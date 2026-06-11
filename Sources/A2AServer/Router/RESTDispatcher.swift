// RESTDispatcher.swift
// A2AServer
//
// REST handler implementations that pull params from the Hummingbird
// request and delegate to A2ADispatcher. Responses are encoded as JSON
// with AIP-193 error shapes (`{"error":{"code":…,"message":…}}`).

import Foundation
import Hummingbird
import NIOCore
import A2AClient

extension A2ADispatcher {
    // MARK: - Agent card

    func respondAgentCard<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let base = baseURL(from: req)
        let card = handler.agentCard(baseURL: base)
        return try jsonResponse(card, status: .ok)
    }

    // MARK: - Send message

    func restSendMessage<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let decoded: SendMessageRequest = try await decodeBody(req: req)
            let response = try await handleSendMessage(decoded, auth: auth)
            return try jsonResponse(response, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        } catch {
            return try errorResponse(.invalidRequest(message: "Invalid request body: \(error)"))
        }
    }

    func restSendStreamingMessage<Context: RequestContext>(
        req: Request,
        ctx: Context,
        rpcWrapped: Bool
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let decoded: SendMessageRequest = try await decodeBody(req: req)
            let stream = handleStreamingMessage(decoded, auth: auth)
            return sseResponse(stream: stream, wrappedInJSONRPC: false)
        } catch let error as A2AError {
            return try errorResponse(error)
        } catch {
            return try errorResponse(.invalidRequest(message: "Invalid request body: \(error)"))
        }
    }

    // MARK: - Task operations

    func restGetTask<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let id = ctx.parameters.get("id") ?? ""
            let historyLength = req.uri.queryParameters.get("historyLength").flatMap { Int(String($0)) }
            let task = try await getTask(id: id, historyLength: historyLength, auth: auth)
            return try jsonResponse(task, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    func restListTasks<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let query = parseTaskQueryParams(from: req)
            let response = try await listTasks(query, auth: auth)
            return try jsonResponse(response, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    func restCancelTaskByID<Context: RequestContext>(
        id: String,
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let body = (try? await decodeBody(req: req) as CancelTaskBody)
            let task = try await cancelTask(id: id, metadata: body?.metadata, auth: auth)
            return try jsonResponse(task, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    func restSubscribeToTaskByID<Context: RequestContext>(
        id: String,
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let stream = try await subscribeToTask(id: id, auth: auth)
            return sseResponse(stream: stream, wrappedInJSONRPC: false)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    // MARK: - Push notification CRUD

    func restCreatePushNotificationConfig<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let taskID = ctx.parameters.get("id") ?? ""

            // Accept both wire shapes:
            //   {"url":"...","token":"..."}                              (flat)
            //   {"taskId":"...","config":{"url":"...","token":"..."}}    (wrapped, matches the client)
            // The request body can only be consumed once, so collect it
            // first and try both decodes against the same bytes.
            let data = try await collectBody(req: req)
            let config: PushNotificationConfig
            if let wrapped = try? Self.bodyDecoder().decode(CreatePushConfigParams.self, from: data) {
                config = wrapped.config
            } else {
                config = try Self.bodyDecoder().decode(PushNotificationConfig.self, from: data)
            }

            let result = try await createPushNotificationConfig(taskID: taskID, config: config, auth: auth)
            return try jsonResponse(result, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        } catch {
            return try errorResponse(.invalidRequest(message: "Invalid request body: \(error)"))
        }
    }

    func restGetPushNotificationConfig<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let taskID = ctx.parameters.get("id") ?? ""
            let configID = ctx.parameters.get("configId") ?? ""
            let result = try await getPushNotificationConfig(taskID: taskID, configID: configID, auth: auth)
            return try jsonResponse(result, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    func restListPushNotificationConfigs<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let taskID = ctx.parameters.get("id") ?? ""
            let result = try await listPushNotificationConfigs(taskID: taskID, auth: auth)
            return try jsonResponse(result, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    func restDeletePushNotificationConfig<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let taskID = ctx.parameters.get("id") ?? ""
            let configID = ctx.parameters.get("configId") ?? ""
            try await deletePushNotificationConfig(taskID: taskID, configID: configID, auth: auth)
            return Response(status: .noContent)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    // MARK: - Extended agent card

    func restGetExtendedAgentCard<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let headers = req.headerMap()
        do {
            let auth = try await resolveAuth(headers: headers)
            let card = try await extendedAgentCard(baseURL: baseURL(from: req), auth: auth)
            return try jsonResponse(card, status: .ok)
        } catch let error as A2AError {
            return try errorResponse(error)
        }
    }

    // MARK: - Helpers

    func baseURL(from req: Request) -> String {
        // Reconstruct from the HTTPRequest authority (Host header). Tests
        // and local deploys set this correctly; production behind a proxy
        // may want X-Forwarded-*.
        if let authority = req.head.authority {
            let scheme = "http"  // TLS termination is usually at the proxy
            return "\(scheme)://\(authority)"
        }
        return "http://localhost"
    }

    func parseTaskQueryParams(from req: Request) -> TaskQueryParams {
        let q = req.uri.queryParameters
        let contextId = q.get("contextId").flatMap { String($0) }
        let statusStr = q.get("status").flatMap { String($0) }
        // TaskState(string:) accepts both v1.0 (TASK_STATE_COMPLETED) and
        // v0.3 ("completed") spellings.
        let status = statusStr.flatMap { TaskState(string: $0) }
        let pageSize = q.get("pageSize").flatMap { Int(String($0)) }
        let pageToken = q.get("pageToken").flatMap { String($0) }
        let historyLength = q.get("historyLength").flatMap { Int(String($0)) }
        let timestampAfter: Date? = {
            guard let raw = q.get("statusTimestampAfter").flatMap({ String($0) }) else { return nil }
            return ISO8601DateFormatter().date(from: raw)
        }()
        let includeArtifacts = q.get("includeArtifacts").flatMap { Bool(String($0)) }
        return TaskQueryParams(
            contextId: contextId,
            status: status,
            pageSize: pageSize,
            pageToken: pageToken,
            historyLength: historyLength,
            statusTimestampAfter: timestampAfter,
            includeArtifacts: includeArtifacts
        )
    }

    func collectBody(req: Request) async throws -> Data {
        let buffer = try await req.body.collect(upTo: 10 * 1024 * 1024)  // 10 MB cap
        return Data(buffer: buffer)
    }

    static func bodyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func decodeBody<T: Decodable>(req: Request) async throws -> T {
        let data = try await collectBody(req: req)
        return try Self.bodyDecoder().decode(T.self, from: data)
    }

    func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    func errorResponse(_ error: A2AError) throws -> Response {
        let body = error.toJSONRPCError()
        let httpStatus = httpStatus(for: error)
        // AIP-193 shape: {"error":{"code":…,"status":"…","message":"…"}}
        struct AIP193Body: Encodable {
            let error: AIP193Error
        }
        struct AIP193Error: Encodable {
            let code: Int
            let status: String
            let message: String
        }
        let aip = AIP193Body(error: AIP193Error(
            code: body.code,
            status: statusName(for: httpStatus),
            message: body.message
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(aip)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: httpStatus,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    private func httpStatus(for error: A2AError) -> HTTPResponse.Status {
        switch error {
        case .taskNotFound: return .notFound
        case .taskNotCancelable: return .conflict
        case .pushNotificationNotSupported: return .badRequest
        case .unsupportedOperation: return .badRequest
        case .contentTypeNotSupported: return .unsupportedMediaType
        case .versionNotSupported: return .badRequest
        case .extensionSupportRequired: return .badRequest
        case .invalidAgentResponse: return .badGateway
        case .extendedAgentCardNotConfigured: return .badRequest
        case .authenticationRequired: return .unauthorized
        case .authorizationFailed: return .forbidden
        case .invalidRequest: return .badRequest
        case .internalError: return .internalServerError
        default: return .internalServerError
        }
    }

    private func statusName(for status: HTTPResponse.Status) -> String {
        switch status {
        case .notFound: return "NOT_FOUND"
        case .conflict: return "FAILED_PRECONDITION"
        case .unauthorized: return "UNAUTHENTICATED"
        case .forbidden: return "PERMISSION_DENIED"
        case .badRequest: return "INVALID_ARGUMENT"
        case .unsupportedMediaType: return "UNSUPPORTED_MEDIA_TYPE"
        case .badGateway: return "UNAVAILABLE"
        case .internalServerError: return "INTERNAL"
        default: return "UNKNOWN"
        }
    }

    // MARK: - SSE response

    func sseResponse(
        stream: AsyncThrowingStream<StreamResponse, Error>,
        wrappedInJSONRPC: Bool,
        rpcID: JSONRPCIdentifier? = nil
    ) -> Response {
        let encoder = ServerSentEventsEncoder()
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        let body = ResponseBody { writer in
            do {
                for try await event in stream {
                    let bytes = try encoder.encode(
                        event,
                        wrappedInJSONRPC: wrappedInJSONRPC,
                        rpcID: rpcID
                    )
                    try await writer.write(ByteBuffer(bytes: bytes))
                }
                try await writer.finish(nil)
            } catch {
                // Emit a terminal error frame so clients see the failure
                // instead of a silently truncated stream, then terminate.
                let rpcError = (error as? A2AError ?? .internalError(message: error.localizedDescription))
                    .toJSONRPCError()
                let enc = JSONEncoder()
                let frameData: Data?
                if wrappedInJSONRPC {
                    frameData = try? enc.encode(JSONRPCErrorResponse(id: rpcID, error: rpcError))
                } else {
                    // Bare AIP-193 shape for the REST binding.
                    frameData = try? enc.encode(RESTStreamErrorFrame(
                        error: .init(code: rpcError.code, message: rpcError.message)
                    ))
                }
                if let frameData, let json = String(data: frameData, encoding: .utf8) {
                    try? await writer.write(ByteBuffer(bytes: Data("data: \(json)\n\n".utf8)))
                }
                try await writer.finish(nil)
            }
        }
        return Response(status: .ok, headers: headers, body: body)
    }
}

// MARK: - Request header convenience

extension Request {
    func headerMap() -> [String: String] {
        var map: [String: String] = [:]
        for field in self.headers {
            map[field.name.canonicalName] = field.value
        }
        return map
    }
}

// MARK: - Body helper types

/// AIP-193-shaped error frame emitted as the terminal SSE event when a
/// REST (non-JSON-RPC) stream fails.
struct RESTStreamErrorFrame: Encodable {
    struct Body: Encodable {
        let code: Int
        let message: String
    }
    let error: Body
}

struct CancelTaskBody: Decodable {
    let metadata: [String: AnyCodable]?
}

struct EmptyResult: Encodable {
    init() {}
}
