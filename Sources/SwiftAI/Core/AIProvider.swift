import Foundation

public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    var capabilities: AICapabilities { get }

    func send(_ request: AIRequest) async throws -> AIResponse
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}
