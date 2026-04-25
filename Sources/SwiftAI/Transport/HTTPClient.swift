import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    public let timeout: TimeInterval

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, Error>
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = try makeURLRequest(from: request)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.transport("Missing HTTP response")
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partial, item in
                partial[String(describing: item.key)] = String(describing: item.value)
            }
            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: data
            )
        } catch {
            throw AIError.transport(error.localizedDescription)
        }
    }

    public func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try makeURLRequest(from: request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIError.transport("Missing HTTP response")
                    }
                    guard 200..<300 ~= httpResponse.statusCode else {
                        throw AIError.httpStatus(httpResponse.statusCode, nil)
                    }

                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeURLRequest(from request: HTTPRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }
}
