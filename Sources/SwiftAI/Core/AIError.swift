import Foundation

public enum AIError: Error, Sendable, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case invalidRequest(String)
    case unsupportedFeature(String)
    case transport(String)
    case httpStatus(Int, String?)
    case decoding(String)
    case streamProtocol(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .unsupportedFeature(let msg): return "Unsupported feature: \(msg)"
        case .transport(let msg): return "Transport error: \(msg)"
        case .httpStatus(let status, let body): return "HTTP error \(status): \(body ?? "No body")"
        case .decoding(let msg): return "Decoding error: \(msg)"
        case .streamProtocol(let msg): return "Stream protocol error: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
