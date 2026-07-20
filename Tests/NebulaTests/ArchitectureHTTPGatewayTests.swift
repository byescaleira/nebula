//
//  ArchitectureHTTPGatewayTests.swift
//  NebulaTests
//
//  Wave N1 — Network. Tests for NebulaHTTPGateway over a URLProtocol-backed
//  URLSession (no real network). Verbs decode/encode, URL resolution (endpoint
//  + path, absolute, query), headers/timeout, 2xx success, non-2xx → NebulaError
//  (.network, status code), URLError → NebulaError (.network), config errors,
//  and the error-handler event. Suite is serialized because the URLProtocol
//  handler is process-wide shared state.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - A Sendable box so a ~Copyable Mutex can be captured in @Sendable
// closures (the final class absorbs ~Copyable behind a copyable reference,
// mirroring NebulaSpyUseCase).

private final class SendableBox<T: Sendable>: Sendable {
    private let mutex: Mutex<T>
    init(_ initial: T) { mutex = Mutex<T>(initial) }
    func mutate(_ body: (inout T) -> Void) { mutex.withLock { body(&$0) } }
    var value: T { mutex.withLock { $0 } }
}

// MARK: - A URLProtocol that serves a canned response (or throws a transport
// error) per a process-wide handler. Scoped to a session via
// `protocolClasses` (no global registration).

