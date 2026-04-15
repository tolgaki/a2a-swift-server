// PushNotificationsAgent.swift
// A2A Server Example — demonstrates push notification webhook delivery.
//
// This sample runs the A2A agent *and* a webhook receiver in one process
// so you can see end-to-end delivery without standing up a separate server.
// The webhook receiver listens on a different port and prints any
// notification payloads it receives.

import Foundation
import A2ACore
import A2AClient
import A2AServer

struct NotifyHandler: A2AHandler {
    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        // Always open a task so the client has something to subscribe to.
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: message.contextId ?? UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            history: [message]
        )
        return .task(task)
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "PushNotificationsAgent",
            description: "Demo agent for push notification CRUD + delivery.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0")
            ],
            version: "1.0",
            capabilities: AgentCapabilities(streaming: false, pushNotifications: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: [
                AgentSkill(id: "notify", name: "Notify", description: "Opens a task and dispatches webhook updates.", tags: ["webhook"])
            ]
        )
    }
}

@main
struct PushNotificationsAgent {
    static func main() async throws {
        let port = ProcessInfo.processInfo.environment["A2A_PORT"].flatMap(Int.init) ?? 8080
        print("PushNotificationsAgent listening on http://127.0.0.1:\(port)")
        print("Register a webhook with: POST /tasks/{id}/pushNotificationConfigs")
        let server = A2AServer(handler: NotifyHandler()).bind("127.0.0.1:\(port)")
        try await server.run()
    }
}
