//
//  MeasureTests.swift
//  NebulaTests
//
//  Wave F (measure half) — NebulaMeasureConfiguration timing + signpost
//  subsystem tests (Swift Testing). Covers measure sync/async/rethrows, bench
//  (warmup + handler fan-out), fluent builders, signposter integration,
//  SuspendingClock variant, the process-wide NebulaMeasureConfig accessor,
//  and Sendable conformance.
//

import Testing
import Foundation
import os
import Synchronization
import Nebula

// MARK: - Test fixtures

/// A throw-only marker error used to verify `measure`/`bench` rethrow
/// propagation. Never trap the process with `preconditionFailure`/`fatalError`.
private struct Boom: Error, Equatable {}

@Suite("NebulaMeasureResult")
struct NebulaMeasureResultTests {
    @Test func storedFieldsRoundTrip() {
        let r = NebulaMeasureResult(name: "loop", iterations: 100, total: .seconds(2))
        #expect(r.name == "loop")
        #expect(r.iterations == 100)
        #expect(r.total == .seconds(2))
    }

    @Test func perIterationDividesTotalByIterations() {
        let r = NebulaMeasureResult(name: "loop", iterations: 4, total: .seconds(2))
        #expect(r.perIteration == .milliseconds(500))
    }

    @Test func componentsDecomposesTotal() {
        let r = NebulaMeasureResult(name: "loop", iterations: 1, total: .seconds(3))
        let c = r.components
        #expect(c.seconds == 3)
        #expect(c.attoseconds == 0)
    }

    @Test func equatableComparesStoredFieldsOnly() {
        let a = NebulaMeasureResult(name: "x", iterations: 2, total: .seconds(1))
        let b = NebulaMeasureResult(name: "x", iterations: 2, total: .seconds(1))
        let c = NebulaMeasureResult(name: "x", iterations: 4, total: .seconds(1))
        #expect(a == b)
        #expect(a != c)
    }

    @Test func sendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaMeasureResult(name: "x", iterations: 1, total: .seconds(1)))
    }
}

@Suite("NebulaMeasureConfiguration.measure")
struct NebulaMeasureConfigurationMeasureTests {
    @Test func measureSyncReturnsValueAndDuration() {
        let (v, d) = NebulaMeasureConfiguration.default.measure("compute") { 42 }
        #expect(v == 42)
        #expect(d >= .zero)
    }

    @Test func measureAsyncReturnsValueAndDuration() async {
        let cfg = NebulaMeasureConfiguration.default
        let (v, d) = await cfg.measure("compute") { await Task { 7 }.value }
        #expect(v == 7)
        #expect(d >= .zero)
    }

    @Test func measureSyncRethrows() throws {
        let cfg = NebulaMeasureConfiguration.default
        #expect(throws: Boom.self) {
            try cfg.measure("x") { throw Boom() }
        }
    }

    @Test func measureAsyncRethrows() async {
        let cfg = NebulaMeasureConfiguration.default
        // Force the ASYNC `measure` overload with an explicitly
        // `() async throws -> Void` closure so `try await` is genuinely
        // required (a plain `{ throw Boom() }` resolves to the sync overload
        // and makes `await` an unnecessary-effect-marker warning).
        await #expect(throws: Boom.self) {
            try await cfg.measure("x") { () async throws -> Void in throw Boom() }
        }
    }

    @Test func measureWithSignposterDoesNotCrash() {
        let cfg = NebulaMeasureConfiguration(
            signposter: NebulaSignposter(subsystem: "test.nebula.measure")
        )
        let (v, d) = cfg.measure("compute") { 99 }
        #expect(v == 99)
        #expect(d >= .zero)
    }

    @Test func measureAsyncWithSignposterDoesNotCrash() async {
        let cfg = NebulaMeasureConfiguration(
            signposter: NebulaSignposter(subsystem: "test.nebula.measure")
        )
        let (v, d) = await cfg.measure("compute") { await Task { 5 }.value }
        #expect(v == 5)
        #expect(d >= .zero)
    }

    @Test func measureTimingRunsEvenWhenDisabled() {
        // `isEnabled` gates the handler fan-out and signpost emission, NOT the
        // timing — the returned Duration must still be meaningful.
        let cfg = NebulaMeasureConfiguration.default.withEnabled(false)
        let (v, d) = cfg.measure("compute") { 17 }
        #expect(v == 17)
        #expect(d >= .zero)
    }

    @Test func measureWithSuspendingClockDoesNotCrash() {
        let cfg = NebulaMeasureConfiguration(clock: SuspendingClock())
        let (v, d) = cfg.measure("compute") { 3 }
        #expect(v == 3)
        #expect(d >= .zero)
    }
}

@Suite("NebulaMeasureConfiguration.bench")
struct NebulaMeasureConfigurationBenchTests {
    @Test func benchReturnsResultWithExpectedFields() {
        let cfg = NebulaMeasureConfiguration.default
        let r = cfg.bench("loop", iterations: 100) { _ = 1 + 1 }
        #expect(r.name == "loop")
        #expect(r.iterations == 100)
        #expect(r.total >= .zero)
        #expect(r.perIteration >= .zero)
    }

    @Test func benchDefaultIterations() {
        let cfg = NebulaMeasureConfiguration.default
        let r = cfg.bench("loop") { _ = 1 + 1 }
        #expect(r.iterations == 10)
    }

