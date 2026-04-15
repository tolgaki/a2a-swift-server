// EchoHandler.swift
// A2AInteropTests
//
// Minimal test handler used by the in-process server harness.

import Foundation
import A2ACore
import A2AServer

struct EchoHandler: A2AHandler {
    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        // If the user asks to create a task, return a freshly submitted task.
        if message.textContent.lowercased().contains("task") {
            let task = A2ATask(
                id: UUID().uuidString,
                contextId: message.contextId ?? UUID().uuidString,
                status: TaskStatus(
                    state: .submitted,
                    message: nil,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                ),
                history: [message]
            )
            return .task(task)
        }

        // Otherwise echo the message back as an agent message.
        return .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("echo: \(message.textContent)")],
            contextId: message.contextId
        ))
    }

    func handleStreamingMessage(
        _ message: Message,
        auth: AuthContext?
    ) -> AsyncThrowingStream<StreamResponse, Error> {
        let contextId = message.contextId ?? UUID().uuidString
        let taskId = UUID().uuidString
        return AsyncThrowingStream { continuation in
            Task {
                let initial = A2ATask(
                    id: taskId,
                    contextId: contextId,
                    status: TaskStatus(state: .submitted, timestamp: ISO8601DateFormatter().string(from: Date())),
                    history: [message]
                )
                continuation.yield(.task(initial))

                // Emit an artifact chunk.
                let artifact = Artifact(
                    artifactId: "result-1",
                    name: "echo",
                    parts: [.text("echo: \(message.textContent)")]
                )
                continuation.yield(.artifactUpdate(TaskArtifactUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    artifact: artifact,
                    lastChunk: true
                )))

                // Final status update.
                continuation.yield(.statusUpdate(TaskStatusUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    status: TaskStatus(
                        state: .completed,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    ),
                    final: true
                )))
                continuation.finish()
            }
        }
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "Echo",
            description: "Test handler that echoes messages back.",
            supportedInterfaces: [
                AgentInterface(
                    url: baseURL,
                    protocolBinding: AgentInterface.httpJSON,
                    protocolVersion: "1.0"
                ),
                AgentInterface(
                    url: baseURL,
                    protocolBinding: AgentInterface.jsonRPC,
                    protocolVersion: "1.0"
                ),
            ],
            version: "1.0",
            capabilities: AgentCapabilities(streaming: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: [
                AgentSkill(
                    id: "echo",
                    name: "Echo",
                    description: "Echoes the user's message back.",
                    tags: ["test"]
                )
            ]
        )
    }
}
