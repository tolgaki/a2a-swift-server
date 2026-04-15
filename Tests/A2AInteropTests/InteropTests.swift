// InteropTests.swift
// A2AInteropTests
//
// Boots an in-process A2AServer and runs the A2AClient against it over
// both REST and JSON-RPC. Covers all 11 core operations.

import XCTest
import Foundation
import A2ACore
import A2AClient
import A2AServer

final class InteropTests: XCTestCase {
    var harness: ServerHarness!
    var baseURL: URL!

    override func setUp() async throws {
        harness = ServerHarness()
        baseURL = try await harness.start(handler: EchoHandler())
    }

    override func tearDown() async throws {
        await harness.stop()
    }

    private func restClient() -> A2AClient {
        A2AClient(configuration: A2AClientConfiguration(
            baseURL: baseURL,
            transportBinding: .httpREST,
            protocolVersion: "1.0"
        ))
    }

    private func rpcClient() -> A2AClient {
        A2AClient(configuration: A2AClientConfiguration(
            baseURL: baseURL,
            transportBinding: .jsonRPC,
            protocolVersion: "1.0"
        ))
    }

    // MARK: - Agent card discovery

    func testAgentCard_Discovery() async throws {
        let url = baseURL.appendingPathComponent(".well-known/agent-card.json")
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(AgentCard.self, from: data)
        XCTAssertEqual(card.name, "Echo")
        XCTAssertEqual(card.supportedInterfaces.count, 2)
    }

    // MARK: - SendMessage

    func testSendMessage_REST() async throws {
        let client = restClient()
        let response = try await client.sendMessage("hello")
        XCTAssertTrue(response.isMessage)
        XCTAssertEqual(response.message?.textContent, "echo: hello")
    }

    func testSendMessage_JSONRPC() async throws {
        let client = rpcClient()
        let response = try await client.sendMessage("hello")
        XCTAssertTrue(response.isMessage)
        XCTAssertEqual(response.message?.textContent, "echo: hello")
    }

    func testSendMessage_ReturnsTask_REST() async throws {
        let client = restClient()
        let response = try await client.sendMessage("please open a task")
        XCTAssertTrue(response.isTask)
        XCTAssertEqual(response.task?.status.state, .submitted)
    }

    func testSendMessage_ReturnsTask_JSONRPC() async throws {
        let client = rpcClient()
        let response = try await client.sendMessage("please open a task")
        XCTAssertTrue(response.isTask)
        XCTAssertEqual(response.task?.status.state, .submitted)
    }

    // MARK: - GetTask

    func testGetTask_REST() async throws {
        let client = restClient()
        let create = try await client.sendMessage("open a task")
        let created = try XCTUnwrap(create.task)
        let fetched = try await client.getTask(created.id)
        XCTAssertEqual(fetched.id, created.id)
    }

    func testGetTask_JSONRPC() async throws {
        let client = rpcClient()
        let create = try await client.sendMessage("open a task")
        let created = try XCTUnwrap(create.task)
        let fetched = try await client.getTask(created.id)
        XCTAssertEqual(fetched.id, created.id)
    }

    // MARK: - ListTasks

    func testListTasks_REST() async throws {
        let client = restClient()
        _ = try await client.sendMessage("open a task")
        _ = try await client.sendMessage("open another task")
        let listing = try await client.listTasks(TaskQueryParams())
        XCTAssertGreaterThanOrEqual(listing.tasks.count, 2)
    }

    func testListTasks_JSONRPC() async throws {
        let client = rpcClient()
        _ = try await client.sendMessage("open a task")
        _ = try await client.sendMessage("open another task")
        let listing = try await client.listTasks(TaskQueryParams())
        XCTAssertGreaterThanOrEqual(listing.tasks.count, 2)
    }

    // MARK: - CancelTask

    func testCancelTask_REST() async throws {
        let client = restClient()
        let create = try await client.sendMessage("open a task")
        let created = try XCTUnwrap(create.task)
        let cancelled = try await client.cancelTask(created.id)
        XCTAssertEqual(cancelled.status.state, .cancelled)
    }

