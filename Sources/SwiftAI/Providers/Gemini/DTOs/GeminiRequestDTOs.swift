import Foundation

struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]

    init(role: String, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = (try? container.decode(String.self, forKey: .role)) ?? "model"
        self.parts = (try? container.decode([GeminiPart].self, forKey: .parts)) ?? []
    }
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?
    let thought: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
        case thought
    }
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

struct GeminiGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "maxOutputTokens"
    }
}
