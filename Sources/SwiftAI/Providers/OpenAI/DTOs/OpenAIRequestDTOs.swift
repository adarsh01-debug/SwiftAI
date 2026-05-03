import Foundation

struct OpenAIResponseRequest: Encodable {
    let model: String
    let input: [OpenAIInputMessage]
    let instructions: String?
    let temperature: Double?
    let maxOutputTokens: Int?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case stream
    }
}

struct OpenAIInputMessage: Encodable {
    let role: String
    let content: [OpenAIInputContent]
}

struct OpenAIInputContent: Encodable {
    let type: String
    let text: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}
