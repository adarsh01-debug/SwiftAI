import Foundation

public struct AIResponse: Sendable, Codable, Equatable {
    public let id: String
    public let model: String
    public let message: AIMessage
    public let usage: AIUsage?
    public let finishReason: String?
    public let provider: AIProviderKind
    public let providerResponse: AIProviderResponse?

    public init(
        id: String,
        model: String,
        message: AIMessage,
        usage: AIUsage? = nil,
        finishReason: String? = nil,
        provider: AIProviderKind,
        providerResponse: AIProviderResponse? = nil
    ) {
        self.id = id
        self.model = model
        self.message = message
        self.usage = usage
        self.finishReason = finishReason
        self.provider = provider
        self.providerResponse = providerResponse
    }

    public init(providerResponse: AIProviderResponse) {
        self.init(
            id: providerResponse.id,
            model: providerResponse.model,
            message: providerResponse.message,
            usage: providerResponse.usage,
            finishReason: providerResponse.finishReason,
            provider: providerResponse.provider,
            providerResponse: providerResponse
        )
    }
}