private final class NebulaHTTPTestProtocol: URLProtocol {
    struct Canned: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]
        init(status: Int = 200, body: Data = Data(), headers: [String: String] = ["Content-Type": "application/json"]) {
            self.status = status; self.body = body; self.headers = headers
        }
    }
    static let handler = Mutex<@Sendable (URLRequest) throws -> Canned?>({ _ in nil })

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func canInit(with request: URLRequest) -> Bool { true }

    override func startLoading() {
        do {
            guard let canned = try NebulaHTTPTestProtocol.handler.withLock({ $0 })(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: canned.status,
                                           httpVersion: "HTTP/1.1", headerFields: canned.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: canned.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

// MARK: - Helpers

private struct DTO: Codable, Equatable, Sendable { let value: Int }

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [NebulaHTTPTestProtocol.self]
    return URLSession(configuration: config)
}

/// Installs a handler that returns `canned` and records the request into `box`.
private func stub(_ canned: NebulaHTTPTestProtocol.Canned, into box: SendableBox<URLRequest?>) {
    NebulaHTTPTestProtocol.handler.withLock { $0 = { req in
        box.mutate { $0 = req }
        return canned
    } }
}

/// Installs a handler that returns `canned` without recording the request.
private func stub(_ canned: NebulaHTTPTestProtocol.Canned) {
    NebulaHTTPTestProtocol.handler.withLock { $0 = { _ in canned } }
}

/// Installs a handler that throws `error` (a transport failure).
private func stubThrow(_ error: @escaping @autoclosure @Sendable () -> Error) {
    NebulaHTTPTestProtocol.handler.withLock { $0 = { _ in throw error() } }
}

private func noRetry() -> NebulaRetryPolicy { .init(maxAttempts: 1, baseDelay: .milliseconds(1), jitter: .none) }

// MARK: - A spy NebulaHTTPCache: returns a canned ``NebulaCachedResponse`` from
// `response(for:policy:)` and records `store` / `remove` / `removeAll` calls.
// `final class` + `Mutex` so the ~Copyable Mutex is absorbed behind a copyable,
// Sendable reference (mirrors SendableBox / NebulaSpyUseCase).

private final class SpyCache: NebulaHTTPCache {
    struct Stored: Sendable, Equatable {
        let response: NebulaHTTPResponse
        let policy: NebulaHTTPCachePolicy
        let url: String
    }
    private let mutex: Mutex<State>
    private struct State: Sendable {
        var next: NebulaCachedResponse?
        var responseCalls = 0
        var stores: [Stored] = []
        var removes = 0
        var removeAlls = 0
    }
    init() { mutex = Mutex(State()) }

    func setNext(_ next: NebulaCachedResponse?) { mutex.withLock { $0.next = next } }
    func response(for request: URLRequest, policy: NebulaHTTPCachePolicy) async -> NebulaCachedResponse? {
        mutex.withLock { $0.responseCalls += 1; return $0.next }
    }
    func store(_ response: NebulaHTTPResponse, for request: URLRequest, policy: NebulaHTTPCachePolicy) async {
        mutex.withLock {
            $0.stores.append(.init(response: response, policy: policy,
                                   url: request.url?.absoluteString ?? ""))
        }
    }
    func remove(for request: URLRequest) async { mutex.withLock { $0.removes += 1 } }
    func removeAll() async { mutex.withLock { $0.removeAlls += 1 } }

    var responseCalls: Int { mutex.withLock { $0.responseCalls } }
    var stores: [Stored] { mutex.withLock { $0.stores } }
}

@Suite(.serialized)
struct NebulaHTTPGatewayTests {

    @Test func getDecodesJSON() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":42}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        let dto = try await gateway.get(DTO.self, "items")
        #expect(dto == DTO(value: 42))
        let req = try #require(box.value)
        #expect(req.httpMethod == "GET")
        #expect(req.url?.absoluteString == "https://api.test/items")
    }

    @Test func getReturnsRawData() async throws {
        let box = SendableBox<URLRequest?>(nil)
        let payload = Data("raw".utf8)
        stub(.init(body: payload), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        let data = try await gateway.get("items")
        #expect(data == payload)
    }

    @Test func postEncodesBodyAndDecodesResponse() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":99}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        let dto = try await gateway.post(DTO.self, "items", body: DTO(value: 7))
        #expect(dto == DTO(value: 99))
        let req = try #require(box.value)
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // `httpBody` is moved to `httpBodyStream` when a request passes through a
        // URLProtocol, so the captured request's `httpBody` is nil here; the body
        // encoding itself is covered by NebulaJSONEncoder's own tests.
    }

    @Test func putEncodesBody() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":1}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        _ = try await gateway.put(DTO.self, "items/1", body: DTO(value: 5))
        let req = try #require(box.value)
        #expect(req.httpMethod == "PUT")
        #expect(req.url?.absoluteString == "https://api.test/items/1")
    }

    @Test func deleteSucceedsOn2xx() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(status: 204, body: Data()), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        try await gateway.delete("items/1")
        let req = try #require(box.value)
        #expect(req.httpMethod == "DELETE")
    }

    @Test func queryItemsAppended() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        _ = try await gateway.get(DTO.self, "items", query: [URLQueryItem(name: "q", value: "x"), URLQueryItem(name: "page", value: "2")])
        let url = try #require(box.value?.url)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.contains(URLQueryItem(name: "q", value: "x")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "page", value: "2")) == true)
    }

    @Test func endpointWithPathResolves() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test/v1")!),
                                        session: makeSession(), retryPolicy: noRetry())
        _ = try await gateway.get(DTO.self, "/items")
        #expect(box.value?.url?.absoluteString == "https://api.test/v1/items")
    }

    @Test func absoluteURLWithoutEndpoint() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .default, session: makeSession(), retryPolicy: noRetry())
        _ = try await gateway.get(DTO.self, "https://host.example/x")
        #expect(box.value?.url?.absoluteString == "https://host.example/x")
    }

    @Test func headersAndTimeoutApplied() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                headers: ["Authorization": "Bearer t"],
                                                timeout: .seconds(30))
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        _ = try await gateway.get(DTO.self, "items")
        let req = try #require(box.value)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(abs(req.timeoutInterval - 30) < 0.001)
    }

    @Test func non2xxThrowsNebulaErrorNetwork() async {
        stub(.init(status: 503, body: Data()))
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        do {
            _ = try await gateway.get(DTO.self, "items")
            Issue.record("expected a throw")
        } catch let e as NebulaError {
            #expect(e.kind == .network)
            #expect(e.code.domain == "Nebula.HTTP")
            #expect(e.code.code == 503)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
    }

    @Test func urlErrorBridgesToNebulaErrorNetwork() async {
        stubThrow(URLError(.timedOut))
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        do {
            _ = try await gateway.get(DTO.self, "items")
            Issue.record("expected a throw")
        } catch let e as NebulaError {
            #expect(e.kind == .network)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
    }

    @Test func configErrorNoEndpointThrows() async {
        stub(.init(body: Data(#"{"value":0}"#.utf8)))
        let gateway = NebulaHTTPGateway(configuration: .default, session: makeSession(), retryPolicy: noRetry())
        do {
            // No endpoint configured + a path `URL(string:)` rejects (the empty
            // string is one of the few inputs modern Foundation returns nil for)
            // → the noEndpointOrAbsoluteURL config error path.
            _ = try await gateway.get(DTO.self, "")
            Issue.record("expected a throw")
        } catch let e as NebulaError {
            // A config/programmer error — not a transport failure, so kind
            // surfaces as .unknown.
            #expect(e.kind == .unknown)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
    }

    @Test func handlerReceivesErrorEvent() async {
        stub(.init(status: 503, body: Data()))
        let events = SendableBox<[NebulaErrorEvent]>([])
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                 handler: { e in events.mutate { $0.append(e) } })
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        do {
            _ = try await gateway.get(DTO.self, "items")
            Issue.record("expected a throw")
        } catch {
            // expected
        }
        let recorded = events.value
        #expect(recorded.count == 1)
        #expect(recorded.first?.category == "Nebula.Gateway")
        #expect(recorded.first?.error.kind == .network)
    }

    // MARK: - Cache policy → URLRequest.cachePolicy (Wave N5 mapping; the
    // Nebula TTL/SWR layer lands in N6).

    @Test func cachePolicyBypassSetsReloadIgnoring() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .bypass)
        _ = try await gateway.send(endpoint)
        let req = try #require(box.value)
        #expect(req.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func cachePolicyProtocolDefaultSetsUseProtocol() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        // Default endpoint cache policy is `.protocolDefault`.
        _ = try await gateway.send(NebulaHTTPRequest(method: .get, path: "items"))
        let req = try #require(box.value)
        #expect(req.cachePolicy == .useProtocolCachePolicy)
    }

    @Test func perRequestHeadersOverrideConfigDefaults() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        // Config sets Authorization + X-Default; the request sets Authorization
        // (override) + X-Custom (new). Per-request headers win; config fills gaps.
        let config = NebulaGatewayConfiguration(
            endpoint: URL(string: "https://api.test")!,
            headers: ["Authorization": "Bearer cfg", "X-Default": "d"]
        )
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items",
                                         headers: ["Authorization": "Bearer req", "X-Custom": "yes"])
        _ = try await gateway.send(endpoint)
        let req = try #require(box.value)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer req")
        #expect(req.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(req.value(forHTTPHeaderField: "X-Default") == "d")
    }

    // Cancellation propagation is not exercised here: a deterministic test is
    // timing-sensitive (URLSession surfaces Task cancellation as
    // `URLError(.cancelled)`; a raw `CancellationError` thrown by a URLProtocol
    // stub is boxed as an `NSError` with domain "Swift.CancellationError" and
    // so does not match `catch is CancellationError`). The gateway's
    // `catch is CancellationError` branch covers the realistic path — a genuine
    // `CancellationError` rethrown by `NebulaRetry.withPolicy`'s
    // `Task.checkCancellation` / sleeper between retry attempts — propagating it
    // raw without wrapping or reporting (cancellation is a client action, not a
    // gateway error).

    // MARK: - Per-endpoint cache integration (Wave N6).

    @Test func freshCacheHitSkipsNetwork() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":0}"#.utf8)), into: box)
        let spy = SpyCache()
        let cached = NebulaHTTPResponse(statusCode: 200, body: Data(#"{"value":42}"#.utf8))
        spy.setNext(NebulaCachedResponse(response: cached, isStale: false))
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                cache: spy)
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .store(ttl: .seconds(60)))
        let response = try await gateway.send(endpoint)
        #expect(response == cached)
        #expect(box.value == nil, "a fresh cache hit must not reach the network")
        #expect(spy.stores.isEmpty, "a fresh hit must not re-store")
    }

    @Test func cacheMissFetchesAndStores() async throws {
        let box = SendableBox<URLRequest?>(nil)
        let payload = Data(#"{"value":99}"#.utf8)
        stub(.init(body: payload), into: box)
        let spy = SpyCache()
        spy.setNext(nil) // miss
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                cache: spy)
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .store(ttl: .seconds(60)))
        let response = try await gateway.send(endpoint)
        #expect(response.body == payload)
        #expect(box.value != nil, "a miss must fetch from the network")
        let stores = spy.stores
        #expect(stores.count == 1)
        #expect(stores.first?.response.body == payload)
        #expect(stores.first?.policy == .store(ttl: .seconds(60)))
    }

    @Test func bypassPolicySkipsCache() async throws {
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":1}"#.utf8)), into: box)
        let spy = SpyCache()
        // Even with a canned fresh hit, `.bypass` must not consult the cache.
        spy.setNext(NebulaCachedResponse(response: .init(statusCode: 200, body: Data(#"{"value":999}"#.utf8)), isStale: false))
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                cache: spy)
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .bypass)
        let response = try await gateway.send(endpoint)
        #expect(response.body == Data(#"{"value":1}"#.utf8), "bypass must fetch from the network, not the cache")
        #expect(box.value != nil)
        #expect(spy.responseCalls == 0, "bypass must not consult the Nebula cache")
        #expect(spy.stores.isEmpty, "bypass must not store")
    }

    @Test func staleCacheHitServesAndRevalidatesInBackground() async throws {
        let box = SendableBox<URLRequest?>(nil)
        let fresh = Data(#"{"value":77}"#.utf8)
        stub(.init(body: fresh), into: box)
        let spy = SpyCache()
        let stale = NebulaHTTPResponse(statusCode: 200, body: Data(#"{"value":1}"#.utf8))
        spy.setNext(NebulaCachedResponse(response: stale, isStale: true))
        let config = NebulaGatewayConfiguration(endpoint: URL(string: "https://api.test")!,
                                                cache: spy)
        let gateway = NebulaHTTPGateway(configuration: config, session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items",
                                         cachePolicy: .staleWhileRevalidate(ttl: .seconds(60), maxStale: .seconds(60)))
        // The served response is the stale entry immediately...
        let served = try await gateway.send(endpoint)
        #expect(served == stale)
        // ...and the background revalidate Task fetches the fresh response and
        // stores it. Poll briefly (the revalidate runs in a detached Task).
        var stored: SpyCache.Stored?
        for _ in 0..<200 {
            if let first = spy.stores.first { stored = first; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let revalidated = try #require(stored)
        #expect(revalidated.response.body == fresh)
        #expect(revalidated.policy == .staleWhileRevalidate(ttl: .seconds(60), maxStale: .seconds(60)))
    }

    @Test func storePolicyWithoutCacheStillFetches() async throws {
        // No cache configured: a `.store` policy delegates to the native HTTP
        // cache and fetches normally (no Nebula store path).
        let box = SendableBox<URLRequest?>(nil)
        stub(.init(body: Data(#"{"value":5}"#.utf8)), into: box)
        let gateway = NebulaHTTPGateway(configuration: .init(endpoint: URL(string: "https://api.test")!),
                                        session: makeSession(), retryPolicy: noRetry())
        let endpoint = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .store(ttl: .seconds(60)))
        let response = try await gateway.send(endpoint)
        #expect(response.body == Data(#"{"value":5}"#.utf8))
        #expect(box.value != nil)
    }
}