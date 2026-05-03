import Foundation

public enum AIStreamEvent: Sendable, Equatable {
    case started(id: String?)
    case textDelta(String)
    case contentDelta(AIContentPart)
    case completed(AIResponse)
    case failed(String)
}
