// JSONRPC.swift
// A2AServer
//
// Internal JSON-RPC 2.0 envelope types for the server dispatcher.

import Foundation
import A2ACore

/// JSON-RPC 2.0 request envelope with decoded method/params.
struct JSONRPCRequestEnvelope<Params: Decodable>: Decodable {
    let jsonrpc: String
    let id: JSONRPCIdentifier?
    let method: String
    let params: Params?
}

/// Generic JSON-RPC request for pre-decoding the method name.
struct JSONRPCMethodOnly: Decodable {
    let jsonrpc: String
    let id: JSONRPCIdentifier?
    let method: String
}

/// JSON-RPC 2.0 success response envelope.
struct JSONRPCSuccessResponse<Result: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCIdentifier?
    let result: Result
}

/// JSON-RPC 2.0 error response envelope.
struct JSONRPCErrorResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCIdentifier?
    let error: JSONRPCErrorBody
}

/// JSON-RPC error body.
struct JSONRPCErrorBody: Encodable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

extension A2AError {
    /// Maps an `A2AError` to its spec-defined JSON-RPC code and message.
    func toJSONRPCError() -> JSONRPCErrorBody {
        switch self {
        case .taskNotFound(let taskId, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.taskNotFound.rawValue,
                message: message ?? "Task not found",
                data: AnyCodable(["taskId": taskId])
            )
        case .taskNotCancelable(let taskId, let state, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.taskNotCancelable.rawValue,
                message: message ?? "Task not cancelable",
                data: AnyCodable(["taskId": taskId, "state": state.rawValue])
            )
        case .pushNotificationNotSupported(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.pushNotificationNotSupported.rawValue,
                message: message ?? "Push notifications not supported",
                data: nil
            )
        case .unsupportedOperation(let operation, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.unsupportedOperation.rawValue,
                message: message ?? "Operation not supported: \(operation)",
                data: AnyCodable(["operation": operation])
            )
        case .contentTypeNotSupported(let contentType, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.contentTypeNotSupported.rawValue,
                message: message ?? "Content type not supported",
                data: AnyCodable(["contentType": contentType])
            )
        case .invalidAgentResponse(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.invalidAgentResponse.rawValue,
                message: message ?? "Invalid agent response",
                data: nil
            )
        case .extendedAgentCardNotConfigured(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.extendedAgentCardNotConfigured.rawValue,
                message: message ?? "Extended agent card not configured",
                data: nil
            )
        case .extensionSupportRequired(let uri, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.extensionSupportRequired.rawValue,
                message: message ?? "Extension required",
                data: AnyCodable(["extensionUri": uri])
            )
        case .versionNotSupported(let version, let supported, let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.versionNotSupported.rawValue,
                message: message ?? "Version not supported",
                data: AnyCodable([
                    "version": version,
                    "supportedVersions": supported ?? ["1.0"]
                ] as [String: Any])
            )
        case .authenticationRequired(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.authenticationRequired.rawValue,
                message: message ?? "Authentication required",
                data: nil
            )
        case .authorizationFailed(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.authorizationFailed.rawValue,
                message: message ?? "Authorization failed",
                data: nil
            )
        case .invalidRequest(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.invalidRequest.rawValue,
                message: message ?? "Invalid request",
                data: nil
            )
        case .internalError(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.internalError.rawValue,
                message: message ?? "Internal error",
                data: nil
            )
        case .invalidResponse(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.internalError.rawValue,
                message: message ?? "Invalid response",
                data: nil
            )
        case .encodingError(let underlying):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.internalError.rawValue,
                message: underlying?.localizedDescription ?? "Encoding error",
                data: nil
            )
        case .networkError(let underlying):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.internalError.rawValue,
                message: underlying?.localizedDescription ?? "Network error",
                data: nil
            )
        case .jsonRPCError(let code, let message, let data):
            return JSONRPCErrorBody(code: code, message: message, data: data)
        case .unknown(let message):
            return JSONRPCErrorBody(
                code: JSONRPCErrorCode.internalError.rawValue,
                message: message ?? "Unknown error",
                data: nil
            )
        }
    }
}
