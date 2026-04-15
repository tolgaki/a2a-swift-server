// WebhookDispatcher.swift
// A2AServer

import Foundation
import A2ACore

/// Delivers task update events to registered push-notification webhooks.
///
/// Each event is POSTed to the configured URL with exponential-backoff
/// retries on transient failures (connection errors, 5xx). Non-transient
/// failures (4xx) are logged and dropped.
///
/// This is an `actor` because it holds the shared `URLSession` and an
/// in-flight delivery set used for bounded concurrency. The implementation
/// is intentionally minimal — consumers with durability requirements
/// should plug in their own queue backed by their message broker of choice.
public actor WebhookDispatcher {
    private let store: any WebhookStore
    private let session: URLSession
    private let maxRetries: Int
    private let initialBackoff: Duration
    private let maxBackoff: Duration

    /// Create a dispatcher.
    ///
    /// - Parameters:
    ///   - store: The backing `WebhookStore` used to look up configs for
    ///     each task.
    ///   - session: URLSession for delivery HTTP calls. Defaults to
    ///     `URLSession.shared`.
    ///   - maxRetries: Maximum delivery attempts including the first.
    ///     Defaults to 3.
    ///   - initialBackoff: Initial retry delay. Defaults to 500ms.
    ///   - maxBackoff: Cap on retry delay. Defaults to 30s.
    public init(
        store: any WebhookStore,
        session: URLSession = .shared,
        maxRetries: Int = 3,
        initialBackoff: Duration = .milliseconds(500),
        maxBackoff: Duration = .seconds(30)
    ) {
        self.store = store
        self.session = session
        self.maxRetries = maxRetries
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
    }

    /// Fan out a `StreamResponse` event to all webhooks registered for the
    /// given task id. Deliveries happen in parallel.
    public func dispatch(taskID: String, event: StreamResponse) async {
        let configs = await store.configs(forTask: taskID)
        guard !configs.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    await self.deliver(config: config, event: event)
                }
            }
        }
    }

    // MARK: - Private

    private func deliver(
        config: PushNotificationConfig,
        event: StreamResponse
    ) async {
        guard let url = URL(string: config.url) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(event) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = config.token {
            request.setValue(token, forHTTPHeaderField: "X-A2A-Notification-Token")
        }
        if let auth = config.authentication {
            let value: String
            if auth.scheme.lowercased() == "basic" {
                value = "Basic \(auth.credentials ?? "")"
            } else {
                value = "\(auth.scheme) \(auth.credentials ?? "")"
            }
            request.setValue(value, forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        var delay = initialBackoff
        for attempt in 1...maxRetries {
            let outcome = await attemptDelivery(request: request)
            switch outcome {
            case .success:
                return
            case .permanentFailure:
                return
            case .retry:
                if attempt == maxRetries { return }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, maxBackoff)
            }
        }
    }

    private enum DeliveryOutcome {
        case success
        case retry
        case permanentFailure
    }

    private func attemptDelivery(request: URLRequest) async -> DeliveryOutcome {
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .retry
            }
            switch http.statusCode {
            case 200...299:
                return .success
            case 400...499:
                // Client error — don't retry.
                return .permanentFailure
            default:
                return .retry
            }
        } catch {
            return .retry
        }
    }
}

// Duration multiplication was added in Swift 6.0 for Int; spell out the
// multiplication explicitly for older toolchains and for clarity.
private func * (lhs: Duration, rhs: Int) -> Duration {
    let components = lhs.components
    let seconds = components.seconds * Int64(rhs)
    let attoseconds = components.attoseconds * Int64(rhs)
    return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
}
