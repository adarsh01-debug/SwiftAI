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
        return try normalized(
            response: decoded,
            rawPayload: .init(statusCode: response.statusCode, headers: response.headers, body: response.body)
        ).asAIResponse()
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
                    var startedMessage: AnthropicMessageResponse?
                    var stopReason: String?
                    var streamUsage: AnthropicUsage?
                    var lastRawPayload: AIProviderRawPayload?
                    var completedEmitted = false
                    for try await event in events {
                        if event.data == "[DONE]" { break }
                        let parsed = try decodeStreamEvent(event.data)
                        lastRawPayload = AIProviderRawPayload(body: event.data.data(using: .utf8))
                        if let mapped = try mapStreamEvent(
                            parsed,
                            assembledText: &assembledText,
                            startedMessage: &startedMessage,
                            stopReason: &stopReason,
                            streamUsage: &streamUsage,
                            rawPayload: lastRawPayload
                        ) {
                            if case .completed = mapped {
                                completedEmitted = true
                            }
                            continuation.yield(mapped)
                        }
                    }
                    if !completedEmitted && !assembledText.isEmpty {
                        let completed = try normalized(
                            response: startedMessage,
                            fallbackText: assembledText,
                            stopReason: stopReason,
                            usage: streamUsage,
                            rawPayload: lastRawPayload
                        )
                        continuation.yield(.completed(completed.asAIResponse()))
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
        return configuration.baseURL.appendingPathComponent(path)
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

    private func mapStreamEvent(
        _ event: AnthropicStreamEvent,
        assembledText: inout String,
        startedMessage: inout AnthropicMessageResponse?,
        stopReason: inout String?,
        streamUsage: inout AnthropicUsage?,
        rawPayload: AIProviderRawPayload?
    ) throws -> AIStreamEvent? {
        switch event.type {
        case "message_start":
            startedMessage = event.message
            return .started(id: event.message?.id)
        case "content_block_delta":
            if let text = event.delta?.text, !text.isEmpty {
                assembledText += text
                return .textDelta(text)
            }
            return nil
        case "message_delta":
            stopReason = event.delta?.stopReason ?? stopReason
            streamUsage = event.usage ?? streamUsage
            return nil
        case "message_stop":
            if let message = event.message {
                return try .completed(normalized(response: message, fallbackText: assembledText, rawPayload: rawPayload).asAIResponse())
            }
            return nil
        case "error":
            return .failed(event.error?.message ?? "Unknown stream error")
        default:
            return nil
        }
    }

    private func normalized(
        response: AnthropicResponse,
        fallbackText: String = "",
        rawPayload: AIProviderRawPayload? = nil
    ) throws -> AIProviderResponse {
        try normalized(response: response.asMessageResponse(), fallbackText: fallbackText, rawPayload: rawPayload)
    }

    private func normalized(
        response: AnthropicMessageResponse?,
        fallbackText: String = "",
        stopReason: String? = nil,
        usage: AnthropicUsage? = nil,
        rawPayload: AIProviderRawPayload? = nil
    ) throws -> AIProviderResponse {
        let textParts = response?.content.compactMap { block -> String? in
            guard block.type == "text" else { return nil }
            return block.text
        } ?? []
        let messageText = textParts.joined()
        let output = fallbackText.isEmpty ? messageText : fallbackText
        let resolvedUsage = usage ?? response?.usage
        return try AIProviderResponse(
            id: response?.id ?? UUID().uuidString,
            model: response?.model ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(output)]),
            usage: AIUsage(
                inputTokens: resolvedUsage?.inputTokens,
                outputTokens: resolvedUsage?.outputTokens,
                totalTokens: nil
            ),
            finishReason: stopReason ?? response?.stopReason,
            provider: .anthropic,
            rawPayload: rawPayload
        )
    }
}
