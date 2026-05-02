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

    public init(
        id: String,
        model: String,
        message: AIMessage,
        usage: AIUsage? = nil,
        finishReason: String? = nil,
        provider: AIProviderKind
    ) {
        self.id = id
        self.model = model
        self.message = message
        self.usage = usage
        self.finishReason = finishReason
        self.provider = provider
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
