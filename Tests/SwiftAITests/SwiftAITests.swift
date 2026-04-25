import Testing
import Foundation
@testable import SwiftAI

struct SwiftAITests {
    @Test func openAISendParsesResponse() async throws {
        let body = """
        {
          "id": "resp_1",
          "model": "gpt-4o-mini",
          "status": "completed",
          "output_text": "Hello from OpenAI",
          "usage": {
            "input_tokens": 10,
            "output_tokens": 5,
            "total_tokens": 15
          }
        }
        """.data(using: .utf8)!
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: body))
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .openAI, apiKey: "test-key", model: "gpt-4o-mini"),
            httpClient: mock
        )

        let response = try await client.send(.init(messages: [.user("Hi")]))

        #expect(response.provider == .openAI)
        #expect(response.message.parts == [.text("Hello from OpenAI")])
        #expect(response.usage?.totalTokens == 15)
    }

    @Test func anthropicSendParsesResponse() async throws {
        let body = """
        {
          "id": "msg_1",
          "model": "claude-3-5-sonnet",
          "stop_reason": "end_turn",
          "content": [{ "type": "text", "text": "Hello from Anthropic" }],
          "usage": { "input_tokens": 8, "output_tokens": 4 }
        }
        """.data(using: .utf8)!
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: body))
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .anthropic, apiKey: "test-key", model: "claude-3-5-sonnet"),
            httpClient: mock
        )

        let response = try await client.send(.init(messages: [.user("Hi")]))
        #expect(response.provider == .anthropic)
        #expect(response.message.parts == [.text("Hello from Anthropic")])
    }

    @Test func openAIStreamingYieldsTextAndCompletion() async throws {
        let streamed = [
            "event: response.created",
            "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_stream\",\"model\":\"gpt-4o-mini\",\"status\":\"in_progress\",\"output_text\":\"\"}}",
            "",
            "event: response.output_text.delta",
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello \"}",
            "",
            "event: response.output_text.delta",
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"there\"}",
            "",
            "event: response.completed",
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_stream\",\"model\":\"gpt-4o-mini\",\"status\":\"completed\",\"output_text\":\"Hello there\"}}",
            ""
        ]
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: Data()), streamLinesData: streamed)
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .openAI, apiKey: "test-key", model: "gpt-4o-mini"),
            httpClient: mock
        )

        var deltas: [String] = []
        var completed = false
        let streamingRequest = AIRequest(messages: [.user("Say hi")], stream: true)
        for try await event in client.stream(streamingRequest) {
            switch event {
            case .textDelta(let value):
                deltas.append(value)
            case .completed(let response):
                completed = true
                #expect(response.message.parts == [.text("Hello there")])
            default:
                break
            }
        }
        #expect(deltas.joined() == "Hello there")
        #expect(completed)
    }

    @Test func authFailureMapsToHTTPError() async throws {
        let body = #"{"error":"unauthorized"}"#.data(using: .utf8)!
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 401, headers: [:], body: body))
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .openAI, apiKey: "bad-key", model: "gpt-4o-mini"),
            httpClient: mock
        )

        do {
            _ = try await client.send(.init(messages: [.user("Hi")]))
            Issue.record("Expected HTTP error")
        } catch let error as AIError {
            if case .httpStatus(401, _) = error { return }
            Issue.record("Unexpected AIError: \(error)")
        }
    }
}

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var sendResponse: HTTPResponse
    var streamLinesData: [String]

    init(sendResponse: HTTPResponse, streamLinesData: [String] = []) {
        self.sendResponse = sendResponse
        self.streamLinesData = streamLinesData
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        _ = request
        return sendResponse
    }

    func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        _ = request
        return AsyncThrowingStream { continuation in
            for line in streamLinesData {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
