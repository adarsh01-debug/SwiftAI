import Foundation

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double?
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
        case stream
    }
}

struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContent]
}

struct AnthropicContent: Encodable {
    let type: String
    let text: String?
    let source: AnthropicImageSource?
}

struct AnthropicImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}
