// A2ADispatcher.swift
// A2AServer
//
// Transport-agnostic dispatch layer that both the REST and JSON-RPC routers
// call into. Owns the handler, stores, auth, and task registry.

import Foundation
import A2ACore

/// Transport-agnostic dispatcher: turns parsed A2A request parameters
/// into handler or store invocations. Both the REST dispatcher and the
/// JSON-RPC dispatcher sit on top of this.
public final class A2ADispatcher: @unchecked Sendable {
    public let handler: any A2AHandler
    public let taskStore: any TaskStore
    public let webhookStore: any WebhookStore
    public let authenticator: any Authenticator
    public let registry: TaskRegistry
    public let webhookDispatcher: WebhookDispatcher
    public let requireAuth: Bool

    public init(
        handler: any A2AHandler,
        taskStore: any TaskStore,
        webhookStore: any WebhookStore,
        authenticator: any Authenticator,
        registry: TaskRegistry = TaskRegistry(),
        requireAuth: Bool = false
    ) {
        self.handler = handler
        self.taskStore = taskStore
        self.webhookStore = webhookStore
        self.authenticator = authenticator
        self.registry = registry
        self.webhookDispatcher = WebhookDispatcher(store: webhookStore)
        self.requireAuth = requireAuth
    }

    // MARK: - Authentication

    /// Extracts the auth context from headers and enforces the agent card's
    /// `securityRequirements`. Throws `authenticationRequired` if the card
    /// requires auth and none was supplied.
    public func resolveAuth(headers: [String: String]) async throws -> AuthContext? {
        let auth = try await authenticator.authenticate(headers: headers)
        if requireAuth && auth == nil {
            throw A2AError.authenticationRequired(message: "Authentication required")
        }
        return auth
    }

    // MARK: - Message operations

    public func handleSendMessage(
        _ request: SendMessageRequest,
        auth: AuthContext?
    ) async throws -> SendMessageResponse {
        let response = try await handler.handleMessage(request.message, auth: auth)

        // If the handler returned a task, insert it into the store so
        // subsequent getTask/listTasks/cancelTask operations can find it.
        if case .task(let task) = response {
            await taskStore.insert(task)
            scheduleAutoCompleteIfConfigured(task: task)
        }
        return response
    }

