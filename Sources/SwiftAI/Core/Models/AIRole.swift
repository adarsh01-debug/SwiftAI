import Foundation

public enum AIRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}
