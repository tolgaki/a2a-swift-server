// TaskStore.swift
// A2AServer

import Foundation
import A2ACore

/// Persistence abstraction for A2A tasks. The server uses this to fulfil
/// `getTask`, `listTasks`, `cancelTask`, and `subscribeToTask` without
/// going through the user's `A2AHandler`.
///
/// The default implementation (`InMemoryTaskStore`) is an `actor` backed
/// by a dictionary. Plug in your own for persistence backends (Postgres,
/// Redis, etc.).
public protocol TaskStore: Sendable {
    /// Insert a new task, overwriting any existing task with the same id.
    func insert(_ task: A2ATask) async

    /// Fetch a task by id.
    func get(id: String) async -> A2ATask?

    /// Apply an in-place mutation to an existing task and return the updated
    /// value. Returns nil if the task does not exist.
    func update(
        id: String,
        _ mutate: @Sendable (inout A2ATask) -> Void
    ) async -> A2ATask?

    /// List tasks matching the given query parameters.
    func list(_ query: TaskQueryParams) async -> TaskListResponse

    /// Delete a task by id.
    func delete(id: String) async
}