    func testCancelTask_JSONRPC() async throws {
        let client = rpcClient()
        let create = try await client.sendMessage("open a task")
        let created = try XCTUnwrap(create.task)
        let cancelled = try await client.cancelTask(created.id)
        XCTAssertEqual(cancelled.status.state, .cancelled)
    }

    // MARK: - Streaming

    func testSendStreamingMessage_REST() async throws {
        let client = restClient()
        let stream = try await client.sendStreamingMessage("stream me")
        var eventCount = 0
        var sawTerminal = false
        for try await event in stream {
            eventCount += 1
            if case .taskStatusUpdate(let update) = event, update.status.state == .completed {
                sawTerminal = true
            }
        }
        XCTAssertGreaterThanOrEqual(eventCount, 3)
        XCTAssertTrue(sawTerminal)
    }

    func testSendStreamingMessage_JSONRPC() async throws {
        let client = rpcClient()
        let stream = try await client.sendStreamingMessage("stream me")
        var eventCount = 0
        var sawTerminal = false
        for try await event in stream {
            eventCount += 1
            if case .taskStatusUpdate(let update) = event, update.status.state == .completed {
                sawTerminal = true
            }
        }
        XCTAssertGreaterThanOrEqual(eventCount, 3)
        XCTAssertTrue(sawTerminal)
    }

    // MARK: - Push notification CRUD

    func testPushNotificationConfig_CRUD_REST() async throws {
        let client = restClient()
        let create = try await client.sendMessage("open a task")
        let task = try XCTUnwrap(create.task)

        let config = PushNotificationConfig(
            url: "https://webhook.example.com/notify",
            token: "test-token"
        )
        let created = try await client.createPushNotificationConfig(taskId: task.id, config: config)
        XCTAssertFalse(created.id.isEmpty)

        let fetched = try await client.getPushNotificationConfig(taskId: task.id, configId: created.id)
        XCTAssertEqual(fetched.pushNotificationConfig.url, "https://webhook.example.com/notify")

        let listed = try await client.listPushNotificationConfigs(taskId: task.id)
        XCTAssertEqual(listed.count, 1)

        try await client.deletePushNotificationConfig(taskId: task.id, configId: created.id)
        let afterDelete = try await client.listPushNotificationConfigs(taskId: task.id)
        XCTAssertEqual(afterDelete.count, 0)
    }

    func testPushNotificationConfig_CRUD_JSONRPC() async throws {
        let client = rpcClient()
        let create = try await client.sendMessage("open a task")
        let task = try XCTUnwrap(create.task)

        let config = PushNotificationConfig(
            url: "https://webhook.example.com/notify",
            token: "test-token"
        )
        let created = try await client.createPushNotificationConfig(taskId: task.id, config: config)
        XCTAssertFalse(created.id.isEmpty)

        let fetched = try await client.getPushNotificationConfig(taskId: task.id, configId: created.id)
        XCTAssertEqual(fetched.pushNotificationConfig.url, "https://webhook.example.com/notify")

        let listed = try await client.listPushNotificationConfigs(taskId: task.id)
        XCTAssertEqual(listed.count, 1)

        try await client.deletePushNotificationConfig(taskId: task.id, configId: created.id)
        let afterDelete = try await client.listPushNotificationConfigs(taskId: task.id)
        XCTAssertEqual(afterDelete.count, 0)
    }

    // MARK: - Error paths

    func testGetTask_NotFound_REST() async throws {
        let client = restClient()
        do {
            _ = try await client.getTask("nonexistent-task")
            XCTFail("Expected taskNotFound error")
        } catch A2AError.taskNotFound {
            // expected
        }
    }

    func testGetTask_NotFound_JSONRPC() async throws {
        let client = rpcClient()
        do {
            _ = try await client.getTask("nonexistent-task")
            XCTFail("Expected taskNotFound error")
        } catch A2AError.taskNotFound {
            // expected
        }
    }
}
