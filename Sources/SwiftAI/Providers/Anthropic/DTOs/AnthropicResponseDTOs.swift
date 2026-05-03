import Foundation

struct AnthropicResponse: Decodable {
    let id: String
    let model: String
    let stopReason: String?
    let content: [AnthropicTextBlock]
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case stopReason = "stop_reason"
        case content
        case usage
    }

    func asMessageResponse() -> AnthropicMessageResponse {
        AnthropicMessageResponse(
            id: id,
            model: model,
            stopReason: stopReason,
            content: content,
            usage: usage
        )
    }
}

struct AnthropicMessageResponse: Decodable {
    let id: String
    let model: String
    let stopReason: String?
    let content: [AnthropicTextBlock]
    let usage: AnthropicUsage?
}

struct AnthropicTextBlock: Decodable {
    let type: String
    let text: String?
}

struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
