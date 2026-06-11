// JSONRPCDispatcher.swift
// A2AServer
//
// Single-entry JSON-RPC 2.0 dispatcher. All A2A operations are multiplexed
// through one POST route (default `/`).

import Foundation
import Hummingbird
import NIOCore
import A2AClient

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
            // Per JSON-RPC 2.0, ParseError (-32700) is reserved for JSON the
            // server cannot parse at all. JSON that parses but is not a
            // valid Request object (missing method/jsonrpc) is
            // InvalidRequest (-32600), echoing the id when one is present.
            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                let id = (try? decoder.decode(JSONRPCIDOnly.self, from: data))?.id
                return try jsonrpcError(
                    id: id,
                    error: JSONRPCErrorBody(
                        code: JSONRPCErrorCode.invalidRequest.rawValue,
                        message: "Invalid request: not a valid JSON-RPC 2.0 request object",
                        data: nil
                    )
                )
            }
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
        } catch let error as DecodingError {
            // Params that fail to decode are an InvalidParams (-32602)
            // condition per JSON-RPC 2.0, not an internal server error.
            return try jsonrpcError(
                id: rpcID,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.invalidParams.rawValue,
                    message: "Invalid params: \(Self.describe(error))",
                    data: nil
                )
            )
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
            throw A2AError.jsonRPCError(
                code: JSONRPCErrorCode.invalidParams.rawValue,
                message: "Missing required params",
                data: nil
            )
        }
        return params
    }

    /// Compact, single-line summary of a decoding failure for error messages.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "params" : joined
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing field '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context):
            return "type mismatch at \(path(context))"
        case .valueNotFound(_, let context):
            return "null value at \(path(context))"
        case .dataCorrupted(let context):
            return "malformed value at \(path(context))"
        @unknown default:
            return "undecodable params"
        }
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
