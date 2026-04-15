// Authenticator.swift
// A2AServer

import Foundation
import A2ACore

/// Server-side counterpart to `AuthenticationProvider`.
///
/// An authenticator inspects request headers and, if credentials are
/// present, returns an `AuthContext`. Returning `nil` means "no credentials
/// were provided"; throwing means "credentials were provided but invalid"
/// (e.g. an expired token, a malformed header).
///
/// The server framework enforces `AgentCard.securityRequirements` on top
/// of whatever the authenticator returns: if the card requires auth and
/// `authenticate` returns `nil`, the framework short-circuits with 401.
public protocol Authenticator: Sendable {
    /// Inspect headers and produce an `AuthContext` if credentials are valid.
    ///
    /// - Parameter headers: The raw HTTP request headers. Case-insensitive.
    /// - Returns: An `AuthContext` if credentials were extracted, or `nil`
    ///   if the request carries no credentials at all.
    /// - Throws: `A2AError.authenticationRequired` for invalid/expired
    ///   credentials, `A2AError.authorizationFailed` for insufficient scope.
    func authenticate(headers: [String: String]) async throws -> AuthContext?
}
