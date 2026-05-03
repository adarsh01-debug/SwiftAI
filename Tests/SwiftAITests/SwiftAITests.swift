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
        #expect(response.providerResponse?.text == "Hello from OpenAI")
        #expect(response.providerResponse?.rawPayload?.bodyString?.contains("Hello from OpenAI") == true)
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
        #expect(response.providerResponse?.provider == .anthropic)
        #expect(response.providerResponse?.rawPayload?.bodyString?.contains("Hello from Anthropic") == true)
    }

    @Test func geminiSendParsesResponseAndUsesHeaderAuth() async throws {
        let body = """
        {
          "modelVersion": "gemini-1.5-flash",
          "candidates": [
            {
              "finishReason": "STOP",
              "content": {
                "role": "model",
                "parts": [{ "text": "Hello from Gemini" }]
              }
            }
          ],
          "usageMetadata": {
            "promptTokenCount": 6,
            "candidatesTokenCount": 3,
            "totalTokenCount": 9
          }
        }
        """.data(using: .utf8)!
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: ["content-type": "application/json"], body: body))
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .gemini, apiKey: "test-key", model: "gemini-1.5-flash"),
            httpClient: mock
        )

        let response = try await client.send(.init(messages: [.user("Hi")]))

        #expect(response.provider == .gemini)
        #expect(response.message.parts == [.text("Hello from Gemini")])
        #expect(response.usage?.totalTokens == 9)
        #expect(response.providerResponse?.rawPayload?.statusCode == 200)
        #expect(mock.sentRequests.first?.headers["x-goog-api-key"] == "test-key")
        #expect(mock.sentRequests.first?.url.query?.contains("key=") != true)
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

    @Test func geminiStreamingCompletesWithAssembledText() async throws {
        let streamed = [
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello \"}]}}],\"modelVersion\":\"gemini-1.5-flash\"}",
            "",
            "data: {\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"there\"}]}}],\"modelVersion\":\"gemini-1.5-flash\"}",
            ""
        ]
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: Data()), streamLinesData: streamed)
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .gemini, apiKey: "test-key", model: "gemini-1.5-flash"),
            httpClient: mock
        )

        var deltas: [String] = []
        var completedResponse: AIResponse?
        for try await event in client.stream(.init(messages: [.user("Say hi")], stream: true)) {
            switch event {
            case .textDelta(let value):
                deltas.append(value)
            case .completed(let response):
                completedResponse = response
            default:
                break
            }
        }

        #expect(deltas.joined() == "Hello there")
        #expect(completedResponse?.message.parts == [.text("Hello there")])
        #expect(completedResponse?.providerResponse?.rawPayload?.bodyString?.contains("there") == true)
        #expect(mock.streamRequests.first?.headers["x-goog-api-key"] == "test-key")
        #expect(mock.streamRequests.first?.url.query == "alt=sse")
    }

    @Test func anthropicStreamingCompletesFromAssembledText() async throws {
        let streamed = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_stream\",\"model\":\"claude-3-5-sonnet\",\"content\":[],\"usage\":{\"input_tokens\":4}}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Hello \"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"there\"}}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            ""
        ]
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: Data()), streamLinesData: streamed)
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .anthropic, apiKey: "test-key", model: "claude-3-5-sonnet"),
            httpClient: mock
        )

        var completedResponse: AIResponse?
        for try await event in client.stream(.init(messages: [.user("Say hi")], stream: true)) {
            if case .completed(let response) = event {
                completedResponse = response
            }
        }

        #expect(completedResponse?.id == "msg_stream")
        #expect(completedResponse?.message.parts == [.text("Hello there")])
        #expect(completedResponse?.finishReason == "end_turn")
        #expect(completedResponse?.usage?.outputTokens == 2)
    }

    @Test func emptyProviderTextIsInvalidResponse() async throws {
        let body = """
        {
          "id": "resp_empty",
          "model": "gpt-4o-mini",
          "status": "completed",
          "output_text": ""
        }
        """.data(using: .utf8)!
        let mock = MockHTTPClient(sendResponse: .init(statusCode: 200, headers: [:], body: body))
        let client = try SwiftAIClient(
            configuration: AIConfiguration(provider: .openAI, apiKey: "test-key", model: "gpt-4o-mini"),
            httpClient: mock
        )

        do {
            _ = try await client.send(.init(messages: [.user("Hi")]))
            Issue.record("Expected invalid response")
        } catch let error as AIError {
            guard case .invalidResponse = error else {
                Issue.record("Unexpected AIError: \(error)")
                return
            }
        }
    }

    @Test func decodedProviderResponseMustPassValidation() throws {
        let emptyAssistantMessage = try JSONEncoder().encode(AIMessage(role: .assistant, parts: [.text("")]))
        let emptyAssistantMessageJSON = String(data: emptyAssistantMessage, encoding: .utf8)!
        let invalid = """
        {
          "id": "normalized_1",
          "model": "gpt-4o-mini",
          "message": \(emptyAssistantMessageJSON),
          "provider": "openAI"
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(AIProviderResponse.self, from: invalid)
            Issue.record("Expected invalid decoded provider response")
        } catch let error as AIError {
            guard case .invalidResponse = error else {
                Issue.record("Unexpected AIError: \(error)")
                return
            }
        }
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
    private(set) var sentRequests: [HTTPRequest] = []
    private(set) var streamRequests: [HTTPRequest] = []

    init(sendResponse: HTTPResponse, streamLinesData: [String] = []) {
        self.sendResponse = sendResponse
        self.streamLinesData = streamLinesData
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        return sendResponse
    }

    func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            for line in streamLinesData {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