    public func handleStreamingMessage(
        _ request: SendMessageRequest,
        auth: AuthContext?
    ) -> AsyncThrowingStream<StreamResponse, Error> {
        let stream = handler.handleStreamingMessage(request.message, auth: auth)
        return AsyncThrowingStream<StreamResponse, Error> { continuation in
            let dispatcher = self
            let dispatchTask = Task {
                do {
                    for try await event in stream {
                        // Persist task snapshots so getTask works during and
                        // after the stream.
                        if case .task(let task) = event {
                            await dispatcher.taskStore.insert(task)
                        }
                        // Fan out to registered webhooks.
                        if let taskID = event.associatedTaskID {
                            await dispatcher.webhookDispatcher.dispatch(taskID: taskID, event: event)
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in dispatchTask.cancel() }
        }
    }

    // MARK: - Task operations

    public func getTask(
        id: String,
        historyLength: Int?,
        auth: AuthContext?
    ) async throws -> A2ATask {
        guard let task = await taskStore.get(id: id) else {
            throw A2AError.taskNotFound(taskId: id, message: nil)
        }
        if let historyLength = historyLength {
            let trimmed = historyLength == 0 ? nil
                : task.history.map { Array($0.suffix(historyLength)) }
            return A2ATask(
                id: task.id,
                contextId: task.contextId,
                status: task.status,
                artifacts: task.artifacts,
                history: trimmed,
                metadata: task.metadata
            )
        }
        return task
    }

    public func listTasks(
        _ query: TaskQueryParams,
        auth: AuthContext?
    ) async throws -> TaskListResponse {
        await taskStore.list(query)
    }

    public func cancelTask(
        id: String,
        metadata: [String: AnyCodable]?,
        auth: AuthContext?
    ) async throws -> A2ATask {
        guard let existing = await taskStore.get(id: id) else {
            throw A2AError.taskNotFound(taskId: id, message: nil)
        }
        if existing.status.state.isTerminal {
            throw A2AError.taskNotCancelable(
                taskId: id,
                state: existing.status.state,
                message: "Task \(id) is already in terminal state \(existing.status.state.rawValue)"
            )
        }

        await registry.cancel(taskID: id)
        try await handler.onTaskCancelled(id: id, auth: auth)

        let updated = await taskStore.update(id: id) { task in
            task = A2ATask(
                id: task.id,
                contextId: task.contextId,
                status: TaskStatus(
                    state: .cancelled,
                    message: task.status.message,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                ),
                artifacts: task.artifacts,
                history: task.history,
                metadata: task.metadata
            )
        }
        guard let updated = updated else {
            throw A2AError.taskNotFound(taskId: id, message: nil)
        }
        return updated
    }

    public func subscribeToTask(
        id: String,
        auth: AuthContext?
    ) async throws -> AsyncThrowingStream<StreamResponse, Error> {
        guard let task = await taskStore.get(id: id) else {
            throw A2AError.taskNotFound(taskId: id, message: nil)
        }
        // Minimal implementation: emit the current snapshot as the first
        // event. A full implementation would hook into a live event bus.
        return AsyncThrowingStream { continuation in
            continuation.yield(.task(task))
            continuation.finish()
        }
    }

    // MARK: - Push notification CRUD

    public func createPushNotificationConfig(
        taskID: String,
        config: PushNotificationConfig,
        auth: AuthContext?
    ) async throws -> TaskPushNotificationConfig {
        guard await taskStore.get(id: taskID) != nil else {
            throw A2AError.taskNotFound(taskId: taskID, message: nil)
        }
        let configID = await webhookStore.create(taskID: taskID, config)
        return TaskPushNotificationConfig(
            id: configID,
            taskId: taskID,
            pushNotificationConfig: PushNotificationConfig(
                id: configID,
                url: config.url,
                token: config.token,
                authentication: config.authentication
            )
        )
    }

    public func getPushNotificationConfig(
        taskID: String,
        configID: String,
        auth: AuthContext?
    ) async throws -> TaskPushNotificationConfig {
        guard let config = await webhookStore.get(taskID: taskID, configID: configID) else {
            throw A2AError.taskNotFound(taskId: configID, message: "Push notification config not found")
        }
        return TaskPushNotificationConfig(
            id: configID,
            taskId: taskID,
            pushNotificationConfig: config
        )
    }

    public func listPushNotificationConfigs(
        taskID: String,
        auth: AuthContext?
    ) async throws -> ListPushNotificationConfigsResponse {
        let configs = await webhookStore.list(taskID: taskID)
        let wrapped = configs.map { config in
            TaskPushNotificationConfig(
                id: config.id ?? "",
                taskId: taskID,
                pushNotificationConfig: config
            )
        }
        return ListPushNotificationConfigsResponse(configs: wrapped, nextPageToken: nil)
    }

    public func deletePushNotificationConfig(
        taskID: String,
        configID: String,
        auth: AuthContext?
    ) async throws {
        guard await webhookStore.get(taskID: taskID, configID: configID) != nil else {
            throw A2AError.taskNotFound(taskId: configID, message: "Push notification config not found")
        }
        await webhookStore.delete(taskID: taskID, configID: configID)
    }

    // MARK: - Agent card

    public func agentCard(baseURL: String) -> AgentCard {
        handler.agentCard(baseURL: baseURL)
    }

    public func extendedAgentCard(
        baseURL: String,
        auth: AuthContext?
    ) async throws -> AgentCard {
        guard let auth = auth else {
            throw A2AError.authenticationRequired(message: "Extended agent card requires authentication")
        }
        guard let card = try await handler.extendedAgentCard(baseURL: baseURL, auth: auth) else {
            throw A2AError.extendedAgentCardNotConfigured(message: nil)
        }
        return card
    }

    // MARK: - Helpers

    private func scheduleAutoCompleteIfConfigured(task: A2ATask) {
        guard let delay = handler.autoCompleteDelay else { return }
        let taskID = task.id
        let store = taskStore
        let registry = self.registry
        let dispatcher = webhookDispatcher
        let bg = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let updated = await store.update(id: taskID) { task in
                task = A2ATask(
                    id: task.id,
                    contextId: task.contextId,
                    status: TaskStatus(
                        state: .completed,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    ),
                    artifacts: task.artifacts,
                    history: task.history,
                    metadata: task.metadata
                )
            }
            if let updated = updated {
                await dispatcher.dispatch(taskID: taskID, event: .task(updated))
            }
            await registry.remove(taskID: taskID)
        }
        Task {
            await registry.register(taskID: taskID, task: bg)
        }
    }
}

// MARK: - StreamResponse task-id helper

extension StreamResponse {
    var associatedTaskID: String? {
        switch self {
        case .task(let task): return task.id
        case .message(let m): return m.taskId
        case .statusUpdate(let u): return u.taskId
        case .artifactUpdate(let u): return u.taskId
        }
    }
}
