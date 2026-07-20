//
//  ArchitectureRetryTests.swift
//  NebulaTests
//
//  Wave N1 — Network. Tests for NebulaRetryPolicy (delay math, jitter bounds,
//  fluent builders, Sendable) and NebulaRetry.withPolicy (retry-until-success,
//  exhaustion, non-retriable surfacing, HTTP-status retry, cancellation). The
//  retry loop is tested with an instant sleeper so counting is deterministic.
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

// MARK: - NebulaRetryPolicy

@Suite("NebulaRetryPolicy")
struct NebulaRetryPolicyTests {

    @Test func delayNoJitterIsExponential() {
        let p = NebulaRetryPolicy(maxAttempts: 5, baseDelay: .milliseconds(100),
                                  multiplier: 2, maxDelay: .seconds(30), jitter: .none)
        #expect(p.delay(forFailedAttempt: 0) == .milliseconds(100))
        #expect(p.delay(forFailedAttempt: 1) == .milliseconds(200))
        #expect(p.delay(forFailedAttempt: 2) == .milliseconds(400))
        #expect(p.delay(forFailedAttempt: 3) == .milliseconds(800))
    }

    @Test func delayCappedAtMax() {
        let p = NebulaRetryPolicy(maxAttempts: 5, baseDelay: .milliseconds(100),
                                  multiplier: 2, maxDelay: .milliseconds(250), jitter: .none)
        #expect(p.delay(forFailedAttempt: 2) == .milliseconds(250))
        #expect(p.delay(forFailedAttempt: 10) == .milliseconds(250))
    }

    @Test func delayFullJitterStaysInBounds() {
        let p = NebulaRetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(100),
                                  multiplier: 1, maxDelay: .seconds(30), jitter: .full)
        for _ in 0..<64 {
            let d = p.delay(forFailedAttempt: 0)
            #expect(d >= .zero)
            #expect(d < .milliseconds(100))
        }
    }

    @Test func delayEqualJitterStaysInBounds() {
        let p = NebulaRetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(100),
                                  multiplier: 1, maxDelay: .seconds(30), jitter: .equal)
        for _ in 0..<64 {
            let d = p.delay(forFailedAttempt: 0)
            #expect(d >= .milliseconds(50))
            #expect(d < .milliseconds(100))
        }
    }

    @Test func maxAttemptsClampedToOne() {
        #expect(NebulaRetryPolicy(maxAttempts: 0).maxAttempts == 1)
        #expect(NebulaRetryPolicy(maxAttempts: -5).maxAttempts == 1)
        #expect(NebulaRetryPolicy(maxAttempts: 4).maxAttempts == 4)
    }

    @Test func fluentBuildersCopy() {
        let p = NebulaRetryPolicy()
        #expect(p.withMaxAttempts(7).maxAttempts == 7)
        #expect(p.withBaseDelay(.seconds(1)).baseDelay == .seconds(1))
        #expect(p.withMultiplier(3).multiplier == 3)
        #expect(p.withMaxDelay(.seconds(5)).maxDelay == .seconds(5))
        #expect(p.withJitter(.none).jitter == .none)
        let custom = p.withIsRetriable { _ in true }
        #expect(custom.isRetriable(URLError(.badURL)))
    }

    @Test func defaultIsRetriableRetriesTransientTransport() {
        let f = NebulaRetryPolicy.defaultIsRetriable
        #expect(f(URLError(.timedOut)))
        #expect(f(URLError(.cannotConnectToHost)))
        #expect(f(URLError(.networkConnectionLost)))
        #expect(f(URLError(.notConnectedToInternet)))
        #expect(f(URLError(.dnsLookupFailed)))
        #expect(f(URLError(.cannotFindHost)))
    }

    @Test func defaultIsRetriableDoesNotRetryTerminalTransport() {
        let f = NebulaRetryPolicy.defaultIsRetriable
        #expect(!f(URLError(.badURL)))
        #expect(!f(URLError(.cancelled)))
        #expect(!f(URLError(.userAuthenticationRequired)))
    }

    @Test func defaultIsRetriableRetries5xxAnd408_429() {
        let f = NebulaRetryPolicy.defaultIsRetriable
        #expect(f(NebulaHTTPStatusError(code: 500)))
        #expect(f(NebulaHTTPStatusError(code: 502)))
        #expect(f(NebulaHTTPStatusError(code: 503)))
        #expect(f(NebulaHTTPStatusError(code: 504)))
        #expect(f(NebulaHTTPStatusError(code: 408)))
        #expect(f(NebulaHTTPStatusError(code: 429)))
    }

    @Test func defaultIsRetriableDoesNotRetry4xx() {
        let f = NebulaRetryPolicy.defaultIsRetriable
        #expect(!f(NebulaHTTPStatusError(code: 400)))
        #expect(!f(NebulaHTTPStatusError(code: 401)))
        #expect(!f(NebulaHTTPStatusError(code: 403)))
        #expect(!f(NebulaHTTPStatusError(code: 404)))
    }

    @Test func policyIsSendableAcrossTasks() async {
        let p = NebulaRetryPolicy(maxAttempts: 2, baseDelay: .milliseconds(1), jitter: .none)
        let result = await withCheckedContinuation { (cont: CheckedContinuation<NebulaRetryPolicy, Never>) in
            Task { cont.resume(returning: p) }
        }
        #expect(result.maxAttempts == 2)
    }
}

