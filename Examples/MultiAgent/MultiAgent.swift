// MultiAgent.swift
// A2A Example — coordinator server that delegates to a worker agent.
//
// Runs two `A2AServer` instances in one process: a "coordinator" agent
// on port 8080 and a "worker" agent on port 8081. The coordinator uses
// `A2AClient` internally to forward the message to the worker.
//
// This is the only example that imports BOTH A2AServer and A2AClient —
// real multi-agent systems often run both sides.

import Foundation
import A2ACore
import A2AClient
import A2AServer

struct WorkerHandler: A2AHandler {
    func handleMessage(_ message: Message, auth: AuthContext?) async throws -> SendMessageResponse {
        .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("worker: received \(message.textContent.count) chars")],
            contextId: message.contextId
        ))
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "Worker",
            description: "Downstream worker that counts characters.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0")
            ],
            version: "1.0",
            skills: [AgentSkill(id: "count", name: "Count", description: "Counts characters.", tags: ["demo"])]
        )
    }
}

struct CoordinatorHandler: A2AHandler {
    let workerURL: URL

    func handleMessage(_ message: Message, auth: AuthContext?) async throws -> SendMessageResponse {
        // Forward the message to the worker via A2AClient.
        let client = A2AClient(baseURL: workerURL)
        let response = try await client.sendMessage(message)

        let upstream = response.message?.textContent ?? "<no reply>"
        return .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("coordinator forwarded to worker, got: \(upstream)")],
            contextId: message.contextId
        ))
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "Coordinator",
            description: "Delegates incoming messages to a downstream worker.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0")
            ],
            version: "1.0",
            skills: [AgentSkill(id: "delegate", name: "Delegate", description: "Forwards to worker.", tags: ["demo"])]
        )
    }
}

@main
struct MultiAgent {
    static func main() async throws {
        // Boot the worker first.
        let worker = A2AServer(handler: WorkerHandler()).bind("127.0.0.1:8081")
        let coordinator = A2AServer(handler: CoordinatorHandler(
            workerURL: URL(string: "http://127.0.0.1:8081")!
        )).bind("127.0.0.1:8080")

        print("Worker      → http://127.0.0.1:8081")
        print("Coordinator → http://127.0.0.1:8080")

        // Run both concurrently. swift test-driven cancellation would
        // terminate the process on Ctrl-C in production.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await worker.run() }
            group.addTask { try await coordinator.run() }
            for try await _ in group {}
        }
    }
}
