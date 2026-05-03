import Foundation

public enum AIProviderKind: String, Sendable, Codable {
    case openAI
    case anthropic
    case gemini
}

public struct AIUsage: Sendable, Codable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public enum AIRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

public enum AIContentPart: Sendable, Codable, Equatable {
    case text(String)
    case imageData(base64: String, mimeType: String)
    case imageURL(String)
}

public struct AIMessage: Sendable, Codable, Equatable {
    public let role: AIRole
    public let parts: [AIContentPart]

    public init(role: AIRole, parts: [AIContentPart]) {
        self.role = role
        self.parts = parts
    }
}

public struct AIRequest: Sendable, Codable, Equatable {
    public let messages: [AIMessage]
    public let temperature: Double?
    public let maxOutputTokens: Int?
    public let contextWindow: Int?
    public let personalityPrompt: String?
    public let transcript: [AIMessage]
    public let stream: Bool
    public let metadata: [String: String]

    public init(
        messages: [AIMessage],
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        contextWindow: Int? = nil,
        personalityPrompt: String? = nil,
        transcript: [AIMessage] = [],
        stream: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.messages = messages
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.contextWindow = contextWindow
        self.personalityPrompt = personalityPrompt
        self.transcript = transcript
        self.stream = stream
        self.metadata = metadata
    }
}

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

public struct AIProviderRawPayload: Sendable, Codable, Equatable {
    public let statusCode: Int?
    public let headers: [String: String]
    public let body: Data?

    public var bodyString: String? {
        guard let body else { return nil }
        return String(data: body, encoding: .utf8)
    }

    public init(statusCode: Int? = nil, headers: [String: String] = [:], body: Data? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

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

public enum AIStreamEvent: Sendable, Equatable {
    case started(id: String?)
    case textDelta(String)
    case contentDelta(AIContentPart)
    case completed(AIResponse)
    case failed(String)
}

public struct AICapabilities: Sendable, Equatable {
    public let supportsImages: Bool
    public let supportsStreaming: Bool

    public init(supportsImages: Bool, supportsStreaming: Bool) {
        self.supportsImages = supportsImages
        self.supportsStreaming = supportsStreaming
    }
}
