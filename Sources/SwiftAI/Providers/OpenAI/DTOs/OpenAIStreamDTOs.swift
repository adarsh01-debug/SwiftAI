import Foundation

struct OpenAIStreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: OpenAIResponseBody?
    let error: OpenAIStreamError?
}

struct OpenAIStreamError: Decodable {
    let message: String
}
