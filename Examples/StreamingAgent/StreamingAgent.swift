// StreamingAgent.swift
// A2A Server Example — demonstrates streaming responses via SSE.
//
// What this sample shows
// ----------------------
// • Implementing `handleStreamingMessage` to emit the full task lifecycle
//   (Submitted → Working → Artifact chunks → Completed) over SSE.
// • Using `AsyncThrowingStream` to produce stream events from a handler.
// • Advertising `capabilities.streaming = true` in the agent card.
//
// Running the sample
// ------------------
//     swift run StreamingAgent
//     curl -N -X POST http://127.0.0.1:8080/message:stream \
//          -H "Content-Type: application/json" \
//          -d '{"message":{"messageId":"1","role":"ROLE_USER","parts":[{"text":"tell me a story"}]}}'

import Foundation
import A2ACore
import A2AServer

struct StoryHandler: A2AHandler {
    var supportsStreaming: Bool { true }

    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        // Non-streaming path: return a single message.
        .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("Streaming is the interesting path — try /message:stream instead.")],
            contextId: message.contextId
        ))
    }

    func handleStreamingMessage(
        _ message: Message,
        auth: AuthContext?
    ) -> AsyncThrowingStream<StreamResponse, Error> {
        let contextId = message.contextId ?? UUID().uuidString
        let taskId = UUID().uuidString
        let chunks = [
            "Once upon a time, ",
            "a curious developer ",
            "discovered the A2A protocol ",
            "and built their first agent.",
        ]

        return AsyncThrowingStream { continuation in
            Task {
                // 1. Initial Task snapshot (submitted state).
                let initialTask = A2ATask(
                    id: taskId,
                    contextId: contextId,
                    status: TaskStatus(
                        state: .submitted,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    ),
                    history: [message]
                )
                continuation.yield(.task(initialTask))

                // 2. Status update → working.
                continuation.yield(.statusUpdate(TaskStatusUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    status: TaskStatus(
                        state: .working,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    )
                )))

                // 3. Stream the story as chunked artifact updates.
                let artifactId = "story-1"
                for (index, chunk) in chunks.enumerated() {
                    try? await Task.sleep(for: .milliseconds(50))
                    continuation.yield(.artifactUpdate(TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        artifact: Artifact(
                            artifactId: artifactId,
                            name: "story",
                            parts: [.text(chunk)]
                        ),
                        append: index > 0,
                        lastChunk: index == chunks.count - 1
                    )))
                }

                // 4. Final status update → completed.
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
            name: "StreamingAgent",
            description: "Streams a short story as chunked artifact updates.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0"),
            ],
            version: "1.0",
            capabilities: AgentCapabilities(streaming: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: [
                AgentSkill(
                    id: "story",
                    name: "Story Streaming",
                    description: "Streams a short story token-by-token.",
                    tags: ["streaming", "demo"]
                )
            ]
        )
    }
}

@main
struct StreamingAgent {
    static func main() async throws {
        let port = ProcessInfo.processInfo.environment["A2A_PORT"].flatMap(Int.init) ?? 8080
        print("StreamingAgent listening on http://127.0.0.1:\(port)")
        let server = A2AServer(handler: StoryHandler()).bind("127.0.0.1:\(port)")
        try await server.run()
    }
}
