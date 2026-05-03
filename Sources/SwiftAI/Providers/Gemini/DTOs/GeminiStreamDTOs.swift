import Foundation

// Each SSE data payload from Gemini's streamGenerateContent endpoint is a
// complete GenerateContentResponse JSON object, not a typed event envelope.
// A sequence of chunks builds up the full response; only the final chunk
// carries usageMetadata and modelVersion.
struct GeminiStreamChunk: Decodable {
    let candidates: [GeminiStreamCandidate]?
    let usageMetadata: GeminiUsageMetadata?
    let modelVersion: String?
}

struct GeminiStreamCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
}

struct GeminiStreamError: Decodable {
    let message: String
}
