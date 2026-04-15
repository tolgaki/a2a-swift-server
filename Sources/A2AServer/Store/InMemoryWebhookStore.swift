// InMemoryWebhookStore.swift
// A2AServer

import Foundation
import A2ACore

/// In-memory, actor-isolated `WebhookStore`.
public actor InMemoryWebhookStore: WebhookStore {
    private var configsByTask: [String: [String: PushNotificationConfig]] = [:]

    public init() {}

    public func create(taskID: String, _ config: PushNotificationConfig) async -> String {
        let configID = config.id ?? UUID().uuidString
        let stored = PushNotificationConfig(
            id: configID,
            url: config.url,
            token: config.token,
            authentication: config.authentication
        )
        configsByTask[taskID, default: [:]][configID] = stored
        return configID
    }

    public func get(taskID: String, configID: String) async -> PushNotificationConfig? {
        configsByTask[taskID]?[configID]
    }

    public func list(taskID: String) async -> [PushNotificationConfig] {
        guard let map = configsByTask[taskID] else { return [] }
        return Array(map.values)
    }

    public func delete(taskID: String, configID: String) async {
        configsByTask[taskID]?.removeValue(forKey: configID)
    }

    public func configs(forTask taskID: String) async -> [PushNotificationConfig] {
        await list(taskID: taskID)
    }
}
