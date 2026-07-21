//
//  MetricsTests.swift
//  NebulaTests
//
//  Wave N19a — CloudKit-backed observability suite. Tests for the Metrics
//  subsystem: NebulaMetricValue, NebulaMetricEvent, NebulaEventBuffer (flush
//  on batchSize + manual), the NebulaMetrics port default extensions,
//  NebulaMetricsConfiguration (gating, fluent builders, record entry),
//  NebulaMetricsConfig process-wide accessor, and NebulaLocalMetrics façade.
//
//  Handler fan-out is captured in a `let Mutex<…>` (the MeasureTests precedent):
//  a `@Sendable` handler cannot mutate a captured `var`, so single-event
//  captures use `Mutex<NebulaMetricEvent?>`.
//

import Testing
import Foundation
import Synchronization
import Nebula

@Suite("NebulaMetricValue")
struct NebulaMetricValueTests {
    @Test func equalityAndHashable() {
        #expect(NebulaMetricValue.bool(true) == .bool(true))
        #expect(NebulaMetricValue.string("x") == .string("x"))
        #expect(NebulaMetricValue.int(3) == .int(3))
        #expect(NebulaMetricValue.double(1.5) == .double(1.5))
        #expect(NebulaMetricValue.json(Data([0x01])) == .json(Data([0x01])))
        #expect(NebulaMetricValue.int(1) != .double(1))
    }
    @Test func descriptionShape() {
        #expect(NebulaMetricValue.bool(true).description == "NebulaMetricValue.bool(true)")
        #expect(NebulaMetricValue.string("hi").description == "NebulaMetricValue.string(hi)")
        #expect(NebulaMetricValue.json(Data([0,1,2])).description == "NebulaMetricValue.json(3 bytes)")
    }
}

@Suite("NebulaMetricEvent")
struct NebulaMetricEventTests {
    @Test func storedFieldsAndDefaults() {
        let ts = Date()
        let e = NebulaMetricEvent(name: "req.lat", kind: .timing, value: 0.25, timestamp: ts, attributes: ["code": .int(200)])
        #expect(e.name == "req.lat")
        #expect(e.kind == .timing)
        #expect(e.value == 0.25)
        #expect(e.timestamp == ts)
        #expect(e.attributes["code"] == .int(200))
    }
    @Test func defaultTimestampAndAttributes() {
        let e = NebulaMetricEvent(name: "n", kind: .counter, value: 1)
        #expect(e.attributes.isEmpty)
        let e2 = NebulaMetricEvent(name: "n", kind: .counter, value: 1)
        #expect(e.timestamp <= e2.timestamp)
    }
}

@Suite("NebulaEventBuffer")
struct NebulaEventBufferTests {
    @Test func flushOnBatchSize() {
        let box = Mutex<[[NebulaMetricEvent]]>([])
        let buf = NebulaEventBuffer<NebulaMetricEvent>(batchSize: 3) { batch in
            box.withLock { $0.append(batch) } }
        for i in 0..<3 {
            buf.append(.init(name: "n", kind: .counter, value: Double(i)))
        }
        let flushed = box.withLock { $0 }
        #expect(flushed.count == 1)
        #expect(flushed[0].count == 3)
        #expect(flushed[0][2].value == 2)
    }
    @Test func manualFlush() {
        let box = Mutex<[[NebulaMetricEvent]]>([])
        let buf = NebulaEventBuffer<NebulaMetricEvent>(batchSize: 100) { batch in
            box.withLock { $0.append(batch) } }
        buf.append(.init(name: "n", kind: .counter, value: 1))
        buf.append(.init(name: "n", kind: .counter, value: 2))
        #expect(box.withLock { $0 }.count == 0)
        buf.flush()
        let flushed = box.withLock { $0 }
        #expect(flushed.count == 1)
        #expect(flushed[0].count == 2)
    }
    @Test func flushResetsPending() {
        let box = Mutex<[Int]>([])
        let buf = NebulaEventBuffer<Int>(batchSize: 2) { batch in box.withLock { $0.append(batch.count) } }
        buf.append(1); buf.append(2)   // auto-flush [1,2] → count 2; pending reset to []
        buf.append(3)
        buf.flush()                     // flush [3] → count 1 (proves 3 was NOT merged with 1,2)
        let counts = box.withLock { $0 }
        #expect(counts == [2, 1])
    }
    @Test func emptyFlushIsNoOp() {
        let box = Mutex<[Int]>([])
        let buf = NebulaEventBuffer<Int>(batchSize: 10) { batch in box.withLock { $0.append(batch.count) } }
        buf.flush()   // empty pending → handler NOT called
        #expect(box.withLock { $0 }.isEmpty)
    }
}

