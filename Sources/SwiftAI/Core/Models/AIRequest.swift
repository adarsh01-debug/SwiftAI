import Foundation

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
