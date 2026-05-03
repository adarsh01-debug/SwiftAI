import Foundation

public struct AIProviderResponse: Sendable, Codable, Equatable {
    public let id: String
    public let model: String
    public let message: AIMessage
    public let usage: AIUsage?
    public let finishReason: String?
    public let provider: AIProviderKind
    public let rawPayload: AIProviderRawPayload?

    public var text: String {
        message.parts.compactMap { part in
            if case .text(let value) = part { return value }
            return nil
        }.joined()
    }

    public init(
        id: String,
        model: String,
        message: AIMessage,
        usage: AIUsage? = nil,
        finishReason: String? = nil,
        provider: AIProviderKind,
        rawPayload: AIProviderRawPayload? = nil
    ) throws {
        guard !id.isEmpty else {
            throw AIError.invalidResponse("Provider response is missing an id")
        }
        guard !model.isEmpty else {
            throw AIError.invalidResponse("Provider response is missing a model")
        }
        guard message.role == .assistant else {
            throw AIError.invalidResponse("Provider response must normalize to an assistant message")
        }
        let text = message.parts.compactMap { part in
            if case .text(let value) = part { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
            return nil
        }.joined()
        guard !text.isEmpty else {
            throw AIError.invalidResponse("Provider response did not include displayable text")
        }

        self.id = id
        self.model = model
        self.message = message
        self.usage = usage
        self.finishReason = finishReason
        self.provider = provider
        self.rawPayload = rawPayload
    }

    public func asAIResponse() -> AIResponse {
        AIResponse(providerResponse: self)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case message
        case usage
        case finishReason
        case provider
        case rawPayload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            model: container.decode(String.self, forKey: .model),
            message: container.decode(AIMessage.self, forKey: .message),
            usage: container.decodeIfPresent(AIUsage.self, forKey: .usage),
            finishReason: container.decodeIfPresent(String.self, forKey: .finishReason),
            provider: container.decode(AIProviderKind.self, forKey: .provider),
            rawPayload: container.decodeIfPresent(AIProviderRawPayload.self, forKey: .rawPayload)
        )
    }
}
