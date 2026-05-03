import Foundation

struct OpenAIResponseBody: Decodable {
    let id: String?
    let model: String?
    let status: String?
    let outputText: String?
    let usage: OpenAIUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case status
        case outputText = "output_text"
        case usage
    }
}

struct OpenAIUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}
