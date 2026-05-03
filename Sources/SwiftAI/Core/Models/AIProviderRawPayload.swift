import Foundation

public struct AIProviderRawPayload: Sendable, Codable, Equatable {
    public let statusCode: Int?
    public let headers: [String: String]
    public let body: Data?

    public var bodyString: String? {
        guard let body else { return nil }
        return String(data: body, encoding: .utf8)
    }

    public init(statusCode: Int? = nil, headers: [String: String] = [:], body: Data? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}
