# a2a-swift-server

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

Server runtime for the **[Agent2Agent (A2A) Protocol v1.0](https://a2a-protocol.org/latest/)**, built on [Hummingbird 2](https://github.com/hummingbird-project/hummingbird).

This package provides `A2AServer` — a batteries-included server you plug an `A2AHandler` into. It depends on [`a2a-client-swift`](https://github.com/tolgaki/a2a-client-swift) for wire types and exposes the `A2AServer` product.

> **Why a separate repo?** The client-side `a2a-client-swift` package intentionally has **no** dependencies so that iOS/macOS apps importing `A2AClient` don't pull Hummingbird + SwiftNIO + ~20 transitive packages they never use. If you need both client and server in one project, add both packages.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/tolgaki/a2a-swift-server.git", from: "1.2.0"),
],
targets: [
    .target(
        name: "MyAgentServer",
        dependencies: [
            .product(name: "A2AServer", package: "a2a-swift-server"),
        ]
    )
]
```

`A2AServer` transitively re-exports `A2AClient` (wire types and the client if you want it) so you don't need to import it separately.

## Quickstart

```swift
import A2AServer   // gives you A2AClient's wire types transitively

struct EchoHandler: A2AHandler {
    func handleMessage(_ message: Message, auth: AuthContext?) async throws -> SendMessageResponse {
        .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("echo: \(message.textContent)")]
        ))
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "Echo",
            description: "Echoes the user's message back.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0"),
            ],
            version: "1.0"
        )
    }
}

@main
struct Server {
    static func main() async throws {
        try await A2AServer(handler: EchoHandler())
            .bind("127.0.0.1:8080")
            .run()
    }
}
```

The server automatically exposes:
- `GET /.well-known/agent-card.json` (and `/agent.json` fallback)
- REST routes for all 11 spec operations at `/message:send`, `/tasks/{id}`, etc.
- A single `POST /` JSON-RPC 2.0 endpoint multiplexing all methods

## What's shipped

| Area | Implementation |
|---|---|
| Handler protocol | `A2AHandler` — required: `handleMessage`, `agentCard`; defaulted: streaming, cancel, extended card |
| REST dispatcher | All 11 operations + discovery + AIP-193 error shapes |
| JSON-RPC dispatcher | Single `POST /` route with method multiplexing and JSON-RPC 2.0 error envelopes |
| Streaming | SSE encoder with bare + JSON-RPC-wrapped framing; 15s keepalive |
| Storage | `TaskStore` + `WebhookStore` protocols with `actor`-based in-memory defaults |
| Task cancellation | `TaskRegistry` tracking in-flight Swift Tasks for real cancellation |
| Push notifications | `WebhookDispatcher` with exponential backoff (500ms → 30s × 3) |
| Auth | `Authenticator` protocol + `NoOpBearerAuthenticator` + `APIKeyAuthenticator`; zero third-party auth deps |

## Deployment target

`A2AServer` requires **macOS 14** (Hummingbird 2's floor). The client-side package `a2a-client-swift` stays at macOS 12 / iOS 15 for consumers who only need the client.

## Examples

| Target | What it demonstrates |
| --- | --- |
| `EchoAgent` | Minimal 5-line server handler |
| `CustomHandler` | Multi-skill routing + artifact responses |
| `StreamingAgent` | Full SSE lifecycle with chunked artifacts |
| `PushNotificationsAgent` | Webhook CRUD + dispatch (uses both client and server) |
| `MultiAgent` | Coordinator + worker in one process |

Run any example with `swift run <TargetName>`.

## Tests

`A2AInteropTests` boots `A2AServer` in-process on an ephemeral port and runs `A2AClient` against it over both REST and JSON-RPC. 17 tests covering every core operation.

```
$ swift test
Executed 17 tests, with 0 failures
```

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
