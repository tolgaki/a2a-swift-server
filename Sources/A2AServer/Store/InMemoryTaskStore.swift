// InMemoryTaskStore.swift
// A2AServer

import Foundation
import A2ACore

/// In-memory, actor-isolated `TaskStore`. Suitable for examples, tests,
/// and single-process deployments. Not persistent across restarts.
public actor InMemoryTaskStore: TaskStore {
    private var tasks: [String: A2ATask] = [:]

    public init() {}

    public func insert(_ task: A2ATask) async {
        tasks[task.id] = task
    }

    public func get(id: String) async -> A2ATask? {
        tasks[id]
    }

    public func update(
        id: String,
        _ mutate: @Sendable (inout A2ATask) -> Void
    ) async -> A2ATask? {
        guard var task = tasks[id] else { return nil }
        mutate(&task)
        tasks[id] = task
        return task
    }

    public func list(_ query: TaskQueryParams) async -> TaskListResponse {
        var filtered = Array(tasks.values)

        if let contextId = query.contextId {
            filtered = filtered.filter { $0.contextId == contextId }
        }
        if let status = query.status {
            filtered = filtered.filter { $0.status.state == status }
        }
        if let after = query.statusTimestampAfter,
           let fmt = ISO8601DateFormatter() as ISO8601DateFormatter? {
            let _ = fmt
            filtered = filtered.filter { task in
                guard let ts = task.status.timestamp,
                      let taskDate = ISO8601DateFormatter().date(from: ts) else { return false }
                return taskDate > after
            }
        }

        // Deterministic ordering for reproducible tests.
        filtered.sort { $0.id < $1.id }

        let pageSize = query.pageSize ?? 50
        let totalSize = filtered.count

        // Minimal cursor: pageToken is the offset as a string.
        let offset = Int(query.pageToken ?? "0") ?? 0
        let end = min(offset + pageSize, filtered.count)
        let page = offset < filtered.count ? Array(filtered[offset..<end]) : []
        let nextToken = end < filtered.count ? String(end) : ""

        // Drop history/artifacts if the caller didn't ask for them.
        let trimmedTasks: [A2ATask] = page.map { task in
            let historyLength = query.historyLength
            let includeArtifacts = query.includeArtifacts ?? true
            var history = task.history
            if let len = historyLength {
                if len == 0 {
                    history = nil
                } else if let h = history, h.count > len {
                    history = Array(h.suffix(len))
                }
            }
            return A2ATask(
                id: task.id,
                contextId: task.contextId,
                status: task.status,
                artifacts: includeArtifacts ? task.artifacts : nil,
                history: history,
                metadata: task.metadata
            )
        }

        return TaskListResponse(
            tasks: trimmedTasks,
            nextPageToken: nextToken,
            pageSize: pageSize,
            totalSize: totalSize
        )
    }

    public func delete(id: String) async {
        tasks.removeValue(forKey: id)
    }
}
