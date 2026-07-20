//
//  NebulaURLCache.swift
//  Nebula
//
//  Wave N6 — Network. The concrete ``NebulaHTTPCache`` façade over the native
//  `URLCache`. Nebula owns the per-endpoint TTL / stale-while-revalidate
//  *metadata*; the native `URLCache` holds the response *bytes* ("Ambos —
//  Nebula sobre nativo", the user's choice). See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//
//  `URLCache` is thread-safe but the SDK does not mark it `Sendable` (verified
//  against the Xcode 27 Beta 3 `.swiftinterface` — `URLCache` appears only as an
//  `extension` adding the convenience `init(memoryCapacity:diskCapacity:directory:)`
//  at `Foundation.swiftinterface:15651`; no `Sendable` conformance). This is the
//  same situation as `UserDefaults` (see ``NebulaDefaults``): a `Mutex<State>`
//  provides the synchronization boundary (region-based isolation, the
//  CLAUDE.md alternative to `@unchecked`), and a `final class` absorbs the
//  `~Copyable` `Mutex` behind a copyable, `Sendable` reference (derived,
//  **no `@unchecked`** — the ``NebulaDefaults`` / ``NebulaSpyUseCase`` precedent).
//

import Foundation
import Synchronization

/// The concrete ``NebulaHTTPCache`` façade over the native `URLCache`.
///
/// Nebula owns the per-endpoint TTL / stale-while-revalidate metadata; the
/// native `URLCache` holds the response bytes. One `Mutex` guards both the
/// `URLCache` and the Nebula-owned metadata so they stay in sync (a hit reads
/// both atomically; a store writes both atomically).
///
/// `URLCache` is thread-safe but not `Sendable` in Swift 6, so the `Mutex`
/// provides the synchronization boundary and the `final class` derives
/// `Sendable` with no `@unchecked`. Pass a dedicated `URLCache` (e.g.
/// `URLCache(memoryCapacity:diskCapacity:directory:)`) per façade; `.shared` is
/// the convenience default.
///
/// ```swift
/// let cache = NebulaURLCache(URLCache(memoryCapacity: 4_000_000, diskCapacity: 0))
/// let gateway = NebulaHTTPGateway(configuration: .default.withCache(cache))
/// ```
public final class NebulaURLCache: NebulaHTTPCache {

    /// A cache key derived from a request's URL and method. `URLCache` keys on
    /// the full `URLRequest`; Nebula's metadata mirrors that with a
    /// `Hashable` value-type key so the metadata map can be a plain `Dictionary`.
    private struct Key: Hashable, Sendable {
        let url: String
        let method: String
        init(_ request: URLRequest) {
            self.url = request.url?.absoluteString ?? ""
            self.method = request.httpMethod ?? "GET"
        }
    }

    /// Nebula-owned freshness metadata for one cached entry: when it was stored
    /// and the TTL / max-stale window agreed at store time.
    private struct Entry: Sendable {
        let storedAt: Date
        let ttl: Duration
        let maxStale: Duration
    }

    /// The locked state: the native `URLCache` (bytes) plus Nebula's metadata
    /// map. `URLCache` is not `Sendable`, so `State` is not `Sendable` either —
    /// the `Mutex` is the synchronization boundary (as with `UserDefaults`).
    private struct State {
        var cache: URLCache
        var metadata: [Key: Entry]
    }

    private let mutex: Mutex<State>

    /// Creates a façade over `cache` (`.shared` by default).
    ///
    /// `cache` is a `sending` parameter (SE-0430): `Mutex`'s initializer takes
    /// the value `sending` (it holds it across isolation boundaries), and
    /// `URLCache` is not `Sendable`, so ownership must transfer at the call
    /// site — the compiler rejects any further use of that instance, preventing
    /// two regions from racing on the same non-`Sendable` store (mirrors
    /// ``NebulaDefaults/init(_:)``). Pass a dedicated `URLCache` per façade;
    /// `.shared` is the convenience default.
    public init(_ cache: sending URLCache = .shared) {
        self.mutex = Mutex(State(cache: cache, metadata: [:]))
    }

    public func response(for request: URLRequest, policy: NebulaHTTPCachePolicy) async -> NebulaCachedResponse? {
        // Only Nebula-managed policies consult this cache; protocol-default
        // delegates to URLSession's native HTTP cache and bypass skips entirely.
        // The request policy gates *whether* to consult; the stored entry's own
        // TTL / max-stale windows decide freshness (a request with a longer TTL
        // than the stored entry's simply misses and re-stores).
        guard Self.windows(for: policy) != nil else { return nil }
        return mutex.withLock { state -> NebulaCachedResponse? in
            let key = Key(request)
            guard let entry = state.metadata[key] else { return nil }
            guard let cached = state.cache.cachedResponse(for: request) else {
                // Bytes evicted under us — drop the orphaned metadata.
                state.metadata.removeValue(forKey: key)
                return nil
            }
            guard let http = cached.response as? HTTPURLResponse else { return nil }
            let response = NebulaHTTPResponse(
                statusCode: http.statusCode,
                headers: NebulaURLCache.headers(from: http),
                body: cached.data
            )
            let age = Duration.seconds(Date().timeIntervalSince(entry.storedAt))
            if age < entry.ttl {
                return NebulaCachedResponse(response: response, isStale: false)
            }
            if age < entry.ttl + entry.maxStale {
                return NebulaCachedResponse(response: response, isStale: true)
            }
            return nil
        }
    }

    public func store(_ response: NebulaHTTPResponse, for request: URLRequest, policy: NebulaHTTPCachePolicy) async {
        guard let (ttl, maxStale) = Self.windows(for: policy) else { return }
        guard let url = request.url else { return }
        mutex.withLock { state in
            guard let http = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            ) else { return }
            state.cache.storeCachedResponse(
                CachedURLResponse(response: http, data: response.body),
                for: request
            )
            state.metadata[Key(request)] = Entry(storedAt: Date(), ttl: ttl, maxStale: maxStale)
        }
    }

    public func remove(for request: URLRequest) async {
        mutex.withLock { state in
            state.cache.removeCachedResponse(for: request)
            state.metadata.removeValue(forKey: Key(request))
        }
    }

    public func removeAll() async {
        mutex.withLock { state in
            state.cache.removeAllCachedResponses()
            state.metadata.removeAll()
        }
    }

    /// Extracts the `(ttl, maxStale)` windows from a Nebula-managed policy, or
    /// `nil` for `.protocolDefault` / `.bypass` (not Nebula-managed).
    private static func windows(for policy: NebulaHTTPCachePolicy) -> (Duration, Duration)? {
        switch policy {
        case .protocolDefault, .bypass:
            return nil
        case .store(let ttl):
            return (ttl, .zero)
        case .staleWhileRevalidate(let ttl, let maxStale):
            return (ttl, maxStale)
        }
    }

    /// Extracts a `[String: String]` header snapshot from a cached HTTP
    /// response (mirrors ``NebulaHTTPGateway/headers(from:)`` — non-`String`
    /// fields are coerced via `String(describing:)` so none are dropped).
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
}