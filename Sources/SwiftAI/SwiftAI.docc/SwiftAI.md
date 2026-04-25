# ``SwiftAI``

SwiftAI is a protocol-oriented Swift Package for talking to multiple AI providers.

## Overview

Use ``SwiftAIClient`` with an ``AIConfiguration`` to call OpenAI or Anthropic with
the same request and response models.

- One-shot: ``SwiftAIClient/send(_:)``
- Streaming: ``SwiftAIClient/stream(_:)``

## Topics

### Essentials

- ``SwiftAIClient``
- ``AIConfiguration``
- ``AIRequest``
- ``AIResponse``
- ``AIProvider``
