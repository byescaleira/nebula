//
//  ArchitectureBackgroundTaskTests.swift
//  NebulaTests
//
//  Wave N15b — tests for the background-task toolkit: the value types
// (``NebulaBackgroundTaskKind`` / ``NebulaBackgroundTaskRequest``), the
// Sendable launch-time handle (``NebulaBackgroundTask``), the
// ``NebulaBackgroundTaskConfiguration`` `@Sendable`-handler config + the
// process-wide ``NebulaBackgroundTaskConfig`` accessor, the
// ``NebulaBackgroundTaskScheduler`` port seam (a `FakeBackgroundTaskScheduler`
// final class conformer), ``NebulaBackgroundTaskError`` (the open-struct layer
// error), and the façade's SDK-mapping round-trip.
//
//  Testability constraint (larger than N15a): every `BackgroundTasks` SDK type
// (`BGTaskScheduler`, `BGTask`, `BGAppRefreshTaskRequest`,
// `BGProcessingTaskRequest`) is `API_UNAVAILABLE(macos)`. `swift test` runs on
// the **macOS host**, where NONE of them compile. So the all-5 value types /
// handle / config / port / error run on macOS; the façade and the
// `BGTaskRequest` mapping round-trip are gated `#if !os(macOS) && !os(watchOS)`
// — they **compile** on iOS/tvOS/visionOS (verified via `xcodebuild`) but are
// dead code on the macOS test host. `BGTaskScheduler.shared` is non-functional
// in a headless test bundle (no app context — the ``NebulaUNNotificationCenter``
// lesson), so the register/submit/cancel integration is NOT exercised here: the
// port seam + the type-level conformance check + the mapping round-trip prove
// the architecture; the SDK integration is a documented limitation. See
// vault/03-padroes/nebula-background-tasks.md.
//

import Testing
import Foundation
import Synchronization

@testable import Nebula

// MARK: - Fixtures

/// A ``NebulaBackgroundTaskScheduler`` conformer backed by an in-memory store,
/// proving the port is testable without the real `BGTaskScheduler.shared` (the
/// architecture-seam point — mirror `FakeNotificationCenter`).
private final class FakeBackgroundTaskScheduler: NebulaBackgroundTaskScheduler {
    private let mutex = Mutex<([String: NebulaBackgroundTaskRequest], [String])>(([:], []))

    func register(_ identifier: String) async -> Bool {
        mutex.withLock { $0.1.append(identifier); return true }
    }

    func submit(_ request: NebulaBackgroundTaskRequest) async throws {
        mutex.withLock { $0.0[request.identifier] = request }
    }

    func cancel(_ identifier: String) async {
        _ = mutex.withLock { $0.0.removeValue(forKey: identifier) }
    }

    func cancelAll() async {
        mutex.withLock { $0.0.removeAll() }
    }

    func pendingRequests() async -> [NebulaBackgroundTaskRequest] {
        mutex.withLock { Array($0.0.values) }
    }
}

// MARK: - Value types

@Suite("NebulaBackgroundTaskKind")
struct NebulaBackgroundTaskKindTests {
    @Test func caseIterableIsTwo() {
        #expect(NebulaBackgroundTaskKind.allCases == [.appRefresh, .processing])
    }
    @Test func equalityAndHashable() {
        #expect(NebulaBackgroundTaskKind.appRefresh != .processing)
        #expect(Set(NebulaBackgroundTaskKind.allCases).count == 2)
    }
    @Test func descriptionMirrorsCaseName() {
        #expect(NebulaBackgroundTaskKind.appRefresh.description == "appRefresh")
        #expect(NebulaBackgroundTaskKind.processing.description == "processing")
    }
}

