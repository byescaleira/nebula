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