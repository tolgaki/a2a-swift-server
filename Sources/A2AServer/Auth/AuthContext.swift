// AuthContext.swift
// A2AServer

import Foundation
import A2ACore

/// Identity and credentials extracted from an inbound request by an
/// `Authenticator`. Passed through to the handler so it can make
/// user-scoped decisions.
public struct AuthContext: Sendable {
    /// HTTP authentication scheme name ("Bearer", "ApiKey", "Basic", etc.)
    public let scheme: String

    /// Raw credential value — for Bearer this is the token, for ApiKey
    /// this is the key itself, for Basic this is the `username:password`
    /// base64-decoded string.
    public let credential: String

    /// Arbitrary claims or metadata populated by custom authenticators.
    /// For example, a JWT authenticator might populate `sub`, `aud`, `scope`.
    public let claims: [String: AnyCodable]?

    public init(
        scheme: String,
        credential: String,
        claims: [String: AnyCodable]? = nil
    ) {
        self.scheme = scheme
        self.credential = credential
        self.claims = claims
    }
}