@Suite("NebulaBackgroundTaskRequest")
struct NebulaBackgroundTaskRequestTests {
    @Test func appRefreshDefaults() {
        let r = NebulaBackgroundTaskRequest(identifier: "id", kind: .appRefresh)
        #expect(r.identifier == "id")
        #expect(r.kind == .appRefresh)
        #expect(r.earliestBeginDate == nil)
        #expect(r.requiresNetworkConnectivity == false)
        #expect(r.requiresExternalPower == false)
    }
    @Test func processingConditions() {
        let date = Date(timeIntervalSince1970: 1_000)
        let r = NebulaBackgroundTaskRequest(
            identifier: "proc", kind: .processing,
            earliestBeginDate: date,
            requiresNetworkConnectivity: true,
            requiresExternalPower: true
        )
        #expect(r.kind == .processing)
        #expect(r.earliestBeginDate == date)
        #expect(r.requiresNetworkConnectivity && r.requiresExternalPower)
    }
    @Test func equalityAndHashable() {
        let a = NebulaBackgroundTaskRequest(identifier: "id", kind: .appRefresh)
        let b = NebulaBackgroundTaskRequest(identifier: "id", kind: .appRefresh)
        #expect(a == b)
        #expect(a != NebulaBackgroundTaskRequest(identifier: "id", kind: .processing))
        #expect(a != NebulaBackgroundTaskRequest(identifier: "other", kind: .appRefresh))
        #expect(Set([a, b, NebulaBackgroundTaskRequest(identifier: "id", kind: .processing)]).count == 2)
    }
    @Test func sendsAcrossTask() async {
        let r = NebulaBackgroundTaskRequest(identifier: "id", kind: .processing, requiresExternalPower: true)
        let received = await Task { r }.value
        #expect(received == r)
    }
}

// MARK: - Sendable handle

@Suite("NebulaBackgroundTask handle")
struct NebulaBackgroundTaskHandleTests {
    @Test func completeAndOnExpirationInvokeClosures() {
        // Build a handle with mock closures (no façade) — proves the handle only
        // forwards to the closures it holds. The handle is all-5 because it
        // stores only Sendable closures; this runs on macOS.
        let finishCalls = Mutex<[Bool]>([])
        let expirationCalls = Mutex<[String]>([])
        let fired = Mutex<Bool>(false)
        let handle = NebulaBackgroundTask(
            identifier: "id",
            kind: .appRefresh,
            finish: { success in finishCalls.withLock { $0.append(success) } },
            setExpiration: { handler in expirationCalls.withLock { $0.append("set") }; handler() }
        )
        handle.complete(success: true)
        handle.complete(success: false)
        handle.onExpiration { fired.withLock { $0 = true } }
        #expect(finishCalls.withLock { $0 } == [true, false])
        #expect(fired.withLock { $0 } == true)
        #expect(expirationCalls.withLock { $0 } == ["set"])
    }
    @Test func equalityIsByIdentifierAndKind() {
        let a = NebulaBackgroundTask(
            identifier: "id", kind: .appRefresh,
            finish: { _ in }, setExpiration: { _ in }
        )
        let b = NebulaBackgroundTask(
            identifier: "id", kind: .appRefresh,
            finish: { success in print(success) }, setExpiration: { h in h() }
        )
        // Equal: same identifier + kind, even though the closures differ.
        #expect(a == b)
        #expect(a != NebulaBackgroundTask(
            identifier: "id", kind: .processing,
            finish: { _ in }, setExpiration: { _ in }
        ))
    }
    @Test func sendsAcrossTask() async {
        let handle = NebulaBackgroundTask(
            identifier: "id", kind: .appRefresh,
            finish: { _ in }, setExpiration: { _ in }
        )
        let received = await Task { handle }.value
        #expect(received.identifier == "id")
        #expect(received.kind == .appRefresh)
    }
}

// MARK: - Configuration

@Suite("NebulaBackgroundTaskConfiguration")
struct NebulaBackgroundTaskConfigurationTests {

    @Test func defaultHandlerIsCaptureFreeNoOp() {
        let config = NebulaBackgroundTaskConfiguration.default
        // The default launch is a no-op: handing it a handle does nothing.
        let handle = NebulaBackgroundTask(
            identifier: "id", kind: .appRefresh,
            finish: { _ in }, setExpiration: { _ in }
        )
        config.launch(handle)
    }

    @Test func withLaunchReturnsConcreteType() {
        let config = NebulaBackgroundTaskConfiguration.default
            .withLaunch { _ in }
        // Concrete type — assignable to NebulaBackgroundTaskConfiguration.
        let _: NebulaBackgroundTaskConfiguration = config
    }

    @Test func isSendableNotEquatable() async {
        // Sendable: crosses a Task boundary.
        let config = NebulaBackgroundTaskConfiguration.default
        let received = await Task { config }.value
        let handle = NebulaBackgroundTask(
            identifier: "id", kind: .appRefresh,
            finish: { _ in }, setExpiration: { _ in }
        )
        received.launch(handle)
        // NOT Equatable: the @Sendable closure is not comparable (compile-time
        // property — there is no `==` on NebulaBackgroundTaskConfiguration; the
        // absence of an `==` call here is the assertion).
    }

