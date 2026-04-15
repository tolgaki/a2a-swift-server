// WebhookStore.swift
// A2AServer

import Foundation
import A2ACore

/// Persistence abstraction for push-notification webhook configurations.
///
/// Each task may have multiple webhooks (e.g. one for the user's
/// notification service and another for an internal observability bridge).
public protocol WebhookStore: Sendable {
    /// Register a new webhook config for a task. Returns the generated
    /// config id.
    func create(taskID: String, _ config: PushNotificationConfig) async -> String

    /// Fetch a specific config by task id + config id.
    func get(taskID: String, configID: String) async -> PushNotificationConfig?

    /// List all configs registered for a task.
    func list(taskID: String) async -> [PushNotificationConfig]

    /// Delete a specific config.
    func delete(taskID: String, configID: String) async

    /// Alias of `list(taskID:)` used by the webhook dispatcher to resolve
    /// delivery targets for a task event.
    func configs(forTask taskID: String) async -> [PushNotificationConfig]
}
