// APIKeyAuthenticator.swift
// A2AServer

import Foundation
import A2ACore

/// Validates an API key from an HTTP header (default `X-API-Key`) against
/// either a static allowlist or a caller-supplied validation closure.
///
/// No external dependencies — suitable for internal or allowlist-based
/// authentication. For OAuth/JWT flows, implement `Authenticator` directly
/// against your identity provider.
public struct APIKeyAuthenticator: Authenticator {
    public let header: String
    private let validate: @Sendable (String) async throws -> Bool

    /// Creates an authenticator that accepts any key in the provided allowlist.
    public init(header: String = "X-API-Key", allowedKeys: Set<String>) {
        self.header = header
        self.validate = { key in allowedKeys.contains(key) }
    }

    /// Creates an authenticator that delegates validation to a closure.
    public init(
        header: String = "X-API-Key",
        validate: @Sendable @escaping (String) async throws -> Bool
    ) {
        self.header = header
        self.validate = validate
    }

    public func authenticate(headers: [String: String]) async throws -> AuthContext? {
        guard let key = lookup(headers, header), !key.isEmpty else {
            return nil
        }
        guard try await validate(key) else {
            throw A2AError.authenticationRequired(message: "Invalid API key")
        }
        return AuthContext(scheme: "ApiKey", credential: key)
    }

    private func lookup(_ headers: [String: String], _ name: String) -> String? {
        if let direct = headers[name] { return direct }
        let lower = name.lowercased()
        for (k, v) in headers where k.lowercased() == lower {
            return v
        }
        return nil
    }
}
