// TaskRegistry.swift
// A2AServer

import Foundation

/// Tracks in-flight Swift `Task` handles keyed by A2A task id so that
/// `cancelTask` on the server can actually interrupt the background work.
///
/// Handlers that return a non-terminal `A2ATask` should register their
/// background work here via `A2AServer.registerBackground(taskID:work:)`
/// (or equivalent helper). The server calls `cancel(taskID:)` when a
/// client requests cancellation.
public actor TaskRegistry {
    /// Type-erased cancellation handle for a Swift task of any return type.
    public struct Cancellable: Sendable {
        let cancel: @Sendable () -> Void
    }

    private var handles: [String: Cancellable] = [:]

    public init() {}

    /// Register a background task under a given A2A task id.
    public func register<T: Sendable>(taskID: String, task: Task<T, Never>) {
        handles[taskID] = Cancellable(cancel: { task.cancel() })
    }

    public func register<T: Sendable>(taskID: String, task: Task<T, any Error>) {
        handles[taskID] = Cancellable(cancel: { task.cancel() })
    }

    /// Cancel the background task registered under the given id. A no-op
    /// if no such task exists.
    public func cancel(taskID: String) {
        handles[taskID]?.cancel()
        handles.removeValue(forKey: taskID)
    }

    /// Remove a registered task without cancelling (used when a task
    /// completes normally).
    public func remove(taskID: String) {
        handles.removeValue(forKey: taskID)
    }

    /// Cancel every in-flight task. Called during graceful shutdown.
    public func cancelAll() {
        for (_, handle) in handles {
            handle.cancel()
        }
        handles.removeAll()
    }
}
