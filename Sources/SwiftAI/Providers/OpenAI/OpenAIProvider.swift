import Foundation

public struct OpenAIProvider: AIProvider {
    public let kind: AIProviderKind = .openAI
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
        let payload = try makeRequestPayload(from: request, stream: false)
        let data = try encoder.encode(payload)
        let httpRequest = HTTPRequest(
            method: "POST",
            url: try endpointURL("responses"),
            headers: defaultHeaders(),
            body: data,
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
                    let payload = try makeRequestPayload(from: request, stream: true)
                    let data = try encoder.encode(payload)
                    let httpRequest = HTTPRequest(
                        method: "POST",
                        url: try endpointURL("responses"),
                        headers: defaultHeaders(),
                        body: data,
                        timeout: configuration.timeout
                    )
                    let lines = httpClient.streamLines(httpRequest)
                    let events = SSEParser.parse(lines: lines)
                    for try await event in events {
                        if event.data == "[DONE]" { break }
                        let parsed = try decodeStreamEvent(event.data)
                        if let streamEvent = mapStreamEvent(parsed) {
                            continuation.yield(streamEvent)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeRequestPayload(from request: AIRequest, stream: Bool) throws -> OpenAIResponseRequest {
        guard !configuration.apiKey.isEmpty else {
            throw AIError.invalidConfiguration("API key is required")
        }
        let allMessages = request.transcript + request.messages
        let input = allMessages.map { message in
            OpenAIInputMessage(role: message.role.rawValue, content: message.parts.map(mapPart))
        }
        return OpenAIResponseRequest(
            model: configuration.model,
            input: input,
            instructions: request.personalityPrompt,
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens,
            stream: stream
        )
    }

    private func mapPart(_ part: AIContentPart) -> OpenAIInputContent {
        switch part {
        case .text(let text):
            return .init(type: "input_text", text: text, imageURL: nil)
        case .imageData(let base64, let mimeType):
            return .init(type: "input_image", text: nil, imageURL: "data:\(mimeType);base64,\(base64)")
        case .imageURL(let url):
            return .init(type: "input_image", text: nil, imageURL: url)
        }
    }

    private func defaultHeaders() -> [String: String] {
        [
            "Authorization": "Bearer \(configuration.apiKey)",
            "Content-Type": "application/json"
        ]
    }

    private func endpointURL(_ path: String) throws -> URL {
        return configuration.baseURL.appendingPathComponent(path)
    }

    private func decodeResponse(_ data: Data) throws -> OpenAIResponseBody {
        do {
            return try decoder.decode(OpenAIResponseBody.self, from: data)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    private func decodeStreamEvent(_ text: String) throws -> OpenAIStreamEvent {
        guard let data = text.data(using: .utf8) else {
            throw AIError.streamProtocol("Invalid UTF-8 stream payload")
        }
        do {
            return try decoder.decode(OpenAIStreamEvent.self, from: data)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    private func mapStreamEvent(_ event: OpenAIStreamEvent) -> AIStreamEvent? {
        if event.type == "response.created" {
            return .started(id: event.response?.id)
        }
        if let delta = event.delta, !delta.isEmpty {
            return .textDelta(delta)
        }
        if event.type == "response.completed", let response = event.response {
            return .completed(normalized(response: response))
        }
        if event.type == "error" {
            return .failed(event.error?.message ?? "Unknown stream error")
        }
        return nil
    }

    private func normalized(response: OpenAIResponseBody) -> AIResponse {
        let text = response.outputText ?? ""
        return AIResponse(
            id: response.id ?? UUID().uuidString,
            model: response.model ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(text)]),
            usage: AIUsage(
                inputTokens: response.usage?.inputTokens,
                outputTokens: response.usage?.outputTokens,
                totalTokens: response.usage?.totalTokens
            ),
            finishReason: response.status,
            provider: .openAI
        )
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let input: [OpenAIInputMessage]
    let instructions: String?
    let temperature: Double?
    let maxOutputTokens: Int?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case stream
    }
}

private struct OpenAIInputMessage: Encodable {
    let role: String
    let content: [OpenAIInputContent]
}

private struct OpenAIInputContent: Encodable {
    let type: String
    let text: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct OpenAIResponseBody: Decodable {
    let id: String?
    let model: String?
    let status: String?
    let outputText: String?
    let usage: OpenAIUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case status
        case outputText = "output_text"
        case usage
    }
}

private struct OpenAIUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct OpenAIStreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: OpenAIResponseBody?
    let error: OpenAIStreamError?
}

private struct OpenAIStreamError: Decodable {
    let message: String
}
