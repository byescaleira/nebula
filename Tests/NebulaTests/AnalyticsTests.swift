//
//  AnalyticsTests.swift
//  NebulaTests
//
//  Wave N19b — CloudKit-backed observability suite. Tests for the Analytics
//  subsystem: NebulaAnalyticsEvent, the NebulaAnalytics port default
//  extensions (track/screen/identify), NebulaAnalyticsConfiguration (gating,
//  fluent builders, track entry), NebulaAnalyticsConfig accessor, and
//  NebulaLocalAnalytics façade.
//
//  Handler fan-out is captured in a `let Mutex<…>` (the MeasureTests precedent):
//  a `@Sendable` handler cannot mutate a captured `var`.
//

import Testing
import Foundation
import Synchronization
import Nebula

@Suite("NebulaAnalyticsEvent")
struct NebulaAnalyticsEventTests {
    @Test func storedFieldsAndDefaults() {
        let ts = Date()
        let e = NebulaAnalyticsEvent(name: "signup", properties: ["plan": .string("pro")], timestamp: ts)
        #expect(e.name == "signup")
        #expect(e.properties["plan"] == .string("pro"))
        #expect(e.timestamp == ts)
    }
    @Test func defaultsEmpty() {
        let e = NebulaAnalyticsEvent(name: "x")
        #expect(e.properties.isEmpty)
    }
}

@Suite("NebulaAnalytics port")
struct NebulaAnalyticsPortTests {
    @Test func defaultExtensionsBuildEvents() {
        let local = NebulaLocalAnalytics()
        local.track("tapped.cta")
        local.screen("Home")
        local.identify("user-42", properties: ["plan": .string("pro")])
        let events = local.events
        #expect(events.count == 3)
        #expect(events[0].name == "tapped.cta")
        #expect(events[1].name == "screen.Home")
        #expect(events[2].name == "identify")
        #expect(events[2].properties["userID"] == .string("user-42"))
        #expect(events[2].properties["plan"] == .string("pro"))
    }
    @Test func identifyCallerUserIDWinsOnCollision() {
        let local = NebulaLocalAnalytics()
        local.identify("real", properties: ["userID": .string("stale")])
        #expect(local.events[0].properties["userID"] == .string("real"))
    }
}

@Suite("NebulaAnalyticsConfiguration")
struct NebulaAnalyticsConfigurationTests {
    @Test func defaultIsEnabledNoOp() {
        NebulaAnalyticsConfiguration.default.track(.init(name: "x"))   // must not trap
    }
    @Test func disabledSkipsHandler() {
        let seen = Mutex<NebulaAnalyticsEvent?>(nil)
        let cfg = NebulaAnalyticsConfiguration.default.withEnabled(false).withHandler { ev in seen.withLock { $0 = ev } }
        cfg.track(.init(name: "x"))
        #expect(seen.withLock { $0 } == nil)
    }
    @Test func enabledInvokesHandler() {
        let seen = Mutex<NebulaAnalyticsEvent?>(nil)
        let cfg = NebulaAnalyticsConfiguration.default.withHandler { ev in seen.withLock { $0 = ev } }
        let e = NebulaAnalyticsEvent(name: "x")
        cfg.track(e)
        #expect(seen.withLock { $0 } == e)
    }
}

@Suite("NebulaAnalyticsConfig accessor")
struct NebulaAnalyticsConfigAccessorTests {
    @Test func getSetRoundTrip() {
        let saved = NebulaAnalyticsConfig.get()
        defer { NebulaAnalyticsConfig.set(saved) }
        NebulaAnalyticsConfig.set(.default.withEnabled(false))
        #expect(NebulaAnalyticsConfig.get().isEnabled == false)
    }
    @Test func trackDelegatesToCurrent() {
        let saved = NebulaAnalyticsConfig.get()
        defer { NebulaAnalyticsConfig.set(saved) }
        let seen = Mutex<NebulaAnalyticsEvent?>(nil)
        NebulaAnalyticsConfig.set(.default.withHandler { ev in seen.withLock { $0 = ev } })
        NebulaAnalyticsConfig.track(.init(name: "z"))
        #expect(seen.withLock { $0 }?.name == "z")
    }
}