@Suite("NebulaMetrics port")
struct NebulaMetricsPortTests {
    @Test func defaultExtensionsBuildEvents() {
        let local = NebulaLocalMetrics()
        local.increment("reqs")
        local.increment("reqs", by: 4)
        local.observe("size", value: 1024)
        local.gauge("depth", value: 7)
        local.timing("lat", duration: .milliseconds(250))
        let events = local.events
        #expect(events.count == 5)
        #expect(events[0].name == "reqs"); #expect(events[0].kind == .counter); #expect(events[0].value == 1)
        #expect(events[1].value == 4)
        #expect(events[2].kind == .histogram); #expect(events[2].value == 1024)
        #expect(events[3].kind == .gauge); #expect(events[3].value == 7)
        #expect(events[4].kind == .timing)
        #expect(abs(events[4].value - 0.25) < 0.0001)
    }
    @Test func localMetricsSnapshotsAndClears() {
        let local = NebulaLocalMetrics()
        local.increment("a")
        #expect(local.events.count == 1)
        local.removeAll()
        #expect(local.events.isEmpty)
    }
}

@Suite("NebulaMetricsConfiguration")
struct NebulaMetricsConfigurationTests {
    @Test func defaultIsEnabledWithNoOpHandler() {
        let cfg = NebulaMetricsConfiguration.default
        #expect(cfg.isEnabled)
        cfg.record(.init(name: "x", kind: .counter, value: 1))
    }
    @Test func disabledSkipsHandler() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let cfg = NebulaMetricsConfiguration.default
            .withEnabled(false)
            .withHandler { ev in seen.withLock { $0 = ev } }
        cfg.record(.init(name: "x", kind: .counter, value: 1))
        #expect(seen.withLock { $0 } == nil)
    }
    @Test func enabledInvokesHandler() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let cfg = NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        let e = NebulaMetricEvent(name: "x", kind: .gauge, value: 9)
        cfg.record(e)
        #expect(seen.withLock { $0 } == e)
    }
    @Test func buildersCopyVerbatim() {
        let cfg = NebulaMetricsConfiguration.default.withHandler { _ in }
        #expect(cfg.withEnabled(false).isEnabled == false)
        #expect(cfg.withEnabled(true).isEnabled == true)
    }
    @Test func recordConvenienceBuildsEvent() {
        let seen = Mutex<NebulaMetricEvent?>(nil)
        let cfg = NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        cfg.record("reqs", kind: .counter, value: 3, attributes: ["code": .int(200)])
        let got = seen.withLock { $0 }
        #expect(got?.name == "reqs")
        #expect(got?.kind == .counter)
        #expect(got?.value == 3)
        #expect(got?.attributes["code"] == .int(200))
    }
}

@Suite("NebulaMetricsConfig accessor")
struct NebulaMetricsConfigAccessorTests {
    @Test func getSetRoundTrip() {
        let saved = NebulaMetricsConfig.get()
        defer { NebulaMetricsConfig.set(saved) }
        let cfg = NebulaMetricsConfiguration.default.withEnabled(false)
        NebulaMetricsConfig.set(cfg)
        #expect(NebulaMetricsConfig.get().isEnabled == false)
    }
    @Test func recordDelegatesToCurrent() {
        let saved = NebulaMetricsConfig.get()
        defer { NebulaMetricsConfig.set(saved) }
        let seen = Mutex<NebulaMetricEvent?>(nil)
        NebulaMetricsConfig.set(NebulaMetricsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } })
        NebulaMetricsConfig.record(.init(name: "z", kind: .counter, value: 1))
        #expect(seen.withLock { $0 }?.name == "z")
    }
}