// NoOpBearerAuthenticator.swift
// A2AServer

import Foundation
import A2ACore

/// Accepts any non-empty `Authorization: Bearer <token>` header and passes
/// the raw token through in `AuthContext.credential`. Does **not** verify
/// the token — the handler is responsible for validation (AAD/Entra,
/// Auth0, Keycloak, AWS Cognito, etc.).
///
/// This is the right default for A2A because the spec deliberately does
/// not mandate a JWT shape. Every identity provider uses a different
/// token format; bundling a JWT library in the framework would make
/// choices the protocol explicitly leaves open.
///
/// ### Using with Microsoft Entra / Azure AD
///
/// Implement `Authenticator` yourself and call out to Microsoft Graph's
/// `/me` endpoint or validate the signature via `jwks_uri` discovered at
/// `https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration`.
public struct NoOpBearerAuthenticator: Authenticator {
    public init() {}

    public func authenticate(headers: [String: String]) async throws -> AuthContext? {
        guard let authHeader = lookup(headers, "Authorization") ?? lookup(headers, "authorization") else {
            return nil
        }
        let parts = authHeader.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else {
            return nil
        }
        let token = String(parts[1])
        guard !token.isEmpty else {
            throw A2AError.authenticationRequired(message: "Empty bearer token")
        }
        return AuthContext(scheme: "Bearer", credential: token)
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
