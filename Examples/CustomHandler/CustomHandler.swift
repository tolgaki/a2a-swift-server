// CustomHandler.swift
// A2A Server Example — a multi-skill handler with keyword-based routing.
//
// What this sample shows
// ----------------------
// • Routing between multiple skills by inspecting the message text.
// • Returning artifacts (structured data parts) rather than plain text.
// • Declaring multiple `AgentSkill` entries on the agent card.
// • Handling the "please create a task" path separately from immediate replies.

import Foundation
import A2ACore
import A2AServer

struct WeatherHandler: A2AHandler {
    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        let text = message.textContent.lowercased()

        if text.contains("weather") {
            return .message(Message(
                messageId: UUID().uuidString,
                role: .agent,
                parts: [
                    .text("Weather lookup:"),
                    .data([
                        "city": AnyCodable("San Francisco"),
                        "temperature_c": AnyCodable(18),
                        "conditions": AnyCodable("Foggy"),
                    ]),
                ],
                contextId: message.contextId
            ))
        }

        if text.contains("report") || text.contains("long") {
            // Simulate a long-running job by returning a task.
            let task = A2ATask(
                id: UUID().uuidString,
                contextId: message.contextId ?? UUID().uuidString,
                status: TaskStatus(
                    state: .submitted,
                    message: Message(
                        messageId: UUID().uuidString,
                        role: .agent,
                        parts: [.text("Weather report scheduled.")]
                    ),
                    timestamp: ISO8601DateFormatter().string(from: Date())
                ),
                history: [message]
            )
            return .task(task)
        }

        return .message(Message(
            messageId: UUID().uuidString,
            role: .agent,
            parts: [.text("Ask me about the weather, or request a report.")],
            contextId: message.contextId
        ))
    }

    func agentCard(baseURL: String) -> AgentCard {
        AgentCard(
            name: "WeatherAgent",
            description: "A demo agent exposing multiple skills and artifact responses.",
            supportedInterfaces: [
                AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON, protocolVersion: "1.0"),
            ],
            version: "1.0",
            capabilities: AgentCapabilities(streaming: false),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain", "application/json"],
            skills: [
                AgentSkill(
                    id: "weather-now",
                    name: "Current Weather",
                    description: "Returns the current weather for a city.",
                    tags: ["weather", "synchronous"],
                    examples: ["what's the weather in SF?"]
                ),
                AgentSkill(
                    id: "weather-report",
                    name: "Weather Report",
                    description: "Generates a detailed weather report as a long-running task.",
                    tags: ["weather", "task", "long-running"],
                    examples: ["generate a weather report for next week"]
                ),
            ]
        )
    }
}

@main
struct CustomHandler {
    static func main() async throws {
        let port = ProcessInfo.processInfo.environment["A2A_PORT"].flatMap(Int.init) ?? 8080
        print("CustomHandler (WeatherAgent) listening on http://127.0.0.1:\(port)")
        let server = A2AServer(handler: WeatherHandler()).bind("127.0.0.1:\(port)")
        try await server.run()
    }
}
