import Foundation

public struct AIRetryPolicy: Sendable, Equatable {
    public let maxRetries: Int
    public let baseDelaySeconds: Double

    public init(maxRetries: Int = 2, baseDelaySeconds: Double = 0.8) {
        self.maxRetries = maxRetries
        self.baseDelaySeconds = baseDelaySeconds
    }
}

public struct AIConfiguration: Sendable, Equatable {
    public let provider: AIProviderKind
    public let apiKey: String
    public let model: String
    public let baseURL: URL
    public let timeout: TimeInterval
    public let retryPolicy: AIRetryPolicy
    public let defaultContextWindow: Int?
    public let defaultPersonalityPrompt: String?
    public let defaultTranscript: [AIMessage]

    public init(
        provider: AIProviderKind,
        apiKey: String,
        model: String,
        baseURL: URL? = nil,
        timeout: TimeInterval = 60,
        retryPolicy: AIRetryPolicy = .init(),
        defaultContextWindow: Int? = nil,
        defaultPersonalityPrompt: String? = nil,
        defaultTranscript: [AIMessage] = []
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL ?? AIConfiguration.defaultBaseURL(for: provider)
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.defaultContextWindow = defaultContextWindow
        self.defaultPersonalityPrompt = defaultPersonalityPrompt
        self.defaultTranscript = defaultTranscript
    }

    static func defaultBaseURL(for provider: AIProviderKind) -> URL {
        switch provider {
        case .openAI:
            return URL(string: "https://api.openai.com/v1")!
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        }
    }
}
