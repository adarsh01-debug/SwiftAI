# SwiftAI

SwiftAI is an SPM-first SDK to connect to multiple AI providers with one unified API.
v1 ships with OpenAI and Anthropic support.

## Features
- One-shot and streaming generation APIs.
- Multimodal input (`text`, `imageURL`, `imageData`).
- Provider-agnostic request/response models.
- Extensible provider protocol for adding more models later.

## Quickstart
```swift
import SwiftAI

let client = try SwiftAIClient(
    configuration: AIConfiguration(
        provider: .openAI,
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
        model: "gpt-4o-mini",
        defaultPersonalityPrompt: "You are a concise assistant."
    )
)

let request = AIRequest(messages: [.user("Summarize Swift concurrency in 4 points.")])
let response = try await client.send(request)
print(response.message)
```

## Streaming
```swift
let request = AIRequest(messages: [.user("Write a haiku about the ocean.")], stream: true)
for try await event in client.stream(request) {
    if case let .textDelta(chunk) = event {
        print(chunk, terminator: "")
    }
}
```

## Anthropic Example
```swift
let anthropic = try SwiftAIClient(
    configuration: AIConfiguration(
        provider: .anthropic,
        apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "",
        model: "claude-3-5-sonnet-latest"
    )
)
```

## Add New Providers
Implement `AIProvider` and inject your provider through `SwiftAIClient` construction flow.
The core request/response contracts are intentionally provider-agnostic.
