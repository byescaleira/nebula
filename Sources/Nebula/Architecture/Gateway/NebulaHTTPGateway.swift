//
//  NebulaHTTPGateway.swift
//  Nebula
//
//  Wave N1 → N5 — Network. The concrete ``NebulaHTTPClient`` (and
//  ``NebulaGateway``) over `URLSession`. Foundation-only (URLSession is
//  Foundation — no new framework import, no binding-rule tension). The Wave N1
//  verb methods are now default extensions on ``NebulaHTTPClient``; this struct's
//  one transport requirement is ``send(_:)``, which builds the `URLRequest`
//  from a ``NebulaHTTPEndpoint``, merges the config's headers/timeout/cache
//  policy, retries the transport call via ``NebulaRetry/withPolicy``, validates
//  the 2xx range, and returns a ``NebulaHTTPResponse``. Bridges `URLError` /
//  HTTP status failures to ``NebulaError`` (kind `.network`) and reports them
//  through the config's `handler`. See
//  vault/03-padroes/nebula-network-endpoint-client.md and
//  vault/03-padroes/nebula-network-retry.md.
//

import Foundation

/// An HTTP status failure: the response was received but its status code was
/// outside the `2xx` success range. Surfaced by ``NebulaHTTPGateway`` so the
/// retry predicate can distinguish "transport failed" (`URLError`) from
/// "server answered with an error status" and retry 5xx / 408 / 429
/// selectively (see ``NebulaRetryPolicy/defaultIsRetriable``).
public struct NebulaHTTPStatusError: Error, Sendable, Equatable {
    /// The HTTP status code (e.g. `503`).
    public let code: Int
    /// Creates a status error.
    public init(code: Int) { self.code = code }
}

/// A concrete ``NebulaHTTPClient`` over `URLSession`: the Foundation HTTP
/// adapter the Wave H gateway scaffold was built for.
///
/// Foundation-only (`URLSession` is Foundation — no new framework import).
/// Sends ``NebulaHTTPEndpoint``s and decodes JSON responses using the
/// ``NebulaGatewayConfiguration``'s ``NebulaJSONDecoder`` / ``NebulaJSONEncoder``
/// (exposed as the ``NebulaHTTPClient`` codec requirements, reused not
/// re-declared). Retries transport and retriable-status failures per
/// ``retryPolicy`` (``NebulaRetryPolicy``). All public verbs (inherited from the
/// ``NebulaHTTPClient`` default extension) and ``send(_:)`` throw ``NebulaError``
/// (kind `.network` for `URLError` / HTTP status); the original `URLError` /
/// ``NebulaHTTPStatusError`` is *not* retained (it is not `Sendable`-safe to box
/// generically) — the lossy `NebulaError` carries the domain/code/message.
///
/// `Sendable` by derived conformance: all stored properties
/// (``NebulaGatewayConfiguration`` / `URLSession` / ``NebulaRetryPolicy``) are
/// `Sendable` — no `@unchecked`.
public struct NebulaHTTPGateway: NebulaHTTPClient {

    /// The gateway configuration (endpoint, headers, codec, logger, timeout,
    /// error handler).
    public let configuration: NebulaGatewayConfiguration
    /// The `URLSession` used for transport. Defaults to `.shared`; inject a
    /// custom session (e.g. a `URLProtocol`-backed one) for tests.
    public let session: URLSession
    /// The retry policy applied to retriable transport / status failures.
    public let retryPolicy: NebulaRetryPolicy

    /// The JSON decoder (from ``configuration``), exposed to satisfy the
    /// ``NebulaHTTPClient`` codec contract used by the verb extensions.
    public var decoder: NebulaJSONDecoder { configuration.decoder }
    /// The JSON encoder (from ``configuration``), exposed to satisfy the
    /// ``NebulaHTTPClient`` codec contract used by the verb extensions.
    public var encoder: NebulaJSONEncoder { configuration.encoder }

    /// Creates a gateway.
    public init(
        configuration: NebulaGatewayConfiguration = .default,
        session: URLSession = .shared,
        retryPolicy: NebulaRetryPolicy = .init()
    ) {
        self.configuration = configuration
        self.session = session
        self.retryPolicy = retryPolicy
    }

    // MARK: - NebulaHTTPClient

