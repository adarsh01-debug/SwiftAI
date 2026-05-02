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

    public func send(_ request: AIRequest) async throws -> AIResponse {
        try await provider.send(mergedRequest(request))
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        provider.stream(mergedRequest(request))
    }

    private func mergedRequest(_ request: AIRequest) -> AIRequest {
        let mergedTranscript = configuration.defaultTranscript + request.transcript
        return AIRequest(
            messages: request.messages,
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens,
            contextWindow: request.contextWindow ?? configuration.defaultContextWindow,
            personalityPrompt: request.personalityPrompt ?? configuration.defaultPersonalityPrompt,
            transcript: mergedTranscript,
            stream: request.stream,
            metadata: request.metadata
        )
    }
}
