// ServerSentEventsEncoder.swift
// A2AServer

import Foundation
import A2ACore

/// Encodes `StreamResponse` frames into Server-Sent Events wire format.
///
/// This is a pure value-level encoder — no I/O, no buffering — so it can
/// be composed with Hummingbird's streaming body without pulling in NIO
/// dependencies here.
public struct ServerSentEventsEncoder: Sendable {
    public init() {}

    /// Encodes a `StreamResponse` as an SSE `data:` frame.
    ///
    /// - Parameters:
    ///   - event: The event to encode.
    ///   - wrappedInJSONRPC: Wrap the event in a JSON-RPC 2.0 response envelope
    ///     (for clients connecting via JSON-RPC), or emit the bare event (REST).
    ///   - rpcID: The JSON-RPC request id to echo in the wrapper. Ignored when
    ///     `wrappedInJSONRPC` is false.
    /// - Returns: Bytes suitable for writing to an SSE response body, including
    ///   the trailing blank line that terminates an SSE event.
    public func encode(
        _ event: StreamResponse,
        wrappedInJSONRPC: Bool,
        rpcID: JSONRPCIdentifier? = nil
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        if wrappedInJSONRPC {
            let wrapper = JSONRPCStreamWrapper(id: rpcID ?? .int(1), result: event)
            jsonData = try encoder.encode(wrapper)
        } else {
            jsonData = try encoder.encode(event)
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw A2AError.encodingError(underlying: nil)
        }

        // Format: `data: <json>\n\n`
        return Data("data: \(jsonString)\n\n".utf8)
    }

    /// Returns a keepalive comment frame per the SSE spec. Servers typically
    /// send these every 15 seconds to keep middleboxes from closing idle
    /// connections.
    public func keepalive() -> Data {
        Data(": keepalive\n\n".utf8)
    }
}

// MARK: - JSON-RPC Stream Wrapper

/// Minimal JSON-RPC 2.0 response envelope used to wrap streaming events.
public struct JSONRPCStreamWrapper: Encodable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCIdentifier
    public let result: StreamResponse

    public init(id: JSONRPCIdentifier, result: StreamResponse) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
    }
}

/// JSON-RPC 2.0 id — either an integer or a string.
public enum JSONRPCIdentifier: Codable, Sendable, Equatable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}
