// JSONRPCDispatcher.swift
// A2AServer
//
// Single-entry JSON-RPC 2.0 dispatcher. All A2A operations are multiplexed
// through one POST route (default `/`).

import Foundation
import Hummingbird
import NIOCore
import A2ACore

extension A2ADispatcher {
    func jsonrpcDispatch<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        let buffer = try await req.body.collect(upTo: 10 * 1024 * 1024)
        let data = Data(buffer: buffer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Pre-decode to get the method name.
        let methodOnly: JSONRPCMethodOnly
        do {
            methodOnly = try decoder.decode(JSONRPCMethodOnly.self, from: data)
        } catch {
            return try jsonrpcError(
                id: nil,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.parseError.rawValue,
                    message: "Parse error",
                    data: nil
                )
            )
        }

        let rpcID = methodOnly.id

        do {
            let auth = try await resolveAuth(headers: headers)

            switch methodOnly.method {
            case "SendMessage":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<SendMessageRequest>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let result = try await handleSendMessage(params, auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: result)

            case "SendStreamingMessage":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<SendMessageRequest>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let stream = handleStreamingMessage(params, auth: auth)
                return sseResponse(stream: stream, wrappedInJSONRPC: true, rpcID: rpcID)

            case "GetTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<GetTaskParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let task = try await getTask(id: params.id, historyLength: params.historyLength, auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: task)

            case "ListTasks":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskQueryParams>.self, from: data
                )
                let params = envelope.params ?? TaskQueryParams()
                let response = try await listTasks(params, auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: response)

            case "CancelTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<CancelTaskRequest>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let task = try await cancelTask(id: params.id, metadata: params.metadata, auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: task)

            case "SubscribeToTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskIdParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let stream = try await subscribeToTask(id: params.id, auth: auth)
                return sseResponse(stream: stream, wrappedInJSONRPC: true, rpcID: rpcID)

            case "CreateTaskPushNotificationConfig":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<CreatePushConfigParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let result = try await createPushNotificationConfig(
                    taskID: params.taskId,
                    config: params.config,
                    auth: auth
                )
                return try jsonrpcSuccess(id: rpcID, result: result)

            case "GetTaskPushNotificationConfig":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<PushConfigIDParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let result = try await getPushNotificationConfig(
                    taskID: params.taskId,
                    configID: params.id,
                    auth: auth
                )
                return try jsonrpcSuccess(id: rpcID, result: result)

            case "ListTaskPushNotificationConfigs":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskIDOnlyParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let result = try await listPushNotificationConfigs(taskID: params.taskId, auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: result)

            case "DeleteTaskPushNotificationConfig":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<PushConfigIDParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                try await deletePushNotificationConfig(
                    taskID: params.taskId,
                    configID: params.id,
                    auth: auth
                )
                return try jsonrpcSuccess(id: rpcID, result: EmptyResult())

            case "GetExtendedAgentCard":
                let card = try await extendedAgentCard(baseURL: baseURL(from: req), auth: auth)
                return try jsonrpcSuccess(id: rpcID, result: card)

            default:
                return try jsonrpcError(
                    id: rpcID,
                    error: JSONRPCErrorBody(
                        code: JSONRPCErrorCode.methodNotFound.rawValue,
                        message: "Method not found: \(methodOnly.method)",
                        data: nil
                    )
                )
            }
        } catch let error as A2AError {
            return try jsonrpcError(id: rpcID, error: error.toJSONRPCError())
        } catch {
            return try jsonrpcError(
                id: rpcID,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.internalError.rawValue,
                    message: error.localizedDescription,
                    data: nil
                )
            )
        }
    }

    private func requireParams<T>(_ params: T?) throws -> T {
        guard let params = params else {
            throw A2AError.invalidRequest(message: "Missing required params")
        }
        return params
    }

    private func jsonrpcSuccess<T: Encodable>(
        id: JSONRPCIdentifier?,
        result: T
    ) throws -> Response {
        let body = JSONRPCSuccessResponse(id: id, result: result)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(body)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    private func jsonrpcError(
        id: JSONRPCIdentifier?,
        error: JSONRPCErrorBody
    ) throws -> Response {
        let body = JSONRPCErrorResponse(id: id, error: error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(body)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,  // JSON-RPC errors always return HTTP 200
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

// MARK: - Param types not shared with the client

struct GetTaskParams: Decodable {
    let tenant: String?
    let id: String
    let historyLength: Int?
}

struct CreatePushConfigParams: Decodable {
    let tenant: String?
    let taskId: String
    let config: PushNotificationConfig
}

struct PushConfigIDParams: Decodable {
    let tenant: String?
    let taskId: String
    let id: String
}

struct TaskIDOnlyParams: Decodable {
    let tenant: String?
    let taskId: String
}
