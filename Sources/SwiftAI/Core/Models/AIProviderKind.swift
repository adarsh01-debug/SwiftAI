import Foundation

public enum AIProviderKind: String, Sendable, Codable {
    case openAI
    case anthropic
    case gemini
}
