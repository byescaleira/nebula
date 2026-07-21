//
//  ArchitectureAuthTests.swift
//  NebulaTests
//
//  Wave N10 — Network. Tests for the interceptor seam: ``NebulaHTTPInterceptor``
//  (port), ``NebulaHTTPInterceptorChain`` (compose/adapt/retry-once,
//  cancellation passthrough), ``NebulaInterceptedClient`` +
//  ``NebulaHTTPClient/intercepted(by:)`` wiring, and ``NebulaAuthInterceptor``
//  (the first Nebula `actor` — bearer injection, 401 refresh-and-retry,
//  single-flight under concurrent 401s, retry-once cap). No network / no
//  URLProtocol — a behavior-driven fake ``NebulaHTTPClient`` returns canned
//  outcomes (response / HTTP status / cancellation) in send order. See
//  vault/03-padroes/nebula-auth-interceptor.md.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - A Sendable attempt counter (Mutex absorbed behind a final class so
// the ~Copyable Mutex can be captured in a @Sendable operation closure).

private final class Counter: Sendable {
    private let count = Mutex<Int>(0)
    @discardableResult
    func incrementAndReturn() -> Int { count.withLock { c in c += 1; return c } }
    var value: Int { count.withLock { $0 } }
}

// MARK: - A behavior-driven fake NebulaHTTPClient. Records the built URLRequests
// and returns a canned outcome per send (1-based index). `final class` so the
// ~Copyable Mutex is absorbed behind a copyable, Sendable reference.

private enum Canned: Sendable {
    case response(NebulaHTTPResponse)
    case httpStatus(Int)        // throws the NebulaError NebulaHTTPGateway would surface
    case cancellation           // throws CancellationError
}

private final class SequenceClient: NebulaHTTPClient {
    private struct State: Sendable {
        var behavior: @Sendable (Int) -> Canned
        var sends: Int = 0
        var requests: [URLRequest] = []
    }
    private let state: Mutex<State>
    let baseURL: URL?

    init(baseURL: URL? = URL(string: "https://api.test"), behavior: @escaping @Sendable (Int) -> Canned) {
        self.baseURL = baseURL
        self.state = Mutex(State(behavior: behavior))
    }

    var decoder: NebulaJSONDecoder { .init() }
    var encoder: NebulaJSONEncoder { .init() }

    func send(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPResponse {
        let request = try endpoint.urlRequest(against: baseURL)
        let outcome = state.withLock { s in
            s.sends += 1
            s.requests.append(request)
            return s.behavior(s.sends)
        }
        switch outcome {
        case .response(let response):
            return response
        case .httpStatus(let code):
            throw NebulaError(code: .init(domain: "Nebula.HTTP", code: code), kind: .network, message: "HTTP \(code)")
        case .cancellation:
            throw CancellationError()
        }
    }

    var sends: Int { state.withLock { $0.sends } }
    var requests: [URLRequest] { state.withLock { $0.requests } }
}

// MARK: - A test NebulaTokenProvider. Tracks refresh count; optionally delays
// refresh (to widen the single-flight window) and/or throws on refresh.

private struct TestRefreshError: Error, Sendable {
    static let failed = TestRefreshError()
}

private final class TestTokenProvider: NebulaTokenProvider {
    typealias Token = String
    private struct State: Sendable {
        var current: String?
        var refreshCount: Int = 0
        var refreshDelay: Duration?
        var refreshThrows: Bool = false
    }
    private let mutex: Mutex<State>

    init(current: String? = "old", refreshDelay: Duration? = nil, refreshThrows: Bool = false) {
        self.mutex = Mutex(State(current: current, refreshDelay: refreshDelay, refreshThrows: refreshThrows))
    }

    func currentToken() async throws -> String? { mutex.withLock { $0.current } }

    func refresh() async throws -> String {
        let delay = mutex.withLock { $0.refreshDelay }
        if let delay { try? await Task.sleep(for: delay) }
        let count = mutex.withLock { s in s.refreshCount += 1; return s.refreshCount }
        if mutex.withLock({ $0.refreshThrows }) { throw TestRefreshError.failed }
        return "new-\(count)"
    }

    func authorizationHeader(for token: String) -> String { "Bearer \(token)" }

