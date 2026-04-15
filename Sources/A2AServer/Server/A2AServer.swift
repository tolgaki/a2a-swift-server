// A2AServer.swift
// A2AServer
//
// Public entry point for running an A2A server. Wraps Hummingbird's
// Application with an A2A-shaped builder API.

import Foundation
import Hummingbird
import A2ACore

/// Runs an A2A Protocol v1.0 server on top of Hummingbird.
///
/// ### Example
///
/// ```swift
/// import A2AServer
///
/// struct EchoHandler: A2AHandler {
///     func handleMessage(_ message: Message, auth: AuthContext?) async throws -> SendMessageResponse {
///         .message(.agent(message.textContent))
///     }
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
///
/// let server = A2AServer(handler: EchoHandler())
///     .bind("127.0.0.1:8080")
/// try await server.run()
/// ```
public final class A2AServer: Sendable {
    public struct Options: Sendable {
        public var host: String = "127.0.0.1"
        public var port: Int = 8080
        public var rpcPath: String = "/"
        public var restPrefix: String = ""
        public var requireAuth: Bool = false

        public init() {}
    }

    private let handler: any A2AHandler
    private let taskStore: any TaskStore
    private let webhookStore: any WebhookStore
    private let authenticator: any Authenticator
    private let options: Options
    private let appBox: AppBox

    private final class AppBox: @unchecked Sendable {
        var boundPort: Int?
    }

    /// Creates a new server backed by the given handler.
    public init(
        handler: any A2AHandler,
        taskStore: any TaskStore = InMemoryTaskStore(),
        webhookStore: any WebhookStore = InMemoryWebhookStore(),
        authenticator: any Authenticator = NoOpBearerAuthenticator(),
        options: Options = Options()
    ) {
        self.handler = handler
        self.taskStore = taskStore
        self.webhookStore = webhookStore
        self.authenticator = authenticator
        self.options = options
        self.appBox = AppBox()
    }

    /// Returns a new server with the given bind address.
    public func bind(_ address: String) -> A2AServer {
        var newOptions = options
        let parts = address.split(separator: ":")
        if parts.count == 2 {
            newOptions.host = String(parts[0])
            newOptions.port = Int(parts[1]) ?? 8080
        }
        return A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: authenticator,
            options: newOptions
        )
    }

    /// Returns a new server with the given JSON-RPC mount path.
    public func rpcPath(_ path: String) -> A2AServer {
        var newOptions = options
        newOptions.rpcPath = path
        return A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: authenticator,
            options: newOptions
        )
    }

    /// Returns a new server with the given REST path prefix.
    public func restPrefix(_ prefix: String) -> A2AServer {
        var newOptions = options
        newOptions.restPrefix = prefix
        return A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: authenticator,
            options: newOptions
        )
    }

    /// Returns a new server with a different authenticator.
    public func authenticator(_ auth: any Authenticator) -> A2AServer {
        A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: auth,
            options: options
        )
    }

    /// Returns a new server with a different task store.
    public func taskStore(_ store: any TaskStore) -> A2AServer {
        A2AServer(
            handler: handler,
            taskStore: store,
            webhookStore: webhookStore,
            authenticator: authenticator,
            options: options
        )
    }

    /// Returns a new server with a different webhook store.
    public func webhookStore(_ store: any WebhookStore) -> A2AServer {
        A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: store,
            authenticator: authenticator,
            options: options
        )
    }

    /// Toggles whether incoming requests MUST carry credentials (vs
    /// advisory auth where the context is passed through if present).
    public func requireAuthentication(_ required: Bool) -> A2AServer {
        var newOptions = options
        newOptions.requireAuth = required
        return A2AServer(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: authenticator,
            options: newOptions
        )
    }

    /// Build the Hummingbird Application without running it. Primarily
    /// useful for tests that want to drive an in-process server.
    public func makeApplication() -> some ApplicationProtocol {
        let dispatcher = A2ADispatcher(
            handler: handler,
            taskStore: taskStore,
            webhookStore: webhookStore,
            authenticator: authenticator,
            requireAuth: options.requireAuth
        )
        let router = Router()
        dispatcher.registerRoutes(
            on: router,
            rpcPath: options.rpcPath,
            restPrefix: options.restPrefix
        )
        return Application(
            router: router,
            configuration: .init(
                address: .hostname(options.host, port: options.port),
                serverName: "a2a-swift"
            )
        )
    }

    /// Runs the server. Blocks the calling task until the process receives
    /// a termination signal or the application exits cleanly.
    public func run() async throws {
        let app = makeApplication()
        try await app.runService()
    }
}