    @Test func benchHandlerInvokedWhenEnabled() {
        let captured = Mutex<[NebulaMeasureResult]>([])
        let cfg = NebulaMeasureConfiguration(handler: { result in captured.withLock { $0.append(result) } })
        _ = cfg.bench("loop", iterations: 5) { _ = 1 + 1 }
        let results = captured.withLock { $0 }
        #expect(results.count == 1)
        #expect(results.first?.iterations == 5)
    }

    @Test func benchHandlerNotInvokedWhenDisabled() {
        let captured = Mutex<[NebulaMeasureResult]>([])
        let cfg = NebulaMeasureConfiguration(
            isEnabled: false,
            handler: { result in captured.withLock { $0.append(result) } }
        )
        _ = cfg.bench("loop", iterations: 5) { _ = 1 + 1 }
        let results = captured.withLock { $0 }
        #expect(results.isEmpty)
    }

    @Test func benchWarmupRunsBeforeTiming() {
        // The operation runs `warmup + iterations` times total; assert the
        // counter equals that sum to prove warmup executes (and is not just
        // skipped) while remaining untimed.
        let counter = Mutex(0)
        let cfg = NebulaMeasureConfiguration.default
        _ = cfg.bench("loop", iterations: 10, warmup: 3) {
            counter.withLock { $0 += 1 }
        }
        #expect(counter.withLock { $0 } == 13)
    }

    @Test func benchRethrows() {
        let cfg = NebulaMeasureConfiguration.default
        #expect(throws: Boom.self) {
            try cfg.bench("loop", iterations: 2) { throw Boom() }
        }
    }

    @Test func benchWithSignposterDoesNotCrash() {
        let cfg = NebulaMeasureConfiguration(
            signposter: NebulaSignposter(subsystem: "test.nebula.measure")
        )
        let r = cfg.bench("loop", iterations: 5) { _ = 1 + 1 }
        #expect(r.iterations == 5)
        #expect(r.total >= .zero)
    }
}

@Suite("NebulaMeasureConfiguration fluent builders")
struct NebulaMeasureConfigurationBuilderTests {
    @Test func withClockReplacesClockOnly() {
        let suspending = SuspendingClock()
        let cfg = NebulaMeasureConfiguration.default.withClock(suspending)
        // `any Clock<Duration>` is an existential — identity comparison is not
        // available, so assert the configuration is still constructed and the
        // other fields are unchanged by re-deriving.
        #expect(cfg.isEnabled == NebulaMeasureConfiguration.default.isEnabled)
        #expect(cfg.signposter == nil)
    }

    @Test func withSignposterReplacesSignposterOnly() {
        let sp = NebulaSignposter(subsystem: "test.nebula.measure")
        let cfg = NebulaMeasureConfiguration.default.withSignposter(sp)
        #expect(cfg.signposter != nil)
        #expect(cfg.isEnabled == NebulaMeasureConfiguration.default.isEnabled)
        // Signposter stays nil on the default — opt-in only.
        #expect(NebulaMeasureConfiguration.default.signposter == nil)
    }

    @Test func withSignposterCanClear() {
        let sp = NebulaSignposter(subsystem: "test.nebula.measure")
        let cfg = NebulaMeasureConfiguration(signposter: sp).withSignposter(nil)
        #expect(cfg.signposter == nil)
    }

    @Test func withEnabledReplacesFlagOnly() {
        let cfg = NebulaMeasureConfiguration.default.withEnabled(false)
        #expect(cfg.isEnabled == false)
        // `NebulaSignposter` is NOT Equatable (it stores an `os.OSSignposter`),
        // so compare the Optional via nil checks rather than `==`.
        #expect(cfg.signposter == nil)
        #expect(NebulaMeasureConfiguration.default.signposter == nil)
    }

    @Test func withHandlerReplacesHandlerOnly() {
        let captured = Mutex(0)
        let cfg = NebulaMeasureConfiguration.default.withHandler { _ in
            captured.withLock { $0 += 1 }
        }
        _ = cfg.bench("loop") { _ = 1 + 1 }
        #expect(captured.withLock { $0 } == 1)
    }
}

@Suite("NebulaMeasureConfig process-wide accessor")
struct NebulaMeasureConfigTests {
    @Test func getReturnsDefaultBeforeAnySet() {
        // Restore in case another test in this process set state.
        defer { NebulaMeasureConfig.set(.default) }
        NebulaMeasureConfig.set(.default)
        let cfg = NebulaMeasureConfig.get()
        #expect(cfg.isEnabled == true)
        #expect(cfg.signposter == nil)
    }

    @Test func setReplacesCurrentConfiguration() {
        defer { NebulaMeasureConfig.set(.default) }
        let captured = Mutex<[NebulaMeasureResult]>([])
        let custom = NebulaMeasureConfiguration(
            isEnabled: true,
            handler: { result in captured.withLock { $0.append(result) } }
        )
        NebulaMeasureConfig.set(custom)
        let retrieved = NebulaMeasureConfig.get()
        #expect(retrieved.isEnabled == true)
        // Confirm the handler is wired by exercising the current config.
        _ = NebulaMeasureConfig.get().bench("loop", iterations: 2) { _ = 1 + 1 }
        #expect(captured.withLock { $0 }.count == 1)
    }
}

@Suite("NebulaMeasureConfiguration Sendable")
struct NebulaMeasureConfigurationSendableTests {
    @Test func configurationIsSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaMeasureConfiguration.default)
        consume(NebulaMeasureConfiguration(
            signposter: NebulaSignposter(subsystem: "test.nebula.measure")
        ))
    }
}