import Foundation

struct AnthropicStreamEvent: Decodable {
    let type: String
    let message: AnthropicMessageResponse?
    let delta: AnthropicDelta?
    let usage: AnthropicUsage?
    let error: AnthropicStreamError?
}

struct AnthropicDelta: Decodable {
    let text: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case text
        case stopReason = "stop_reason"
    }
}

struct AnthropicStreamError: Decodable {
    let message: String
}
