import Foundation

/// Adopt this protocol on any `Decodable` type you want SwiftAI to automatically
/// decode from the AI's JSON response. The SDK will prepend a schema instruction
/// to the personality prompt so the model knows to reply with conforming JSON.
public protocol AIResponseType: Decodable {
    /// A human-readable JSON schema description injected into the system prompt.
    /// Describe the expected fields, types, and any constraints.
    static var jsonSchema: String { get }
}
