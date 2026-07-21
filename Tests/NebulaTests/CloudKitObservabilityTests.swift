//
//  CloudKitObservabilityTests.swift
//  NebulaTests
//
//  Wave N19c/e — CloudKit-backed observability suite. Tests for the CloudKit
//  glue: NebulaCloudKitEnvironment, NebulaCloudKitConfiguration (fluent
//  builders, defaults, Equatable), NebulaCloudKitConfig accessor, and the
//  NebulaCloudKitSync port (exercised via a fake conformer — the real
//  NebulaCloudKitSyncEngine wraps CKSyncEngine, which requires an iCloud
//  entitlement + container at runtime and so is app-owned/manual-verified,
//  the MeridianExample precedent). Plus NebulaPerformanceSink routing.
//

import Testing
import Foundation
import Synchronization
import Nebula

@Suite("NebulaCloudKitConfiguration")
struct NebulaCloudKitConfigurationTests {
    @Test func defaults() {
        let c = NebulaCloudKitConfiguration.default
        #expect(c.containerIdentifier == nil)
        #expect(c.environment == .private)
        #expect(c.zoneName == "NebulaObservability")
        #expect(c.isEnabled == false)
    }
    @Test func buildersCopyVerbatim() {
        let c = NebulaCloudKitConfiguration.default
            .withContainerIdentifier("iCloud.com.example.app")
            .withEnvironment(.public)
            .withZoneName("Telemetry")
            .withEnabled(true)
        #expect(c.containerIdentifier == "iCloud.com.example.app")
        #expect(c.environment == .public)
        #expect(c.zoneName == "Telemetry")
        #expect(c.isEnabled == true)
    }
    @Test func equatable() {
        #expect(NebulaCloudKitConfiguration.default == .default)
        #expect(NebulaCloudKitConfiguration.default != .default.withEnabled(true))
        #expect(NebulaCloudKitEnvironment.private == .private)
        #expect(NebulaCloudKitEnvironment.private != .shared)
    }
}

@Suite("NebulaCloudKitConfig accessor")
struct NebulaCloudKitConfigAccessorTests {
    @Test func getSetRoundTrip() {
        let saved = NebulaCloudKitConfig.get()
        defer { NebulaCloudKitConfig.set(saved) }
        NebulaCloudKitConfig.set(.default.withEnabled(true).withZoneName("X"))
        let c = NebulaCloudKitConfig.get()
        #expect(c.isEnabled == true)
        #expect(c.zoneName == "X")
    }
}

/// A fake `NebulaCloudKitSync` conformer for port tests (no CloudKit I/O).
private final class FakeCloudKitSync: NebulaCloudKitSync, @unchecked Sendable {
    let sends = Mutex(0)
    let fetches = Mutex(0)
    var fail = false
    func sendChanges() async throws {
        if fail { throw NSError(domain: "x", code: 1) }
        sends.withLock { $0 += 1 }
    }
    func fetchChanges() async throws {
        if fail { throw NSError(domain: "x", code: 1) }
        fetches.withLock { $0 += 1 }
    }
}

@Suite("NebulaCloudKitSync port")
struct NebulaCloudKitSyncPortTests {
    @Test func fakeConformsAndCounts() async throws {
        let sync = FakeCloudKitSync()
        try await sync.sendChanges()
        try await sync.fetchChanges()
        #expect(sync.sends.withLock { $0 } == 1)
        #expect(sync.fetches.withLock { $0 } == 1)
    }
    @Test func propagatesThrow() async {
        let sync = FakeCloudKitSync()
        sync.fail = true
        await #expect(throws: NSError.self) { try await sync.sendChanges() }
    }
    @Test func syncErgonomicRunsSendThenFetch() async throws {
        let sync = FakeCloudKitSync()
        try await sync.sync()
        #expect(sync.sends.withLock { $0 } == 1)
        #expect(sync.fetches.withLock { $0 } == 1)
    }
    @Test func syncSurfacesSendFailureBeforeFetch() async {
        let sync = FakeCloudKitSync()
        sync.fail = true
        await #expect(throws: NSError.self) { try await sync.sync() }
        // sendChanges() threw, so fetchChanges() must NOT have run.
        #expect(sync.fetches.withLock { $0 } == 0)
    }
}

@Suite("NebulaCloudKitPreferences")
struct NebulaCloudKitPreferencesTests {

