//
//  NebulaTokenProvider.swift
//  Nebula
//
//  Wave N10 — Network. The token-provider port: a `Sendable` source of auth
//  tokens used by ``NebulaAuthInterceptor``. PAT (not a generic method) so the
//  concrete ``NebulaAuthInterceptor`` is generic over `Provider` and the
//  `Token` type is concrete inside the actor. The app owns the concrete
//  conformer (read tokens from Keychain via ``NebulaKeychain``, refresh against
//  its auth backend); Nebula owns the single-flight refresh coordination.
//  Foundation-only. See vault/03-padroes/nebula-auth-interceptor.md.
//

import Foundation

/// A source of auth tokens for ``NebulaAuthInterceptor``.
///
/// The **port** the app conforms to supply the credentials ``NebulaAuthInterceptor``
/// injects. A PAT with an `associatedtype Token: Sendable` so the concrete
/// interceptor is generic over a concrete token type (e.g. `String` for a
/// bearer JWT, `Data` for a raw token). The app owns the conformer:
/// - ``currentToken()`` returns the current token, or `nil` when there is no
///   logged-in session (anonymous passthrough — no `Authorization` header is
///   injected).
/// - ``refresh()`` obtains a fresh token, throwing an app-supplied error on
///   failure (the interceptor surfaces that error in place of the 401).
/// - ``authorizationHeader(for:)`` formats a token as the `Authorization`
///   header value (e.g. `"Bearer <jwt>"`).
public protocol NebulaTokenProvider: Sendable {
    /// The token type. `Sendable` so it can cross the interceptor's actor
    /// isolation.
    associatedtype Token: Sendable

    /// The current token, or `nil` when there is no logged-in session.
    func currentToken() async throws -> Token?

    /// Obtains a fresh token. Throws an app-supplied error on failure — the
    /// interceptor surfaces it in place of the 401 that triggered the refresh.
    func refresh() async throws -> Token

    /// Formats `token` as the `Authorization` header value (e.g.
    /// `"Bearer <jwt>"`).
    func authorizationHeader(for token: Token) -> String
}