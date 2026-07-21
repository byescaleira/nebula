//
//  NebulaAuthInterceptor.swift
//  Nebula
//
//  Wave N10 — Network. The concrete ``NebulaHTTPInterceptor`` for bearer-token
//  auth + 401 refresh-and-retry. Nebula's first `actor` (CLAUDE.md: "Actors,
//  not global actors… use `actor` when shared mutable state spans many call
//  sites and a single `Mutex` is awkward"). The actor coordinates **single-
//  flight** refresh: the first 401 refreshes, concurrent 401s `await` the same
//  in-flight `Task` (exactly one `NebulaTokenProvider.refresh()` call).
//  ``adapt(_:)`` injects `Authorization: Bearer <token>` (anonymous passthrough
//  when there is no token); ``retry(_:for:attempt:)`` detects a 401
//  ``NebulaError`` and retries **once** with the refreshed token. No new
//  ``NebulaError.Kind`` — the interceptor is transparent; a refresh failure
//  surfaces the app-supplied provider error in place of the 401. Foundation-only.
//  See vault/03-padroes/nebula-auth-interceptor.md.
//

import Foundation

/// A ``NebulaHTTPInterceptor`` that injects a bearer `Authorization` header
/// from a ``NebulaTokenProvider`` and performs **single-flight** 401
/// refresh-and-retry.
///
/// Nebula's first `actor`. The actor owns the cached current token and a
/// single in-flight refresh `Task`; when several concurrent requests hit a 401,
/// only the first triggers ``NebulaTokenProvider/refresh()`` and the rest
/// `await` the same task — avoiding N parallel refreshes against the auth
/// backend. After a successful refresh the cached token is updated; a failed
/// refresh clears the cache and surfaces the provider's error.
///
/// Behavior:
/// - ``adapt(_:)`` injects `Authorization: <provider.authorizationHeader(for:)>`.
///   When `currentToken()` is `nil` (no session), the endpoint passes through
///   unchanged (anonymous — no header).
/// - ``retry(_:for:attempt:)`` matches a 401 ``NebulaError`` (the form
///   ``NebulaHTTPGateway`` surfaces) at `attempt == 0`, refreshes once, and
///   returns the endpoint re-adapted with the new token. A second 401 (or any
///   non-401 error) is declined (`nil`) and surfaces.
///
/// The header is injected at the `URLRequest` layer via a private endpoint
/// wrapper; this works because ``NebulaHTTPGateway`` only fills config headers
/// for fields the endpoint did not set, so the injected `Authorization` is
/// preserved.
public actor NebulaAuthInterceptor<Provider: NebulaTokenProvider>: NebulaHTTPInterceptor {
    private let provider: Provider
    private var cachedToken: Provider.Token?
    private var inFlight: Task<Provider.Token, any Error>?

    /// Creates an interceptor backed by `provider`.
    public init(provider: Provider) {
        self.provider = provider
    }

    // MARK: - NebulaHTTPInterceptor

    public func adapt(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPEndpoint {
        guard let token = try await currentToken() else { return endpoint }
        return NebulaAuthInterceptor.inject(endpoint, authorization: provider.authorizationHeader(for: token))
    }

    public func retry(
        _ error: any Error,
        for endpoint: NebulaHTTPEndpoint,
        attempt: Int
    ) async throws -> NebulaHTTPEndpoint? {
        // Retry once: the chain offers a single retry pass (attempt 0); a
        // second 401 surfaces instead of looping forever.
        guard attempt == 0, NebulaAuthInterceptor.isUnauthorized(error) else { return nil }
        let token = try await refresh()
        return NebulaAuthInterceptor.inject(endpoint, authorization: provider.authorizationHeader(for: token))
    }

    // MARK: - Token coordination (actor-isolated)

    /// Returns the cached token, fetching it from the provider on first access.
    private func currentToken() async throws -> Provider.Token? {
        if let cachedToken { return cachedToken }
        let token = try await provider.currentToken()
        cachedToken = token
        return token
    }

    /// Refreshes the token with single-flight coordination. The first caller
    /// starts a `Task`; concurrent callers `await` the same in-flight task so
    /// the provider's `refresh()` runs exactly once. The slot is cleared on
    /// completion (`defer`); a caller that already captured the task reference
    /// still receives its result after the clear.
    private func refresh() async throws -> Provider.Token {
        if let inFlight { return try await inFlight.value }
        let task = Task { [provider] in try await provider.refresh() }
        inFlight = task
        defer { inFlight = nil }
        do {
            let token = try await task.value
            cachedToken = token
            return token
        } catch {
            cachedToken = nil
            throw error
        }
    }

    // MARK: - Pure helpers (nonisolated)

    /// `true` when `error` is the 401 `NebulaError` ``NebulaHTTPGateway``
    /// surfaces (domain `"Nebula.HTTP"`, code `401`). A non-401 `NebulaError`
    /// (5xx, `URLError`-bridged) does not match.
    private static nonisolated func isUnauthorized(_ error: any Error) -> Bool {
        guard let nebula = error as? NebulaError else { return false }
        return nebula.code.domain == "Nebula.HTTP" && nebula.code.code == 401
    }

    /// Wraps `endpoint` so its `URLRequest` carries `authorization` in the
    /// `Authorization` header. Nonisolated — pure, no actor state.
    private static nonisolated func inject(_ endpoint: NebulaHTTPEndpoint, authorization: String) -> NebulaHTTPEndpoint {
        _NebulaAuthAdaptingEndpoint(base: endpoint, authorization: authorization)
    }
}

/// A private ``NebulaHTTPEndpoint`` that forwards everything to `base` except
/// it sets the `Authorization` header on the built `URLRequest`. `Sendable` by
/// derived conformance (`base` is `Sendable`, `authorization` is `String`); no
/// `@unchecked`. The `cachePolicy` forwards to `base` so existential dispatch
/// honors the original endpoint's policy.
private struct _NebulaAuthAdaptingEndpoint: NebulaHTTPEndpoint {
    let base: NebulaHTTPEndpoint
    let authorization: String

    func urlRequest(against baseURL: URL?) throws -> URLRequest {
        var request = try base.urlRequest(against: baseURL)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    var cachePolicy: NebulaHTTPCachePolicy { base.cachePolicy }
}