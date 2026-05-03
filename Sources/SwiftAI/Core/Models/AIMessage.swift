import Foundation

public struct AIMessage: Sendable, Codable, Equatable {
    public let role: AIRole
    public let parts: [AIContentPart]

    public init(role: AIRole, parts: [AIContentPart]) {
        self.role = role
        self.parts = parts
    }
}