// MARK: - NebulaRetry.withPolicy

@Suite("NebulaRetry.withPolicy")
struct NebulaRetryTests {

    private func instantSleeper() -> @Sendable (Duration) async throws -> Void {
        { _ in }
    }

    @Test func retriesUntilSuccess() async throws {
        let calls = Counter()
        let value = try await NebulaRetry.withPolicy(
            .init(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none),
            sleeper: instantSleeper()
        ) { () async throws -> String in
            let n = calls.incrementAndReturn()
            if n < 3 { throw URLError(.timedOut) }
            return "ok"
        }
        #expect(value == "ok")
        #expect(calls.value == 3)
    }

    @Test func exhaustsAttemptsThenRethrows() async {
        let calls = Counter()
        await #expect(throws: URLError.self) {
            _ = try await NebulaRetry.withPolicy(
                .init(maxAttempts: 2, baseDelay: .milliseconds(1), jitter: .none),
                sleeper: instantSleeper()
            ) { () async throws -> String in
                _ = calls.incrementAndReturn()
                throw URLError(.timedOut)
            }
        }
        #expect(calls.value == 2)
    }

    @Test func nonRetriableErrorSurfacesImmediately() async {
        let calls = Counter()
        await #expect(throws: URLError.self) {
            _ = try await NebulaRetry.withPolicy(
                .init(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none),
                sleeper: instantSleeper()
            ) { () async throws -> String in
                _ = calls.incrementAndReturn()
                throw URLError(.badURL)
            }
        }
        #expect(calls.value == 1)
    }

    @Test func httpStatusRetriableUntilSuccess() async throws {
        let calls = Counter()
        let value = try await NebulaRetry.withPolicy(
            .init(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none),
            sleeper: instantSleeper()
        ) { () async throws -> Int in
            let n = calls.incrementAndReturn()
            if n < 3 { throw NebulaHTTPStatusError(code: 503) }
            return 200
        }
        #expect(value == 200)
        #expect(calls.value == 3)
    }

    @Test func httpStatus4xxNotRetried() async {
        let calls = Counter()
        await #expect(throws: NebulaHTTPStatusError.self) {
            _ = try await NebulaRetry.withPolicy(
                .init(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none),
                sleeper: instantSleeper()
            ) { () async throws -> Int in
                _ = calls.incrementAndReturn()
                throw NebulaHTTPStatusError(code: 404)
            }
        }
        #expect(calls.value == 1)
    }

    @Test func cancellationErrorIsNeverRetried() async {
        let calls = Counter()
        // A predicate that would retry anything — CancellationError must still
        // surface on the first attempt, unretried.
        let alwaysRetry = NebulaRetryPolicy(maxAttempts: 5, baseDelay: .milliseconds(1),
                                             jitter: .none, isRetriable: { _ in true })
        await #expect(throws: CancellationError.self) {
            _ = try await NebulaRetry.withPolicy(alwaysRetry, sleeper: instantSleeper()) { () async throws -> Int in
                _ = calls.incrementAndReturn()
                throw CancellationError()
            }
        }
        #expect(calls.value == 1)
    }

    @Test func cancellationDuringSleepPropagates() async {
        let calls = Counter()
        let sleeper: @Sendable (Duration) async throws -> Void = { _ in
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await NebulaRetry.withPolicy(
                .init(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none),
                sleeper: sleeper
            ) { () async throws -> Int in
                _ = calls.incrementAndReturn()
                throw URLError(.timedOut)
            }
        }
        #expect(calls.value == 1)
    }

    @Test func customPredicateDecidesRetry() async throws {
        let calls = Counter()
        // Retry only on a marker error, not on URLError.
        struct Marker: Error, Sendable {}
        let policy = NebulaRetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), jitter: .none,
                                       isRetriable: { ($0 as? Marker) != nil })
        let value = try await NebulaRetry.withPolicy(policy, sleeper: instantSleeper()) { () async throws -> Int in
            let n = calls.incrementAndReturn()
            if n < 2 { throw Marker() }
            return 7
        }
        #expect(value == 7)
        #expect(calls.value == 2)
    }
}