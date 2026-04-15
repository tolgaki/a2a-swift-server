// A2AHandler.swift
// A2AServer

import Foundation
import A2ACore

/// The public protocol users implement to back an A2A server.
///
/// Most handlers only need to provide `handleMessage` and `agentCard`.
/// All other operations (getTask, listTasks, cancelTask, subscribeToTask,
/// and the 4 push notification CRUD methods) are fulfilled by the server
/// framework directly against the configured `TaskStore` and `WebhookStore`.
///
/// ### Example
///
/// ```swift
/// struct EchoHandler: A2AHandler {
///     func handleMessage(_ message: Message, auth: AuthContext?) async throws -> SendMessageResponse {
///         .message(Message.agent(message.textContent))
///     }
///
///     func agentCard(baseURL: String) -> AgentCard {
///         AgentCard(
///             name: "Echo",
///             description: "Echoes the user's message back.",
///             supportedInterfaces: [
///                 AgentInterface(url: baseURL, protocolBinding: AgentInterface.httpJSON)
///             ],
///             version: "1.0"
///         )
///     }
/// }
/// ```
public protocol A2AHandler: Sendable {
    /// Handle a non-streaming message and return either a `Message` (for
    /// immediate replies) or an `A2ATask` (for long-running work).
    ///
    /// - Parameters:
    ///   - message: The inbound user message.
    ///   - auth: Optional caller identity if the server could extract one.
    /// - Returns: A `SendMessageResponse` wrapping either a task or a message.
    func handleMessage(
        _ message: Message,
        auth: AuthContext?
    ) async throws -> SendMessageResponse

    /// Produce the agent card served at `/.well-known/agent-card.json` and
    /// returned to `GetExtendedAgentCard` calls.
    ///
    /// - Parameter baseURL: The public base URL under which the server is
    ///   reachable, derived from the incoming request's Host header. Handlers
    ///   should use this to populate `AgentInterface.url`.
    func agentCard(baseURL: String) -> AgentCard

    // MARK: - Optional

    /// Handle a streaming message. Default: emits a single "Unsupported"
    /// error event.
    func handleStreamingMessage(
        _ message: Message,
        auth: AuthContext?
    ) -> AsyncThrowingStream<StreamResponse, Error>

    /// Called when a client cancels a task via `CancelTask`. The server
    /// framework has already attempted to cancel the underlying Swift Task
    /// via `TaskRegistry`; this hook lets the handler do additional cleanup.
    func onTaskCancelled(id: String, auth: AuthContext?) async throws

    /// Produce the authenticated extended agent card. Default: returns the
    /// same card as `agentCard(baseURL:)`.
    func extendedAgentCard(
        baseURL: String,
        auth: AuthContext
    ) async throws -> AgentCard?

    /// If non-nil, the framework spawns a background task after every
    /// non-terminal `SendMessageResponse.task` return and flips the task
    /// to `completed` after the given duration. Useful for demos.
    var autoCompleteDelay: Duration? { get }
}

extension A2AHandler {
    public func handleStreamingMessage(
        _ message: Message,
        auth: AuthContext?
    ) -> AsyncThrowingStream<StreamResponse, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: A2AError.unsupportedOperation(
                operation: "SendStreamingMessage",
                message: "This agent does not support streaming."
            ))
        }
    }

    public func onTaskCancelled(id: String, auth: AuthContext?) async throws {
        // Default: nothing to do. The framework already cancelled the
        // background task handle via TaskRegistry.
    }

    public func extendedAgentCard(
        baseURL: String,
        auth: AuthContext
    ) async throws -> AgentCard? {
        agentCard(baseURL: baseURL)
    }

    public var autoCompleteDelay: Duration? { nil }
}