    /// Polls `predicate` until it holds or a bounded retry budget is exhausted
    /// (the conformer flushes via a fire-and-forget `Task.detached`, so the sink
    /// is invoked off the calling thread).
    private func awaitUntil(_ expected: Int, _ read: () -> Int) async {
        for _ in 0..<200 {
            if read() == expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(read() == expected, "await timed out")
    }

    @Test func cacheRoundTripIsSynchronous() {
        let prefs = NebulaCloudKitPreferences(sink: { _ in })   // no-op sink
        #expect(prefs.data(forKey: "x") == nil)
        prefs.setData(Data([1, 2, 3]), forKey: "x")
        #expect(prefs.data(forKey: "x") == Data([1, 2, 3]))
        prefs.remove(forKey: "x")
        #expect(prefs.data(forKey: "x") == nil)
    }

    @Test func setDataNilRemovesAndEmitsRemoveChange() async {
        let recorded = Mutex<[NebulaCloudKitKVChange]>([])
        let prefs = NebulaCloudKitPreferences(sink: { change in recorded.withLock { $0.append(change) } })
        prefs.setData(Data([9]), forKey: "k")
        prefs.setData(nil, forKey: "k")
        await awaitUntil(2) { recorded.withLock { $0.count } }
        let changes = recorded.withLock { $0 }
        #expect(changes.count == 2)
        #expect(changes[0] == .init(key: "k", op: .set(Data([9]))))
        #expect(changes[1] == .init(key: "k", op: .remove))
        #expect(prefs.data(forKey: "k") == nil)
    }

    @Test func codableBridgeRoundTripsThroughCache() throws {
        struct Settings: Codable, Equatable { let theme: String; let volume: Int }
        let prefs = NebulaCloudKitPreferences(sink: { _ in })
        try prefs.setValue(Settings(theme: "dark", volume: 7), forKey: "settings")
        let got: Settings? = try prefs.value(Settings.self, forKey: "settings")
        #expect(got == Settings(theme: "dark", volume: 7))
        try prefs.setValue(Settings?.none, forKey: "settings")
        #expect((try prefs.value(Settings.self, forKey: "settings")) == nil)
    }

    @Test func disabledConfigUsesNoOpDefaultSinkButCacheStillWorks() {
        // Disabled default config → defaultSink is a no-op (no CloudKit hit in
        // the test process). The cache is the synchronous source of truth.
        let prefs = NebulaCloudKitConfiguration.default  // isEnabled == false
        let store = NebulaCloudKitPreferences(prefs)
        store.setData(Data([0xAB]), forKey: "k")
        #expect(store.data(forKey: "k") == Data([0xAB]))
    }

    @Test func kvChangeEquality() {
        #expect(NebulaCloudKitKVChange(key: "k", op: .set(Data([1]))) == .init(key: "k", op: .set(Data([1]))))
        #expect(NebulaCloudKitKVChange(key: "k", op: .set(Data([1]))) != .init(key: "k", op: .remove))
        #expect(NebulaCloudKitKVChange(key: "a", op: .remove) != .init(key: "b", op: .remove))
    }
}

@Suite("NebulaPerformanceSink")
struct NebulaPerformanceSinkTests {
    @Test func defaultMappingRoutesTimingIntoMetrics() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let metrics = NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        let handler = NebulaPerformanceSink.handler(via: metrics, prefix: "boot")
        // 4 iterations totaling 2s → perIteration = 500ms = 0.5s.
        let result = NebulaMeasureResult(name: "launch", iterations: 4, total: .seconds(2))
        handler(result)
        let got = seen.withLock { $0 }
        #expect(got?.name == "boot.launch")
        #expect(got?.kind == .timing)
        #expect(abs((got?.value ?? -1) - 0.5) < 0.0001)
        #expect(got?.attributes["iterations"] == .int(4))
    }
    @Test func noPrefixKeepsName() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let metrics = NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        NebulaPerformanceSink.handler(via: metrics)(
            NebulaMeasureResult(name: "x", iterations: 1, total: .milliseconds(100)))
        let got = seen.withLock { $0 }
        #expect(got?.name == "x")
        #expect(abs((got?.value ?? -1) - 0.1) < 0.0001)
    }
    @Test func customMapping() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let metrics = NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        let handler = NebulaPerformanceSink.handler(via: metrics) { r in
            NebulaMetricEvent(name: r.name, kind: .histogram, value: Double(r.iterations), attributes: [:])
        }
        handler(NebulaMeasureResult(name: "h", iterations: 7, total: .seconds(1)))
        let got = seen.withLock { $0 }
        #expect(got?.kind == .histogram)
        #expect(got?.value == 7)
    }
    @Test func disabledMetricsSwallows() {
        let ran = Mutex(false)
        let metrics = NebulaMetricsConfiguration.default.withEnabled(false).withHandler { _ in
            ran.withLock { $0 = true }
        }
        NebulaPerformanceSink.handler(via: metrics)(
            NebulaMeasureResult(name: "x", iterations: 1, total: .seconds(1)))
        #expect(ran.withLock { $0 } == false)
    }
}