    var refreshCount: Int { mutex.withLock { $0.refreshCount } }
}

// MARK: - A recording-only interceptor (adapt passthrough + count, retry count +
// decline). Used to assert chain composition and that cancellation is not retried.

private final class RecordingInterceptor: NebulaHTTPInterceptor {
    private let adaptCount = Mutex<Int>(0)
    private let retryCount = Mutex<Int>(0)

    func adapt(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPEndpoint {
        adaptCount.withLock { $0 += 1 }
        return endpoint
    }

    func retry(_ error: any Error, for endpoint: NebulaHTTPEndpoint, attempt: Int) async throws -> NebulaHTTPEndpoint? {
        retryCount.withLock { $0 += 1 }
        return nil
    }

    var adaptCountValue: Int { adaptCount.withLock { $0 } }
    var retryCountValue: Int { retryCount.withLock { $0 } }
}

// MARK: - Fixtures

private let okResponse = NebulaHTTPResponse(statusCode: 200)
private func endpoint(_ path: String = "items", cachePolicy: NebulaHTTPCachePolicy = .protocolDefault) -> NebulaHTTPRequest {
    NebulaHTTPRequest(method: .get, path: path, cachePolicy: cachePolicy)
}

// MARK: - NebulaHTTPInterceptorChain

@Suite("NebulaHTTPInterceptorChain")
struct NebulaHTTPInterceptorChainTests {

    @Test func emptyChainForwardsSend() async throws {
        let client = SequenceClient { _ in .response(okResponse) }
        let response = try await client.intercepted(by: NebulaHTTPInterceptorChain()).send(endpoint())
        #expect(response == okResponse)
        #expect(client.sends == 1)
    }

    @Test func adaptRunsOncePerSend() async throws {
        let client = SequenceClient { _ in .response(okResponse) }
        let recording = RecordingInterceptor()
        let intercepted = client.intercepted(by: [recording])
        _ = try await intercepted.send(endpoint())
        #expect(recording.adaptCountValue == 1)
        #expect(recording.retryCountValue == 0)
    }

    @Test func cancellationIsNotRetried() async {
        let client = SequenceClient { _ in .cancellation }
        let recording = RecordingInterceptor()
        let intercepted = client.intercepted(by: [recording])
        await #expect(throws: CancellationError.self) {
            _ = try await intercepted.send(endpoint())
        }
        // The chain rethrows cancellation before the retry pass runs.
        #expect(recording.retryCountValue == 0)
        #expect(recording.adaptCountValue == 1)
    }

    @Test func declinedRetrySurfacesOriginalError() async {
        let client = SequenceClient { _ in .httpStatus(500) }
        let recording = RecordingInterceptor()
        let intercepted = client.intercepted(by: [recording])
        do {
            _ = try await intercepted.send(endpoint())
            Issue.record("expected a 500 error")
        } catch let error as NebulaError {
            #expect(error.code.code == 500)
            #expect(error.code.domain == "Nebula.HTTP")
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
        // retry was offered (and declined) for the 500.
        #expect(recording.retryCountValue == 1)
        #expect(client.sends == 1)
    }
}

// MARK: - NebulaAuthInterceptor.adapt

@Suite("NebulaAuthInterceptor.adapt")
struct NebulaAuthInterceptorAdaptTests {

