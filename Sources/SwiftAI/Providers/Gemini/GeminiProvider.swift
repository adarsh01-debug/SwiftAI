import Foundation

public struct GeminiProvider: AIProvider {
    public let kind: AIProviderKind = .gemini
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
        let payload = try makePayload(from: request)
        let body = try encoder.encode(payload)
        let httpRequest = HTTPRequest(
            method: "POST",
            url: try endpointURL(streaming: false),
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
                    let payload = try makePayload(from: request)
                    let body = try encoder.encode(payload)
                    let httpRequest = HTTPRequest(
                        method: "POST",
                        url: try endpointURL(streaming: true),
                        headers: defaultHeaders(),
                        body: body,
                        timeout: configuration.timeout
                    )
                    let lines = httpClient.streamLines(httpRequest)
                    let events = SSEParser.parse(lines: lines)
                    var assembledText = ""
                    var lastChunk: GeminiStreamChunk?
                    var lastRawPayload: AIProviderRawPayload?
                    var startedEmitted = false
                    for try await event in events {
                        if event.data == "[DONE]" { break }
                        if event.data.isEmpty { continue }
                        // Gemini 2.5 sends multiple JSON objects separated by "\n" in a single SSE event.
                        // Decode each line independently instead of treating the joined string as one JSON.
                        let jsonLines = event.data
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        for jsonLine in jsonLines {
                            do {
                                let chunk = try decodeStreamChunk(jsonLine)
                                lastRawPayload = AIProviderRawPayload(body: jsonLine.data(using: .utf8))
                                if !startedEmitted {
                                    continuation.yield(.started(id: nil))
                                    startedEmitted = true
                                }
                                if let mapped = mapStreamChunk(chunk, assembledText: &assembledText) {
                                    continuation.yield(mapped)
                                }
                                lastChunk = chunk
                            } catch {
                                if let data = jsonLine.data(using: .utf8) {
                                    if let wrapper = try? decoder.decode(GeminiErrorWrapper.self, from: data) {
                                        throw AIError.invalidResponse(wrapper.error.message)
                                    }
                                    if let wrappers = try? decoder.decode([GeminiErrorWrapper].self, from: data),
                                       let first = wrappers.first {
                                        throw AIError.invalidResponse(first.error.message)
                                    }
                                }
                            }
                        }
                    }
                    if let final = lastChunk {
                        continuation.yield(.completed(try normalizedFromChunk(
                            final,
                            fallbackText: assembledText,
                            rawPayload: lastRawPayload
                        ).asAIResponse()))
                    } else {
                        throw AIError.invalidResponse("No content received from Gemini")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makePayload(from request: AIRequest) throws -> GeminiRequest {
        guard !configuration.apiKey.isEmpty else {
            throw AIError.invalidConfiguration("API key is required")
        }

        let allMessages = request.transcript + request.messages
        let contents: [GeminiContent] = allMessages.compactMap { message in
            guard message.role != .system else { return nil }
            let role = message.role == .assistant ? "model" : "user"
            let parts = message.parts.map(mapPart)
            return GeminiContent(role: role, parts: parts)
        }

        let systemInstruction: GeminiSystemInstruction? = request.personalityPrompt.map {
            GeminiSystemInstruction(parts: [GeminiPart(text: $0, inlineData: nil, thought: nil)])
        }

        let generationConfig = GeminiGenerationConfig(
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens
        )

        return GeminiRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig
        )
    }

    private func mapPart(_ part: AIContentPart) -> GeminiPart {
        switch part {
        case .text(let value):
            return GeminiPart(text: value, inlineData: nil, thought: nil)
        case .imageData(let base64, let mimeType):
            return GeminiPart(text: nil, inlineData: GeminiInlineData(mimeType: mimeType, data: base64), thought: nil)
        case .imageURL(let url):
            return GeminiPart(text: url, inlineData: nil, thought: nil)
        }
    }

    private func defaultHeaders() -> [String: String] {
        [
            "Content-Type": "application/json",
            "x-goog-api-key": configuration.apiKey
        ]
    }

    private func endpointURL(streaming: Bool) throws -> URL {
        let action = streaming ? "streamGenerateContent" : "generateContent"
        let base = configuration.baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(configuration.model):\(action)")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if streaming {
            queryItems.append(URLQueryItem(name: "alt", value: "sse"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw AIError.invalidConfiguration("Could not construct Gemini endpoint URL")
        }
        return url
    }

    private func decodeResponse(_ data: Data) throws -> GeminiResponse {
        do {
            return try decoder.decode(GeminiResponse.self, from: data)
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    private func decodeStreamChunk(_ text: String) throws -> GeminiStreamChunk {
        guard let data = text.data(using: .utf8) else {
            throw AIError.streamProtocol("Invalid UTF-8 stream payload")
        }
        return try decoder.decode(GeminiStreamChunk.self, from: data)
    }

    private func mapStreamChunk(_ chunk: GeminiStreamChunk, assembledText: inout String) -> AIStreamEvent? {
        let parts = chunk.candidates?.first?.content?.parts ?? []
        let text = parts.filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.isEmpty else { return nil }
        assembledText += text
        return .textDelta(text)
    }

    private func normalizedFromChunk(
        _ chunk: GeminiStreamChunk,
        fallbackText: String = "",
        rawPayload: AIProviderRawPayload? = nil
    ) throws -> AIProviderResponse {
        let candidate = chunk.candidates?.first
        let parts = candidate?.content?.parts ?? []
        let text = parts.compactMap(\.text).joined()
        let output = fallbackText.isEmpty ? text : fallbackText
        return try AIProviderResponse(
            id: UUID().uuidString,
            model: chunk.modelVersion ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(output)]),
            usage: AIUsage(
                inputTokens: chunk.usageMetadata?.promptTokenCount,
                outputTokens: chunk.usageMetadata?.candidatesTokenCount,
                totalTokens: chunk.usageMetadata?.totalTokenCount
            ),
            finishReason: candidate?.finishReason,
            provider: .gemini,
            rawPayload: rawPayload
        )
    }

    private func normalized(
        response: GeminiResponse,
        fallbackText: String = "",
        rawPayload: AIProviderRawPayload? = nil
    ) throws -> AIProviderResponse {
        let candidate = response.candidates?.first
        let parts = candidate?.content?.parts ?? []
        let text = parts.compactMap(\.text).joined()
        let output = fallbackText.isEmpty ? text : fallbackText
        return try AIProviderResponse(
            id: UUID().uuidString,
            model: response.modelVersion ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(output)]),
            usage: AIUsage(
                inputTokens: response.usageMetadata?.promptTokenCount,
                outputTokens: response.usageMetadata?.candidatesTokenCount,
                totalTokens: response.usageMetadata?.totalTokenCount
            ),
            finishReason: candidate?.finishReason,
            provider: .gemini,
            rawPayload: rawPayload
        )
    }
}