    @Test func sendsAcrossTask() async {
        let captured = Mutex<[NebulaBackgroundTask]>([])
        let config = NebulaBackgroundTaskConfiguration.default
            .withLaunch { task in captured.withLock { $0.append(task) } }
        let handle = NebulaBackgroundTask(
            identifier: "x", kind: .processing,
            finish: { _ in }, setExpiration: { _ in }
        )
        await Task { config.launch(handle) }.value
        #expect(captured.withLock { $0.count } == 1)
        #expect(captured.withLock { $0.first?.identifier } == "x")
        #expect(captured.withLock { $0.first?.kind } == .processing)
    }
}

@Suite("NebulaBackgroundTaskConfig accessor", .serialized)
struct NebulaBackgroundTaskConfigAccessorTests {

    @Test func getSetRoundTrip() {
        let original = NebulaBackgroundTaskConfig.get()
        defer { NebulaBackgroundTaskConfig.set(original) }
        let custom = NebulaBackgroundTaskConfiguration.default
            .withLaunch { _ in }
        NebulaBackgroundTaskConfig.set(custom)
        // The set config's launch is a distinct no-op closure (no observable
        // behavior beyond not crashing); verify it survives a get + invocation.
        let roundTripped = NebulaBackgroundTaskConfig.get()
        let handle = NebulaBackgroundTask(
            identifier: "i", kind: .appRefresh,
            finish: { _ in }, setExpiration: { _ in }
        )
        roundTripped.launch(handle)
    }
}

// MARK: - Port seam

@Suite("NebulaBackgroundTaskScheduler port")
struct NebulaBackgroundTaskSchedulerPortTests {

    @Test func fakeConformerSubmitsAndCancels() async throws {
        let scheduler: any NebulaBackgroundTaskScheduler = FakeBackgroundTaskScheduler()
        let registered = await scheduler.register("id-1")
        #expect(registered == true)
        try await scheduler.submit(NebulaBackgroundTaskRequest(identifier: "id-1", kind: .appRefresh))
        try await scheduler.submit(
            NebulaBackgroundTaskRequest(identifier: "proc", kind: .processing, requiresExternalPower: true)
        )
        let pending = await scheduler.pendingRequests()
        #expect(pending.count == 2)
        await scheduler.cancel("id-1")
        #expect(await scheduler.pendingRequests().count == 1)
        await scheduler.cancelAll()
        #expect(await scheduler.pendingRequests().isEmpty)
    }
}

// MARK: - Layer error

@Suite("NebulaBackgroundTaskError")
struct NebulaBackgroundTaskErrorTests {

    @Test func factoryStatics() {
        #expect(NebulaBackgroundTaskError.notPermitted().kind == .notPermitted)
        #expect(NebulaBackgroundTaskError.schedulingFailed().kind == .schedulingFailed)
        #expect(NebulaBackgroundTaskError.tooManyPending().kind == .tooManyPending)
        #expect(NebulaBackgroundTaskError.unavailable().kind == .unavailable)
        #expect(NebulaBackgroundTaskError.immediateRunIneligible().kind == .immediateRunIneligible)
        #expect(NebulaBackgroundTaskError.unknown().kind == .unknown)
    }

    @Test func coarseKindMapsSchedulingFailedToCocoa() {
        #expect(NebulaBackgroundTaskError.schedulingFailed().coarseKind == .cocoa)
        #expect(NebulaBackgroundTaskError.notPermitted().coarseKind == .unknown)
        #expect(NebulaBackgroundTaskError.tooManyPending().coarseKind == .unknown)
        #expect(NebulaBackgroundTaskError.unavailable().coarseKind == .unknown)
        #expect(NebulaBackgroundTaskError.immediateRunIneligible().coarseKind == .unknown)
        #expect(NebulaBackgroundTaskError.unknown().coarseKind == .unknown)
    }

    @Test func toNebulaErrorBridgesWithoutNewKind() {
        let err = NebulaBackgroundTaskError.schedulingFailed()
        let nebula = err.toNebulaError(kind: err.coarseKind)
        #expect(nebula.kind == .cocoa) // no new NebulaError.Kind case
        #expect(nebula.code.domain == "Nebula.NebulaBackgroundTaskError")
    }

    @Test func underlyingErrorIsPreserved() {
        let underlying = NebulaError.Box(NebulaError(error: NSError(domain: "x", code: 7)))
        let err = NebulaBackgroundTaskError.notPermitted(underlying: underlying)
        let nebula = err.toNebulaError(kind: err.coarseKind)
        #expect(nebula.underlying != nil)
    }

