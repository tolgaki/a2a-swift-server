// EchoAgent.swift
// A2A Server Example — the minimal "hello world" of A2A servers.
//
// What this sample shows
// ----------------------
// • Implementing `A2AHandler` in ~15 lines.
// • Advertising a spec-compliant `AgentCard` with both REST and JSON-RPC
//   interfaces.
// • Booting the server with `A2AServer(handler:).bind("host:port").run()`.
//
// Running the sample
// ------------------
//     swift run EchoAgent
//
// Then hit it with a client:
//     curl http://127.0.0.1:8080/.well-known/agent-card.json
//     curl -X POST http://127.0.0.1:8080/message:send \
//          -H "Content-Type: application/json" \
//          -d '{"message":{"messageId":"1","role":"ROLE_USER","parts":[{"text":"hi"}]}}'

import Foundation
import A2ACore
import A2AServer

struct EchoHandler: A2AHandler {
    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("echo: \(message.textContent)")],
            contextId: message.contextId
        ))
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "EchoAgent",
            description: "A tiny agent that echoes the user's message back.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0"),
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.jsonRPC, protocolVersion: "1.0"),
            ],
            version: "1.0",
            capabilities: AgentCapabilities(streaming: false),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: [
                AgentSkill(
                    id: "echo",
                    name: "Echo",
                    description: "Echoes the user's message back.",
                    tags: ["demo"]
                )
            ]
        )
    }
}

@main
struct EchoAgent {
    static func main() async throws {
        let host = ProcessInfo.processInfo.environment["A2A_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["A2A_PORT"].flatMap(Int.init) ?? 8080

        print("EchoAgent listening on http://\(host):\(port)")
        print("Try: curl http://\(host):\(port)/.well-known/agent-card.json")

        let server = A2AServer(handler: EchoHandler())
            .bind("\(host):\(port)")
        try await server.run()
    }
}
