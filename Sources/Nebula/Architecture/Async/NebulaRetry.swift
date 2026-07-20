//
//  NebulaRetry.swift
//  Nebula
//
//  Wave N1 — Network. A Sendable retry policy + loop for any `async throws`
//  operation. The concrete ``NebulaHTTPGateway`` (Wave N1) wraps its
//  `URLSession` call in ``NebulaRetry/withPolicy(_:sleeper:operation:)``; the
//  policy is framework-agnostic, so any I/O use case can reuse it. Lives in
//  `Architecture/Async/` alongside ``NebulaResultPipeline`` (async-flow
//  helpers), NOT under `Gateway/` — retry is not HTTP-specific. See
//  vault/03-padroes/nebula-network-retry.md.
//

import Foundation

/// The jitter strategy ``NebulaRetryPolicy`` applies to a computed backoff
/// delay. Jitter decorrelates retried clients so a thundering herd of retries
/// doesn't slam a recovering server on the same clock.
public enum NebulaRetryJitter: Sendable, Equatable {
    /// No jitter — sleep the full computed delay. Deterministic; useful in
    /// tests but worst for thundering-herd avoidance.
    case none
    /// Full jitter — sleep a uniform random fraction `[0, delay)` of the
    /// computed delay. The recommended default (AWS Architecture Blog,
    /// "Exponential Backoff and Jitter").
    case full
    /// Equal jitter — sleep `[delay/2, delay)`. Less variance than full
    /// jitter; keeps a minimum wait while still decorrelating.
    case equal
}

/// A retry policy: how many times to try an `async throws` operation and how
/// long to wait between attempts.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` `isRetriable`
/// predicate closure, which cannot be compared, mirroring
/// ``NebulaGatewayConfiguration`` / ``NebulaErrorConfiguration``). Constructed
/// and passed explicitly (no SwiftUI `@Environment`); fluent `.with*`
/// builders return a copy.
///
/// - ``maxAttempts`` — total attempts **including the first**. `1` = no retry
///   (run once, surface any failure). Clamped to a minimum of `1`.
/// - ``baseDelay`` — the delay before the second attempt. Subsequent delays
///   scale by ``multiplier`` (`baseDelay * multiplier^index`).
/// - ``multiplier`` — the exponential backoff factor (default `2.0`).
/// - ``maxDelay`` — the cap applied after exponentiation (before jitter).
/// - ``jitter`` — the ``NebulaRetryJitter`` strategy (default `.full`).
/// - ``isRetriable`` — a `@Sendable` predicate deciding whether a thrown
///   error merits another attempt. The default retries transient transport
///   `URLError` codes and HTTP 5xx / 408 / 429 status errors (see
///   ``defaultIsRetriable``); non-retriable errors surface immediately.
public struct NebulaRetryPolicy: Sendable {

    /// Total attempts including the first. `1` = no retry. Minimum `1`.
    public let maxAttempts: Int
    /// The delay before the second attempt; scales by ``multiplier``.
    public let baseDelay: Duration
    /// The exponential backoff factor.
    public let multiplier: Double
    /// The cap applied to the computed delay (before jitter).
    public let maxDelay: Duration
    /// The jitter strategy.
    public let jitter: NebulaRetryJitter
    /// Decides whether a thrown error merits another attempt.
    public let isRetriable: @Sendable (any Error) -> Bool