    @Test func equalityAndHashable() {
        let a = NebulaBackgroundTaskError.notPermitted()
        let b = NebulaBackgroundTaskError.notPermitted()
        #expect(a == b)
        #expect(a != NebulaBackgroundTaskError.unavailable())
        #expect(Set([a, b, NebulaBackgroundTaskError.unknown()]).count == 2)
    }

    @Test func kindIsStringLiteral() {
        let custom: NebulaBackgroundTaskError.Kind = "custom"
        #expect(NebulaBackgroundTaskError.Kind("custom") == custom)
        #expect(custom.description == "custom")
    }

    @Test func sendsAcrossTask() async {
        let err = NebulaBackgroundTaskError.unavailable()
        let received = await Task { err }.value
        #expect(received == err)
    }
}

// MARK: - Façade SDK mapping round-trip (no `BGTaskScheduler.shared`)
//
// `BGTaskScheduler.shared` is non-functional in a headless test bundle (no app
// context) and every `BackgroundTasks` SDK type is `API_UNAVAILABLE(macos)`. So
// the façade is NOT instantiated here; instead the pure mapping helpers
// (`makeBGRequest` / `makeNebulaRequest`, exposed `internal`) are round-tripped
// through constructible `BGAppRefreshTaskRequest` / `BGProcessingTaskRequest`.
// This covers the SDK-mapping logic without touching the shared singleton or
// the system-delivered `BGTask`. Gated `#if !os(macOS) && !os(watchOS)` — these
// compile on iOS/tvOS/visionOS (xcodebuild-verified) and are dead code on the
// macOS test host.

#if !os(macOS) && !os(watchOS)
import BackgroundTasks

@Suite("NebulaBGTaskScheduler SDK mapping")
struct NebulaBGTaskSchedulerMappingTests {

    @Test func appRefreshRoundTrip() {
        let nebula = NebulaBackgroundTaskRequest(
            identifier: "refresh",
            kind: .appRefresh,
            earliestBeginDate: Date(timeIntervalSince1970: 1_000)
        )
        let bg = NebulaBGTaskScheduler.makeBGRequest(nebula)
        #expect(bg.identifier == "refresh")
        #expect(bg.earliestBeginDate == Date(timeIntervalSince1970: 1_000))
        // appRefresh → BGAppRefreshTaskRequest (not the processing subclass).
        #expect(bg is BGAppRefreshTaskRequest)
        #expect(!(bg is BGProcessingTaskRequest))

        let back = NebulaBGTaskScheduler.makeNebulaRequest(bg)
        #expect(back.identifier == "refresh")
        #expect(back.kind == .appRefresh)
        #expect(back.earliestBeginDate == Date(timeIntervalSince1970: 1_000))
        // App-refresh conditions stay at their defaults.
        #expect(back.requiresNetworkConnectivity == false)
        #expect(back.requiresExternalPower == false)
    }

    @Test func processingRoundTripCarriesConditions() {
        let nebula = NebulaBackgroundTaskRequest(
            identifier: "proc",
            kind: .processing,
            earliestBeginDate: Date(timeIntervalSince1970: 2_000),
            requiresNetworkConnectivity: true,
            requiresExternalPower: true
        )
        let bg = NebulaBGTaskScheduler.makeBGRequest(nebula)
        #expect(bg is BGProcessingTaskRequest)
        let processing = bg as! BGProcessingTaskRequest
        #expect(processing.requiresNetworkConnectivity == true)
        #expect(processing.requiresExternalPower == true)

        let back = NebulaBGTaskScheduler.makeNebulaRequest(bg)
        #expect(back.kind == .processing)
        #expect(back.requiresNetworkConnectivity == true)
        #expect(back.requiresExternalPower == true)
        #expect(back.earliestBeginDate == Date(timeIntervalSince1970: 2_000))
    }

    @Test func facadeIsAPortConformer() {
        // Type-level conformance WITHOUT instantiating the façade (its
        // register/submit touch `BGTaskScheduler.shared`, which is non-functional
        // in a headless test bundle). Assignable to
        // `any NebulaBackgroundTaskScheduler.Type` proves the conformance.
        let schedulerType: any NebulaBackgroundTaskScheduler.Type = NebulaBGTaskScheduler.self
        #expect(schedulerType is NebulaBGTaskScheduler.Type)
    }
}

#endif