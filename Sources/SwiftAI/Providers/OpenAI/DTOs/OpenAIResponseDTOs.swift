import Foundation

struct OpenAIResponseBody: Decodable {
    let id: String?
    let model: String?
    let status: String?
    let output: [OpenAIOutputItem]?
    let usage: OpenAIUsage?

    var outputText: String? {
        let joined = output?
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap { $0.text }
            .joined() ?? ""
        return joined.isEmpty ? nil : joined
    }

    enum CodingKeys: String, CodingKey {
        case id, model, status, output, usage
    }
}

struct OpenAIOutputItem: Decodable {
    let type: String?
    let role: String?
    let content: [OpenAIOutputContent]?
}

struct OpenAIOutputContent: Decodable {
    let type: String?
    let text: String?
}

struct OpenAIUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens  = "total_tokens"
    }
}
