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
        return normalized(response: decoded)
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
                    var lastResponse: GeminiResponse?
                    var startedEmitted = false
                    for try await event in events {
                        if event.data == "[DONE]" { break }
                        if event.data.isEmpty { continue }
                        guard let chunk = try? decodeResponse(event.data) else { continue }
                        if !startedEmitted {
                            continuation.yield(.started(id: nil))
                            startedEmitted = true
                        }
                        if let text = chunk.candidates?.first?.content?.parts.first?.text, !text.isEmpty {
                            assembledText += text
                            continuation.yield(.textDelta(text))
                        }
                        lastResponse = chunk
                    }
                    if let final = lastResponse {
                        continuation.yield(.completed(normalized(response: final, fallbackText: assembledText)))
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
            GeminiSystemInstruction(parts: [GeminiPart(text: $0, inlineData: nil)])
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
            return GeminiPart(text: value, inlineData: nil)
        case .imageData(let base64, let mimeType):
            return GeminiPart(text: nil, inlineData: GeminiInlineData(mimeType: mimeType, data: base64))
        case .imageURL(let url):
            return GeminiPart(text: url, inlineData: nil)
        }
    }

    private func defaultHeaders() -> [String: String] {
        ["Content-Type": "application/json"]
    }

    private func endpointURL(streaming: Bool) throws -> URL {
        let action = streaming ? "streamGenerateContent" : "generateContent"
        let base = configuration.baseURL
            .appendingPathComponent("models")
            .appendingPathComponent(configuration.model)
            .appendingPathComponent(action)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "key", value: configuration.apiKey)]
        if streaming {
            queryItems.append(URLQueryItem(name: "alt", value: "sse"))
        }
        components.queryItems = queryItems
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

    private func decodeResponse(_ text: String) throws -> GeminiResponse {
        guard let data = text.data(using: .utf8) else {
            throw AIError.streamProtocol("Invalid UTF-8 stream payload")
        }
        return try decodeResponse(data)
    }

    private func normalized(response: GeminiResponse, fallbackText: String = "") -> AIResponse {
        let candidate = response.candidates?.first
        let parts = candidate?.content?.parts ?? []
        let text = parts.compactMap(\.text).joined()
        let output = text.isEmpty ? fallbackText : text
        return AIResponse(
            id: UUID().uuidString,
            model: response.modelVersion ?? configuration.model,
            message: AIMessage(role: .assistant, parts: [.text(output)]),
            usage: AIUsage(
                inputTokens: response.usageMetadata?.promptTokenCount,
                outputTokens: response.usageMetadata?.candidatesTokenCount,
                totalTokens: response.usageMetadata?.totalTokenCount
            ),
            finishReason: candidate?.finishReason,
            provider: .gemini
        )
    }
}

// MARK: - Request DTOs

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "maxOutputTokens"
    }
}

// MARK: - Response DTOs

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsageMetadata?
    let modelVersion: String?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
}

private struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}