    /// Creates a retry policy.
    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(200),
        multiplier: Double = 2.0,
        maxDelay: Duration = .seconds(30),
        jitter: NebulaRetryJitter = .full,
        isRetriable: @escaping @Sendable (any Error) -> Bool = NebulaRetryPolicy.defaultIsRetriable
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.jitter = jitter
        self.isRetriable = isRetriable
    }

    /// The default `isRetriable` predicate: retries transient transport
    /// `URLError` codes (`.timedOut`, `.cannotConnectToHost`,
    /// `.networkConnectionLost`, `.notConnectedToInternet`, `.dnsLookupFailed`,
    /// `.cannotFindHost`) and HTTP status codes `408`, `429`, `500`, `502`,
    /// `503`, `504` (surfaced by ``NebulaHTTPGateway`` as a
    /// ``NebulaHTTPStatusError``). Everything else (4xx other than 408/429,
    /// `.cancelled`, `.badURL`, …) surfaces immediately. Capture-free →
    /// trivially `Sendable`.
    public static let defaultIsRetriable: @Sendable (any Error) -> Bool = { error in
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        if let status = error as? NebulaHTTPStatusError {
            return [408, 429, 500, 502, 503, 504].contains(status.code)
        }
        return false
    }

    /// Computes the delay before the attempt after the `index`-th failure
    /// (`index` is 0-based: `0` is the delay before retrying the first failed
    /// attempt). `baseDelay * multiplier^index`, capped at `maxDelay`, then
    /// jittered.
    public func delay(forFailedAttempt index: Int) -> Duration {
        var d = baseDelay * pow(multiplier, Double(index))
        if maxDelay > .zero { d = min(d, maxDelay) }
        switch jitter {
        case .none:  return d
        case .full:  return d * Double.random(in: 0..<1)
        case .equal: return d * (0.5 + 0.5 * Double.random(in: 0..<1))
        }
    }

    // MARK: - Fluent builders

    /// Returns a copy with `maxAttempts` replaced.
    public func withMaxAttempts(_ maxAttempts: Int) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
    /// Returns a copy with `baseDelay` replaced.
    public func withBaseDelay(_ baseDelay: Duration) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
    /// Returns a copy with `multiplier` replaced.
    public func withMultiplier(_ multiplier: Double) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
    /// Returns a copy with `maxDelay` replaced.
    public func withMaxDelay(_ maxDelay: Duration) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
    /// Returns a copy with `jitter` replaced.
    public func withJitter(_ jitter: NebulaRetryJitter) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
    /// Returns a copy with the `isRetriable` predicate replaced.
    public func withIsRetriable(_ isRetriable: @escaping @Sendable (any Error) -> Bool) -> NebulaRetryPolicy {
        .init(maxAttempts: maxAttempts, baseDelay: baseDelay, multiplier: multiplier, maxDelay: maxDelay, jitter: jitter, isRetriable: isRetriable)
    }
}

/// A retry loop for `async throws` operations.
public enum NebulaRetry {

    /// The default sleeper: `try await Task.sleep(for: delay)`. Throws
    /// `CancellationError` if the task is cancelled mid-sleep (which propagates
    /// out of ``withPolicy(_:sleeper:operation:)`` and stops retrying).
    public static let defaultSleep: @Sendable (Duration) async throws -> Void = { delay in
        try await Task.sleep(for: delay)
    }

    /// Runs `operation`, retrying on errors for which `policy.isRetriable`
    /// returns `true`, up to `policy.maxAttempts` total attempts.
    ///
    /// - Honors cancellation: `Task.checkCancellation()` is checked before
    ///   each attempt, a thrown `CancellationError` is rethrown immediately
    ///   (never retried), and a cancellation during `sleeper` propagates out.
    /// - `sleeper` is injectable for tests (default ``defaultSleep``); pass an
    ///   instant sleeper to test the retry/counting logic without real delays.
    /// - A non-retriable error (per `policy.isRetriable`) is rethrown on the
    ///   first attempt; the error is the *original* error, not wrapped.
    public static func withPolicy<T>(
        _ policy: NebulaRetryPolicy,
        sleeper: @escaping @Sendable (Duration) async throws -> Void = NebulaRetry.defaultSleep,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !policy.isRetriable(error) { throw error }
                attempt += 1
                if attempt >= policy.maxAttempts { throw error }
                try await sleeper(policy.delay(forFailedAttempt: attempt - 1))
            }
        }
    }
}