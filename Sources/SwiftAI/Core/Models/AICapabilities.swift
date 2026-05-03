import Foundation

public struct AICapabilities: Sendable, Equatable {
    public let supportsImages: Bool
    public let supportsStreaming: Bool

    public init(supportsImages: Bool, supportsStreaming: Bool) {
        self.supportsImages = supportsImages
        self.supportsStreaming = supportsStreaming
    }
}
