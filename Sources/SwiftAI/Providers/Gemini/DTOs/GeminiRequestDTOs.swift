import Foundation

struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
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
