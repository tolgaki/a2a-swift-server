// ServerHarness.swift
// A2AInteropTests
//
// In-process server harness. Boots an A2AServer on an ephemeral port
// inside a background task, gives tests a live base URL, and tears
// down cleanly.

import Foundation
import Hummingbird
import A2ACore
import A2AServer

actor ServerHarness {
    private var task: _Concurrency.Task<Void, Error>?
    private(set) var baseURL: URL?

    /// Boots the server on an ephemeral port, waits for it to be ready,
    /// and returns the live base URL.
    func start(handler: any A2AHandler) async throws -> URL {
        // Use port 0 so the OS picks an ephemeral port. Hummingbird will
        // expose the actual bound port via the application's `onServerRunning`
        // callback.
        let dispatcher = A2ADispatcher(
            handler: handler,
            taskStore: InMemoryTaskStore(),
            webhookStore: InMemoryWebhookStore(),
            authenticator: NoOpBearerAuthenticator(),
            requireAuth: false
        )
        let router = Router()
        dispatcher.registerRoutes(on: router, rpcPath: "/", restPrefix: "")

        let portBox = PortBox()
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: 0),
                serverName: "a2a-swift-test"
            ),
            onServerRunning: { channel in
                if let local = channel.localAddress, let port = local.port {
                    await portBox.setPort(port)
                }
            }
        )

        self.task = _Concurrency.Task {
            try await app.runService()
        }

        // Spin until we get a port (max 5 seconds).
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let port = await portBox.port {
                let url = URL(string: "http://127.0.0.1:\(port)")!
                self.baseURL = url
                return url
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        throw HarnessError.timeout
    }

    func stop() async {
        task?.cancel()
        task = nil
        baseURL = nil
    }

    enum HarnessError: Error {
        case timeout
    }
}

/// Box for the ephemeral port so the `onServerRunning` callback can publish
/// the bound address back to the harness.
private actor PortBox {
    private(set) var port: Int?
    func setPort(_ p: Int) { port = p }
}
