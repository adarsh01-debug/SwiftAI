import Foundation

struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsageMetadata?
    let modelVersion: String?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
}

struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}
