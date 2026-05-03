import Foundation

public enum AIContentPart: Sendable, Codable, Equatable {
    case text(String)
    case imageData(base64: String, mimeType: String)
    case imageURL(String)
}
