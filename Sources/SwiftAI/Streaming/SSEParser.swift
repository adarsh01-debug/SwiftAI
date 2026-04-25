import Foundation

public struct ServerSentEvent: Sendable, Equatable {
    public let event: String?
    public let data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

public enum SSEParser {
    public static func parse(lines: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var eventName: String?
                    var dataLines: [String] = []

                    for try await line in lines {
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                continuation.yield(
                                    ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"))
                                )
                            }
                            eventName = nil
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let chunk = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                            dataLines.append(chunk)
                        }
                    }

                    if !dataLines.isEmpty {
                        continuation.yield(
                            ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"))
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
