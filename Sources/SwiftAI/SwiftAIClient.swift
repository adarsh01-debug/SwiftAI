import Foundation

public struct SwiftAIClient: Sendable {
    public let configuration: AIConfiguration
    private let provider: any AIProvider

    public init(configuration: AIConfiguration, httpClient: HTTPClient = URLSessionHTTPClient()) throws {
        self.configuration = configuration
        switch configuration.provider {
        case .openAI:
            self.provider = OpenAIProvider(configuration: configuration, httpClient: httpClient)
        case .anthropic:
            self.provider = AnthropicProvider(configuration: configuration, httpClient: httpClient)
        case .gemini:
            self.provider = GeminiProvider(configuration: configuration, httpClient: httpClient)
        }
    }

    /// Sends a request and decodes the AI's JSON response into `T`.
    ///
    /// A schema instruction derived from `T.jsonSchema` is automatically prepended
    /// to the effective personality prompt before the request is sent, telling the
    /// model to reply with JSON that matches `T`. The text content of the response
    /// is then decoded into `T` and returned.
    public func send<T: AIResponseType>(_ request: AIRequest) async throws -> T {
        let merged = mergedRequest(request, schemaInstruction: schemaInstruction(for: T.self))
        let raw = try await provider.send(merged)
        return try decodeTyped(raw)
    }

    /// Sends a request and returns the raw `AIResponse` envelope without any JSON
    /// decoding. Use this when you need access to response metadata (id, usage,
    /// finish reason) or when you are not working with a typed model.
    public func sendRaw(_ request: AIRequest) async throws -> AIResponse {
        try await provider.send(mergedRequest(request))
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        provider.stream(mergedRequest(request))
    }

    // MARK: - Private

    private func schemaInstruction<T: AIResponseType>(for _: T.Type) -> String {
        """
        You must respond with valid JSON only. Do not include markdown code blocks, \
        prose, or any text outside the JSON object. Your response must conform to the \
        following schema:

        \(T.jsonSchema)
        """
    }

    private func mergedRequest(_ request: AIRequest, schemaInstruction: String? = nil) -> AIRequest {
        let mergedTranscript = configuration.defaultTranscript + request.transcript
        let basePersonality = request.personalityPrompt ?? configuration.defaultPersonalityPrompt
        let personalityPrompt: String?

        if let instruction = schemaInstruction {
            if let base = basePersonality, !base.isEmpty {
                personalityPrompt = instruction + "\n\n" + base
            } else {
                personalityPrompt = instruction
            }
        } else {
            personalityPrompt = basePersonality
        }

        return AIRequest(
            messages: request.messages,
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens,
            contextWindow: request.contextWindow ?? configuration.defaultContextWindow,
            personalityPrompt: personalityPrompt,
            transcript: mergedTranscript,
            stream: request.stream,
            metadata: request.metadata
        )
    }

    private func decodeTyped<T: Decodable>(_ response: AIResponse) throws -> T {
        let text = response.message.parts.compactMap { part -> String? in
            if case .text(let t) = part { return t }
            return nil
        }.joined()

        guard let data = text.data(using: .utf8) else {
            throw AIError.decoding("Response text is not valid UTF-8")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.decoding("Could not decode \(T.self) from response: \(error.localizedDescription)")
        }
    }
}