    @Test func injectsBearerHeader() async throws {
        let provider = TestTokenProvider(current: "old")
        let interceptor = NebulaAuthInterceptor(provider: provider)
        let adapted = try await interceptor.adapt(endpoint())
        let request = try adapted.urlRequest(against: URL(string: "https://api.test")!)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func noTokenPassesThroughAnonymously() async throws {
        let provider = TestTokenProvider(current: nil)
        let interceptor = NebulaAuthInterceptor(provider: provider)
        let adapted = try await interceptor.adapt(endpoint())
        let request = try adapted.urlRequest(against: URL(string: "https://api.test")!)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func forwardsCachePolicy() async throws {
        let provider = TestTokenProvider(current: "old")
        let interceptor = NebulaAuthInterceptor(provider: provider)
        let adapted = try await interceptor.adapt(endpoint("items", cachePolicy: .bypass))
        #expect(adapted.cachePolicy == .bypass)
    }
}

// MARK: - NebulaAuthInterceptor 401 refresh-and-retry

@Suite("NebulaAuthInterceptor 401")
struct NebulaAuthInterceptor401Tests {

    @Test func refreshesAndRetriesOnce() async throws {
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { n in n == 1 ? .httpStatus(401) : .response(okResponse) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        let response = try await intercepted.send(endpoint())
        #expect(response == okResponse)
        #expect(client.sends == 2)
        #expect(provider.refreshCount == 1)
        // The retry request carries the refreshed token (send 2).
        let retryRequest = try #require(client.requests.count == 2 ? client.requests[1] : nil)
        #expect(retryRequest.value(forHTTPHeaderField: "Authorization") == "Bearer new-1")
    }

    @Test func non401IsNotRetried() async {
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { _ in .httpStatus(500) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        do {
            _ = try await intercepted.send(endpoint())
            Issue.record("expected a 500 error")
        } catch let error as NebulaError {
            #expect(error.code.code == 500)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
        #expect(provider.refreshCount == 0)
        #expect(client.sends == 1)
    }

    @Test func second401SurfacesNoInfiniteLoop() async {
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { _ in .httpStatus(401) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        do {
            _ = try await intercepted.send(endpoint())
            Issue.record("expected a 401 error")
        } catch let error as NebulaError {
            #expect(error.code.code == 401)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
        // One refresh for the single retry pass; the second 401 surfaces.
        #expect(provider.refreshCount == 1)
        #expect(client.sends == 2)
    }

    @Test func refreshFailureSurfaces() async {
        let provider = TestTokenProvider(current: "old", refreshThrows: true)
        let client = SequenceClient { n in n == 1 ? .httpStatus(401) : .response(okResponse) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        do {
            _ = try await intercepted.send(endpoint())
            Issue.record("expected a refresh failure")
        } catch is TestRefreshError {
            // expected — the provider error surfaces in place of the 401
        } catch {
            Issue.record("expected TestRefreshError, got \(error)")
        }
        #expect(provider.refreshCount == 1)
        // Only the initial send ran; the retry aborted at refresh.
        #expect(client.sends == 1)
    }
}

// MARK: - NebulaAuthInterceptor concurrency (single-flight)

@Suite("NebulaAuthInterceptor concurrency", .serialized)
struct NebulaAuthInterceptorConcurrencyTests {

    @Test func concurrent401sShareSingleRefresh() async throws {
        // 401 for the first two sends (the two concurrent requests), then 200
        // for both retries.
        let provider = TestTokenProvider(current: "old", refreshDelay: .milliseconds(15))
        let client = SequenceClient { n in n <= 2 ? .httpStatus(401) : .response(okResponse) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        async let a = intercepted.send(endpoint())
        async let b = intercepted.send(endpoint())
        let (ra, rb) = try await (a, b)

        #expect(ra == okResponse)
        #expect(rb == okResponse)
        // Single-flight: both 401s shared one refresh.
        #expect(provider.refreshCount == 1)
        #expect(client.sends == 4)
        // Both retries carry the same refreshed token (proof of one refresh).
        #expect(client.requests.count == 4)
        #expect(client.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer new-1")
        #expect(client.requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer new-1")
    }

    @Test func adaptOnlyPathScalesWithoutRefresh() async throws {
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { _ in .response(okResponse) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        let successes = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    if (try? await intercepted.send(endpoint())) != nil {
                        successes.incrementAndReturn()
                    }
                }
            }
        }
        #expect(successes.value == 50)
        #expect(provider.refreshCount == 0)
    }
}

// MARK: - NebulaHTTPClient.intercepted(by:)

@Suite("NebulaHTTPClient intercepted")
struct NebulaHTTPClientInterceptedTests {

    @Test func verbsFunnelThroughInterceptor() async throws {
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { _ in .response(okResponse) }
        let intercepted = client.intercepted(by: [NebulaAuthInterceptor(provider: provider)])

        // A verb convenience builds a NebulaHTTPRequest and delegates to
        // intercepted.send → the auth interceptor injects the header.
        _ = try await intercepted.get("items")
        let request = try #require(client.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func composesMultipleInterceptorsInOrder() async throws {
        let recording = RecordingInterceptor()
        let provider = TestTokenProvider(current: "old")
        let client = SequenceClient { _ in .response(okResponse) }
        let intercepted = client.intercepted(by: [recording, NebulaAuthInterceptor(provider: provider)])

        _ = try await intercepted.send(endpoint())
        #expect(recording.adaptCountValue == 1)
        // The recording interceptor ran first (left-to-right); the auth
        // interceptor then injected the header on the final request.
        let request = try #require(client.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }
}