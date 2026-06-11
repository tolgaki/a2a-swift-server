// JSONRPCCore.swift
// A2AServer
//
// Transport-agnostic JSON-RPC 2.0 dispatch: a raw request body in, a
// `JSONRPCOutcome` out. HTTP frameworks (Hummingbird, Vapor, custom
// runtimes) only need a thin adapter that maps the outcome onto their
// response type — the protocol logic lives here, framework-free.

import Foundation
import A2AClient

/// Result of dispatching one JSON-RPC request body.
public enum JSONRPCOutcome: Sendable {
    /// A complete JSON response body (success or JSON-RPC error).
    /// Serve with HTTP 200 and Content-Type `application/json`.
    case json(Data)

    /// Authentication or authorization failure. The A2A spec treats auth
    /// as transport-level: serve with HTTP 401 (`authenticationRequired`)
    /// or 403 (`authorizationFailed`) rather than a JSON-RPC error code.
    case unauthenticated(A2AError)

    /// A streaming method. Frame each event as an SSE `data:` line wrapped
    /// in a JSON-RPC envelope (see `ServerSentEventsEncoder`) and serve
    /// with Content-Type `text/event-stream`.
    case stream(AsyncThrowingStream<StreamResponse, Error>, rpcID: JSONRPCIdentifier?)
}

extension A2ADispatcher {
    /// Dispatches a single JSON-RPC 2.0 request.
    ///
    /// - Parameters:
    ///   - data: The raw request body.
    ///   - headers: The HTTP request headers (lowercase canonical names),
    ///     used for authentication and `Host`-based agent-card URLs.
    /// - Returns: The outcome to serialize onto the transport.
    public func dispatchJSONRPC(body data: Data, headers: [String: String]) async -> JSONRPCOutcome {
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
                return .json(Self.jsonrpcErrorData(
                    id: id,
                    error: JSONRPCErrorBody(
                        code: JSONRPCErrorCode.invalidRequest.rawValue,
                        message: "Invalid request: not a valid JSON-RPC 2.0 request object",
                        data: nil
                    )
                ))
            }
            return .json(Self.jsonrpcErrorData(
                id: nil,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.parseError.rawValue,
                    message: "Parse error",
                    data: nil
                )
            ))
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
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: result))

            case "SendStreamingMessage":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<SendMessageRequest>.self, from: data
                )
                let params = try requireParams(envelope.params)
                return .stream(handleStreamingMessage(params, auth: auth), rpcID: rpcID)

            case "GetTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<GetTaskParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let task = try await getTask(id: params.id, historyLength: params.historyLength, auth: auth)
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: task))

            case "ListTasks":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskQueryParams>.self, from: data
                )
                let params = envelope.params ?? TaskQueryParams()
                let response = try await listTasks(params, auth: auth)
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: response))

            case "CancelTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<CancelTaskRequest>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let task = try await cancelTask(id: params.id, metadata: params.metadata, auth: auth)
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: task))

            case "SubscribeToTask":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskIdParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let stream = try await subscribeToTask(id: params.id, auth: auth)
                return .stream(stream, rpcID: rpcID)

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
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: result))

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
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: result))

            case "ListTaskPushNotificationConfigs":
                let envelope = try decoder.decode(
                    JSONRPCRequestEnvelope<TaskIDOnlyParams>.self, from: data
                )
                let params = try requireParams(envelope.params)
                let result = try await listPushNotificationConfigs(taskID: params.taskId, auth: auth)
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: result))

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
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: EmptyResult()))

            case "GetExtendedAgentCard":
                let base = headers["host"].map { "http://\($0)" } ?? "http://localhost"
                let card = try await extendedAgentCard(baseURL: base, auth: auth)
                return .json(try Self.jsonrpcSuccessData(id: rpcID, result: card))

            default:
                return .json(Self.jsonrpcErrorData(
                    id: rpcID,
                    error: JSONRPCErrorBody(
                        code: JSONRPCErrorCode.methodNotFound.rawValue,
                        message: "Method not found: \(methodOnly.method)",
                        data: nil
                    )
                ))
            }
        } catch let error as A2AError {
            switch error {
            case .authenticationRequired, .authorizationFailed:
                // Spec: authentication is transport-level. Signal it with an
                // HTTP status (401/403), not an off-spec JSON-RPC error code.
                return .unauthenticated(error)
            default:
                return .json(Self.jsonrpcErrorData(id: rpcID, error: error.toJSONRPCError()))
            }
        } catch let error as DecodingError {
            // Params that fail to decode are an InvalidParams (-32602)
            // condition per JSON-RPC 2.0, not an internal server error.
            return .json(Self.jsonrpcErrorData(
                id: rpcID,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.invalidParams.rawValue,
                    message: "Invalid params: \(Self.describe(error))",
                    data: nil
                )
            ))
        } catch {
            return .json(Self.jsonrpcErrorData(
                id: rpcID,
                error: JSONRPCErrorBody(
                    code: JSONRPCErrorCode.internalError.rawValue,
                    message: error.localizedDescription,
                    data: nil
                )
            ))
        }
    }

    // MARK: - Helpers

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

    private static func jsonrpcSuccessData<T: Encodable>(
        id: JSONRPCIdentifier?,
        result: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONRPCSuccessResponse(id: id, result: result))
    }

    private static func jsonrpcErrorData(
        id: JSONRPCIdentifier?,
        error: JSONRPCErrorBody
    ) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(JSONRPCErrorResponse(id: id, error: error)) {
            return data
        }
        // Last-resort static envelope; encoding the value types above cannot
        // realistically fail.
        return Data(#"{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}"#.utf8)
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
