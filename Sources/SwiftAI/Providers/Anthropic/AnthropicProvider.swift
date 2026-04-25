import Foundation

public struct AnthropicProvider: AIProvider {
    public let kind: AIProviderKind = .anthropic
    public let capabilities = AICapabilities(supportsImages: true, supportsStreaming: true)

    private let configuration: AIConfiguration
    private let httpClient: HTTPClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(configuration: AIConfiguration, httpClient: HTTPClient) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func send(_ request: AIRequest) async throws -> AIResponse {
        let payload = try makePayload(from: request, stream: false)
        let body = try encoder.encode(payload)
        let httpRequest = HTTPRequest(
            method: "POST",
            url: try endpointURL("messages"),
            headers: defaultHeaders(),
            body: body,
            timeout: configuration.timeout
        )
        let response = try await httpClient.send(httpRequest)
        guard 200..<300 ~= response.statusCode else {
            throw AIError.httpStatus(response.statusCode, String(data: response.body, encoding: .utf8))
        }
        let decoded = try decodeResponse(response.body)
        return normalized(response: decoded)
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let payload = try makePayload(from: request, stream: true)
                    let body = try encoder.encode(payload)
                    let httpRequest = HTTPRequest(
                        method: "POST",
                        url: try endpointURL("messages"),
                        headers: defaultHeaders(),
                        body: body,
                        timeout: configuration.timeout
                    )
                    let lines = httpClient.streamLines(httpRequest)
                    let events = SSEParser.parse(lines: lines)
                    var assembledText = ""
                    for try await event in events {
                        if event.data == "[DONE]" { break }
                        let parsed = try decodeStreamEvent(event.data)
                        if let mapped = mapStreamEvent(parsed, assembledText: &assembledText) {
                            continuation.yield(mapped)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makePayload(from request: AIRequest, stream: Bool) throws -> AnthropicRequest {
        guard !configuration.apiKey.isEmpty else {
            throw AIError.invalidConfiguration("API key is required")
        }

        let allMessages = request.transcript + request.messages
        let systemPrompt = request.personalityPrompt
        let filteredMessages = allMessages.filter { $0.role != .system }.map { message in
            AnthropicMessage(role: message.role == .assistant ? "assistant" : "user", content: message.parts.map(mapPart))
        }
        return AnthropicRequest(
            model: configuration.model,
            maxTokens: request.maxOutputTokens ?? 1024,
            temperature: request.temperature,
            system: systemPrompt,
            messages: filteredMessages,
            stream: stream
        )
    }

    private func mapPart(_ part: AIContentPart) -> AnthropicContent {
        switch part {
        case .text(let value):
            return AnthropicContent(type: "text", text: value, source: nil)
        case .imageData(let base64, let mimeType):
            return AnthropicContent(
                type: "image",
                text: nil,
                source: .init(type: "base64", mediaType: mimeType, data: base64)
            )
        case .imageURL(let rawURL):
            return AnthropicContent(type: "text", text: rawURL, source: nil)
        }
    }

    private func defaultHeaders() -> [String: String] {
        [
            "x-api-key": configuration.apiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        ]
    }

    private func endpointURL(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw AIError.invalidConfiguration("Invalid base URL")
        }
        return url
    }

    private func decodeResponse(_ data: Data) throws -> AnthropicResponse {
        do {
            return try decoder.decode(AnthropicResponse.self, from: data)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    private func decodeStreamEvent(_ eventPayload: String) throws -> AnthropicStreamEvent {
        guard let data = eventPayload.data(using: .utf8) else {
            throw AIError.streamProtocol("Invalid UTF-8 stream payload")
        }
        do {
            return try decoder.decode(AnthropicStreamEvent.self, from: data)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    private func mapStreamEvent(_ event: AnthropicStreamEvent, assembledText: inout String) -> AIStreamEvent? {
        switch event.type {
        case "message_start":
            return .started(id: event.message?.id)
        case "content_block_delta":
            if let text = event.delta?.text, !text.isEmpty {
                assembledText += text
                return .textDelta(text)
            }
            return nil
        case "message_stop":
            if let message = event.message {
                return .completed(normalized(response: message, fallbackText: assembledText))
            }
            return nil
        case "error":
            return .failed(event.error?.message ?? "Unknown stream error")
        default:
            return nil
        }
    }

    private func normalized(response: AnthropicResponse, fallbackText: String = "") -> AIResponse {
        normalized(response: response.asMessageResponse(), fallbackText: fallbackText)
    }

    private func normalized(response: AnthropicMessageResponse, fallbackText: String = "") -> AIResponse {
        let textParts = response.content.compactMap { block -> String? in
            guard block.type == "text" else { return nil }
            return block.text
        }
        let messageText = textParts.joined()
        let output = messageText.isEmpty ? fallbackText : messageText
        return AIResponse(
            id: response.id,
            model: response.model,
            message: AIMessage(role: .assistant, parts: [.text(output)]),
            usage: AIUsage(
                inputTokens: response.usage?.inputTokens,
                outputTokens: response.usage?.outputTokens,
                totalTokens: nil
            ),
            finishReason: response.stopReason,
            provider: .anthropic
        )
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double?
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
        case stream
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContent]
}

private struct AnthropicContent: Encodable {
    let type: String
    let text: String?
    let source: AnthropicImageSource?
}

private struct AnthropicImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct AnthropicResponse: Decodable {
    let id: String
    let model: String
    let stopReason: String?
    let content: [AnthropicTextBlock]
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case stopReason = "stop_reason"
        case content
        case usage
    }

    func asMessageResponse() -> AnthropicMessageResponse {
        AnthropicMessageResponse(
            id: id,
            model: model,
            stopReason: stopReason,
            content: content,
            usage: usage
        )
    }
}

private struct AnthropicMessageResponse: Decodable {
    let id: String
    let model: String
    let stopReason: String?
    let content: [AnthropicTextBlock]
    let usage: AnthropicUsage?
}

private struct AnthropicTextBlock: Decodable {
    let type: String
    let text: String?
}

private struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let message: AnthropicMessageResponse?
    let delta: AnthropicDelta?
    let error: AnthropicStreamError?
}

private struct AnthropicDelta: Decodable {
    let text: String?
}

private struct AnthropicStreamError: Decodable {
    let message: String
}
