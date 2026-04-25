import Foundation

public extension AIContentPart {
    static func imageData(_ data: Data, mimeType: String) -> AIContentPart {
        .imageData(base64: data.base64EncodedString(), mimeType: mimeType)
    }
}

public extension AIMessage {
    static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, parts: [.text(text)])
    }

    static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, parts: [.text(text)])
    }

    static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, parts: [.text(text)])
    }

    static func user(text: String, imageURL: String) -> AIMessage {
        AIMessage(role: .user, parts: [.text(text), .imageURL(imageURL)])
    }

    static func user(text: String, imageData: Data, mimeType: String) -> AIMessage {
        AIMessage(role: .user, parts: [.text(text), .imageData(base64: imageData.base64EncodedString(), mimeType: mimeType)])
    }
}