    /// Sends `endpoint`: builds the `URLRequest`, merges the config's
    /// headers/timeout/cache policy, retries the transport call, validates the
    /// 2xx range, and returns the response. Config errors (no endpoint /
    /// unparseable URL) fail fast before the retry loop. For Nebula-managed
    /// cache policies (``NebulaHTTPCachePolicy/store(ttl:)`` /
    /// ``NebulaHTTPCachePolicy/staleWhileRevalidate(ttl:maxStale:)``) with a
    /// configured ``NebulaHTTPCache``, a fresh hit is served without a network
    /// fetch and a successful fetch is stored; a stale-while-revalidate hit is
    /// served immediately and revalidated in a background `Task`.
    public func send(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPResponse {
        let request: URLRequest
        do {
            request = try buildRequest(endpoint)
        } catch {
            let nebula = NebulaError(error: error)
            configuration.report(nebula)
            throw nebula
        }
        let policy = endpoint.cachePolicy
        // Consult the Nebula cache first for Nebula-managed policies. A fresh
        // hit short-circuits the network; a stale hit (SWR within maxStale) is
        // served immediately and revalidated in the background.
        if let cache = configuration.cache, NebulaHTTPGateway.isCacheable(policy) {
            if let cached = await cache.response(for: request, policy: policy) {
                if cached.isStale {
                    // Detached so the revalidate never hops onto a caller-isolated
                    // actor (e.g. a @MainActor app consumer) — it runs on the
                    // cooperative pool and the served response is not delayed.
                    Task.detached { [self] in await self.revalidate(request: request, policy: policy) }
                }
                return cached.response
            }
        }
        do {
            // Return only Sendable fragments from the @Sendable retry closure
            // (Data / Int / [String: String]) — not the URLResponse itself.
            let (data, statusCode, headers) = try await NebulaRetry.withPolicy(retryPolicy) { [session] () async throws -> (Data, Int, [String: String]) in
                let (d, r) = try await session.data(for: request)
                let http = try NebulaHTTPGateway.validate(r)
                return (d, http.statusCode, NebulaHTTPGateway.headers(from: http))
            }
            let response = NebulaHTTPResponse(statusCode: statusCode, headers: headers, body: data)
            // Store the 2xx response for Nebula-managed policies (validate
            // already guaranteed 2xx — a non-2xx threw NebulaHTTPStatusError).
            if let cache = configuration.cache, NebulaHTTPGateway.isCacheable(policy) {
                await cache.store(response, for: request, policy: policy)
            }
            return response
        } catch let status as NebulaHTTPStatusError {
            let nebula = NebulaError(
                code: .init(domain: "Nebula.HTTP", code: status.code),
                kind: .network,
                message: "HTTP \(status.code)"
            )
            configuration.report(nebula)
            throw nebula
        } catch let urlError as URLError {
            let nebula = NebulaError(urlError: urlError)
            configuration.report(nebula)
            throw nebula
        } catch is CancellationError {
            // Cancellation is a client-side action, not a gateway error: propagate
            // it raw (do NOT wrap as NebulaError, do NOT invoke the handler).
            throw CancellationError()
        } catch {
            let nebula = NebulaError(error: error)
            configuration.report(nebula)
            throw nebula
        }
    }

    // MARK: - Internal

    /// Builds the `URLRequest` from `endpoint`, then merges the config's
    /// headers (only for fields the endpoint did not set — per-request headers
    /// override config defaults), applies the config timeout, and maps the
    /// endpoint's cache policy to `URLRequest.cachePolicy`.
    private func buildRequest(_ endpoint: NebulaHTTPEndpoint) throws -> URLRequest {
        var request = try endpoint.urlRequest(against: configuration.endpoint)
        for (key, value) in configuration.headers {
            if request.value(forHTTPHeaderField: key) == nil {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let timeout = configuration.timeout {
            request.timeoutInterval = TimeInterval(timeout.components.seconds)
                + TimeInterval(timeout.components.attoseconds) * 1e-18
        }
        switch endpoint.cachePolicy {
        case .bypass:
            request.cachePolicy = .reloadIgnoringLocalCacheData
        case .protocolDefault:
            request.cachePolicy = .useProtocolCachePolicy
        case .store, .staleWhileRevalidate:
            // When Nebula owns the cache, bypass the native HTTP cache so
            // Nebula's TTL / stale-while-revalidate is authoritative (the
            // native cache would otherwise serve a stale entry on refetch);
            // otherwise delegate to the native protocol cache.
            request.cachePolicy = configuration.cache != nil
                ? .reloadIgnoringLocalCacheData
                : .useProtocolCachePolicy
        }
        return request
    }

    /// `true` when `policy` is Nebula-managed (``NebulaHTTPCachePolicy/store(ttl:)``
    /// or ``NebulaHTTPCachePolicy/staleWhileRevalidate(ttl:maxStale:)``) — the
    /// policies the gateway consults/stores via ``NebulaHTTPCache``.
    private static func isCacheable(_ policy: NebulaHTTPCachePolicy) -> Bool {
        switch policy {
        case .store, .staleWhileRevalidate: return true
        case .protocolDefault, .bypass: return false
        }
    }

    /// Validates the response: a non-`HTTPURLResponse` throws
    /// `URLError(.badServerResponse)`; a non-`2xx` status throws a
    /// ``NebulaHTTPStatusError`` carrying the code. Returns the HTTP response on
    /// success.
    private static func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200..<300).contains(http.statusCode) {
            throw NebulaHTTPStatusError(code: http.statusCode)
        }
        return http
    }

    /// Extracts a `[String: String]` header snapshot from an HTTP response.
    /// Non-`String`-valued fields (e.g. `Content-Length` delivered as `NSNumber`)
    /// are coerced via `String(describing:)` so no field is silently dropped.
    private static func headers(from http: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let k = key as? String else { continue }
            if let v = value as? String {
                result[k] = v
            } else {
                result[k] = String(describing: value)
            }
        }
        return result
    }

    /// Background stale-while-revalidate: re-fetches `request`, and on a 2xx
    /// stores the fresh response into the configured cache. Best-effort —
    /// transport errors are swallowed (the caller already served the stale
    /// response; a failed revalidate leaves the stale entry in place). Runs in
    /// a detached `Task` so it never blocks the served response.
    private func revalidate(request: URLRequest, policy: NebulaHTTPCachePolicy) async {
        guard let cache = configuration.cache else { return }
        do {
            let (d, r) = try await session.data(for: request)
            let http = try NebulaHTTPGateway.validate(r)
            let response = NebulaHTTPResponse(
                statusCode: http.statusCode,
                headers: NebulaHTTPGateway.headers(from: http),
                body: d
            )
            await cache.store(response, for: request, policy: policy)
        } catch {
            // Best-effort: a failed revalidate leaves the stale entry in place.
        }
    }
}