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
        return try normalized(
            response: decoded,
            rawPayload: .init(statusCode: response.statusCode, headers: response.headers, body: response.body)
        ).asAIResponse()
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
                        if event.data.isEmpty { continue }
                        // The Responses API emits many event types; skip any
                        // whose shape doesn't match our model rather than throwing.
                        guard let parsed = try? decodeStreamEvent(event.data) else { continue }
                        let rawPayload = AIProviderRawPayload(body: event.data.data(using: .utf8))
                        if let streamEvent = try mapStreamEvent(parsed, rawPayload: rawPayload) {
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
            OpenAIInputMessage(role: message.role.rawValue, content: message.parts.map { mapPart($0, role: message.role) })
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

    private func mapPart(_ part: AIContentPart, role: AIRole) -> OpenAIInputContent {
        switch part {
        case .text(let text):
            // OpenAI Responses API requires "output_text" for assistant turns,
            // and "input_text" for user/system turns.
            let type = role == .assistant ? "output_text" : "input_text"
            return .init(type: type, text: text, imageURL: nil)
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

    private func mapStreamEvent(_ event: OpenAIStreamEvent, rawPayload: AIProviderRawPayload?) throws -> AIStreamEvent? {
        if event.type == "response.created" {
            return .started(id: event.response?.id)
        }
        if let delta = event.delta, !delta.isEmpty {
            return .textDelta(delta)
        }
        if event.type == "response.completed", let response = event.response {
            return try .completed(normalized(response: response, rawPayload: rawPayload).asAIResponse())
        }
        if event.type == "error" {
            return .failed(event.error?.message ?? "Unknown stream error")
        }
        return nil
    }

    private func normalized(response: OpenAIResponseBody, rawPayload: AIProviderRawPayload? = nil) throws -> AIProviderResponse {
        let text = response.outputText ?? ""
        return try AIProviderResponse(
            id: response.id ?? UUID().uuidString,
            model: response.model ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(text)]),
            usage: AIUsage(
                inputTokens: response.usage?.inputTokens,
                outputTokens: response.usage?.outputTokens,
                totalTokens: response.usage?.totalTokens
            ),
            finishReason: response.status,
            provider: .openAI,
            rawPayload: rawPayload
        )
    }
}
