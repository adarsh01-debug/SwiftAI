# SwiftAI

SwiftAI is an SPM-first SDK to connect to multiple AI providers with one unified API.
v1 ships with OpenAI, Anthropic, and Gemini support.

## Features
- One-shot and streaming generation APIs.
- Multimodal input (`text`, `imageURL`, `imageData`).
- Provider-agnostic request/response models.
- Provider-native decoding with validated normalized responses.
- Raw provider payload preservation for debugging.
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
print(response.providerResponse?.text ?? "")
```

## Response Normalization
Each provider decodes its native API response first, then maps it into `AIProviderResponse`.
SwiftAI only treats a response as valid if it can normalize into this shared model.

`AIProviderResponse` guarantees:
- `id`: provider response id, or an SDK-generated id when the provider does not return one.
- `model`: resolved model name from the provider response or configuration.
- `message`: assistant message with displayable text.
- `usage`: token counts when the provider returns them.
- `finishReason`: provider stop/status reason when available.
- `provider`: source provider.
- `rawPayload`: response status, headers, and body for debugging.

For backward compatibility, `client.send(_:)` still returns `AIResponse`.
Use `response.providerResponse` when you need the normalized provider contract or raw payload.

```swift
let response = try await client.send(request)

guard let normalized = response.providerResponse else {
    throw AIError.invalidResponse("Missing normalized provider response")
}

print(normalized.text)
print(normalized.rawPayload?.bodyString ?? "")
```

## Streaming
Streaming is optimized for UI display: providers emit `.textDelta` chunks as text arrives and a final `.completed` response after the stream finishes.
The final response also passes through `AIProviderResponse` validation.

```swift
let request = AIRequest(messages: [.user("Write a haiku about the ocean.")], stream: true)
for try await event in client.stream(request) {
    switch event {
    case let .textDelta(chunk):
        print(chunk, terminator: "")
    case let .completed(response):
        print("\nFinished with: \(response.finishReason ?? "unknown")")
    default:
        break
    }
}
```

If you only need the final answer, use `client.send(_:)`.
If you need progressive rendering, use `client.stream(_:)` and append `.textDelta` values.

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

## Gemini Example
Gemini requests authenticate with the `x-goog-api-key` header.
The API key is not sent as a `?key=` query item.

```swift
let gemini = try SwiftAIClient(
    configuration: AIConfiguration(
        provider: .gemini,
        apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? "",
        model: "gemini-1.5-flash"
    )
)
```

## Add New Providers
Implement `AIProvider` and inject your provider through `SwiftAIClient` construction flow.
Keep provider DTOs private to the provider, then normalize successful responses into `AIProviderResponse`.

Recommended provider flow:
1. Build the provider-native request payload from `AIRequest`.
2. Send the request through `HTTPClient`.
3. Decode the provider-native response DTO.
4. Map the DTO into `AIProviderResponse`.
5. Return `AIResponse(providerResponse:)`.

For streaming providers, emit `.textDelta` events as chunks arrive.
Accumulate the displayed text and emit `.completed(AIResponse(providerResponse: normalized))` once the stream finishes.
