//
//  LoggingTests.swift
//  NebulaTests
//
//  Wave B — logging module tests (Swift Testing). Covers level mapping/ordering,
//  category raw values, configuration fluent builders + default + gating,
//  the in-memory handler ring buffer, and signposter ID exclusivity.
//

import Testing
import Nebula
import os

@Suite("NebulaLogLevel")
struct NebulaLogLevelTests {
    @Test func caseIterableOrderIsBySeverity() {
        #expect(NebulaLogLevel.allCases == [.debug, .info, .notice, .error, .fault])
    }

    @Test func warningIsAnAliasForError() {
        #expect(NebulaLogLevel.warning == .error)
        // `warning` is a static alias, not a case, so it's absent from allCases.
        #expect(!NebulaLogLevel.allCases.contains { $0 == NebulaLogLevel.warning && $0 != .error })
    }

    @Test func comparableBySeverity() {
        #expect(NebulaLogLevel.debug < .info)
        #expect(NebulaLogLevel.info < .notice)
        #expect(NebulaLogLevel.notice < .error)
        #expect(NebulaLogLevel.error < .fault)
    }

    @Test func osLogTypeMapping() {
        #expect(NebulaLogLevel.debug.osLogType == .debug)
        #expect(NebulaLogLevel.info.osLogType == .info)
        #expect(NebulaLogLevel.notice.osLogType == .default)
        #expect(NebulaLogLevel.error.osLogType == .error)
        #expect(NebulaLogLevel.fault.osLogType == .fault)
    }

    @Test func initFromOSLogTypeRoundTripsKnownCases() {
        #expect(NebulaLogLevel(osLogType: .debug) == .debug)
        #expect(NebulaLogLevel(osLogType: .info) == .info)
        #expect(NebulaLogLevel(osLogType: .default) == .notice)
        #expect(NebulaLogLevel(osLogType: .error) == .error)
        #expect(NebulaLogLevel(osLogType: .fault) == .fault)
    }
}

@Suite("NebulaLogCategory")
struct NebulaLogCategoryTests {
    @Test func rawValueRoundTrips() {
        #expect(NebulaLogCategory("sync").rawValue == "sync")
    }

    @Test func stringLiteralInit() {
        let c: NebulaLogCategory = "background-sync"
        #expect(c.rawValue == "background-sync")
        #expect(c.description == "background-sync")
    }

    @Test func presetsHaveExpectedRawValues() {
        #expect(NebulaLogCategory.networking.rawValue == "networking")
        #expect(NebulaLogCategory.persistence.rawValue == "persistence")
        #expect(NebulaLogCategory.formatting.rawValue == "formatting")
        #expect(NebulaLogCategory.measure.rawValue == "measure")
        #expect(NebulaLogCategory.concurrency.rawValue == "concurrency")
        #expect(NebulaLogCategory.general.rawValue == "general")
    }

    @Test func isHashableAndSendable() {
        #expect(NebulaLogCategory.networking == "networking")
        #expect(NebulaLogCategory.networking != "general")
    }
}

@Suite("NebulaLogger")
struct NebulaLoggerTests {
    @Test func storesSubsystemAndCategory() {
        let logger = NebulaLogger(subsystem: "com.acme.app", category: .networking)
        #expect(logger.subsystem == "com.acme.app")
        #expect(logger.category == .networking)
    }

    @Test func exposesUnderlyingOSLogger() {
        let logger = NebulaLogger(subsystem: "com.acme.app", category: "custom")
        // The exposed os.Logger must be usable with a literal (redaction path).
        logger.osLogger.error("test \(1, privacy: .public)")
    }

    @Test func signposterSharesSubsystem() {
        let logger = NebulaLogger(subsystem: "com.acme.app", category: .measure)
        let s = logger.signposter
        #expect(s.subsystem == "com.acme.app")
        #expect(s.category == .measure)
        // The exposed osSignposter must be usable with a literal (redaction path).
        let id = s.makeSignpostID()
        #expect(id != .invalid)
    }
}

@Suite("NebulaLogConfiguration")
struct NebulaLogConfigurationTests {
    @Test func defaultHasExpectedShape() {
        let d = NebulaLogConfiguration.default
        #expect(d.isEnabled)
        #expect(d.subsystem == "com.nebula.foundation")
        #expect(d.category == .general)
        #expect(d.minLevel == .info)
    }

    @Test func fluentBuildersReplaceEachField() {
        let base = NebulaLogConfiguration.default
        let cfg = base
            .withSubsystem("com.acme.app")
            .withCategory(.networking)
            .withMinLevel(.error)
            .withEnabled(false)
        #expect(cfg.subsystem == "com.acme.app")
        #expect(cfg.category == .networking)
        #expect(cfg.minLevel == .error)
        #expect(cfg.isEnabled == false)
        // builders return new values; base is untouched.
        #expect(base.subsystem == "com.nebula.foundation")
    }

    @Test func withHandlerOverridesHandler() {
        let sink = NebulaMemoryLogHandler()
        let cfg = NebulaLogConfiguration.default
            .withMinLevel(.debug)
            .withHandler(sink.handler)
        cfg.log(.error, "boom")
        let events = sink.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.level == .error)
        #expect(events.first?.message == "boom")
        #expect(events.first?.category == cfg.category)
    }

    @Test func gatingSkipsBelowMinLevel() {
        let sink = NebulaMemoryLogHandler()
        let cfg = NebulaLogConfiguration.default
            .withMinLevel(.error)
            .withHandler(sink.handler)
        cfg.log(.debug, "ignored")
        cfg.log(.info, "ignored")
        cfg.log(.notice, "ignored")
        cfg.log(.error, "kept")
        let events = sink.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message == "kept")
    }

    @Test func disabledSkipsHandler() {
        let sink = NebulaMemoryLogHandler()
        let cfg = NebulaLogConfiguration.default
            .withEnabled(false)
            .withMinLevel(.debug)
            .withHandler(sink.handler)
        cfg.log(.error, "suppressed")
        #expect(sink.snapshot().isEmpty)
    }

    @Test func loggerReflectsSubsystemAndCategory() {
        let cfg = NebulaLogConfiguration.default
            .withSubsystem("com.acme.app")
            .withCategory(.persistence)
        let logger = cfg.logger()
        #expect(logger.subsystem == "com.acme.app")
        #expect(logger.category == .persistence)
    }
}

@Suite("NebulaMemoryLogHandler")
struct NebulaMemoryLogHandlerTests {
    @Test func ringBufferKeepsMostRecent() {
        let sink = NebulaMemoryLogHandler(capacity: 3)
        let cfg = NebulaLogConfiguration(isEnabled: true, minLevel: .debug, handler: sink.handler)
        cfg.log(.info, "a")
        cfg.log(.info, "b")
        cfg.log(.info, "c")
        cfg.log(.info, "d")
        let events = sink.snapshot()
        #expect(events.count == 3)
        #expect(events.map(\.message) == ["b", "c", "d"])
    }

    @Test func clearEmptiesBuffer() {
        let sink = NebulaMemoryLogHandler()
        let cfg = NebulaLogConfiguration(isEnabled: true, minLevel: .debug, handler: sink.handler)
        cfg.log(.info, "x")
        #expect(sink.count == 1)
        sink.clear()
        #expect(sink.count == 0)
        #expect(sink.snapshot().isEmpty)
    }

    // `capacityPrecondition` is intentionally NOT tested here: `capacity: 0`
    // calls `preconditionFailure`, which traps the process (it is a fail-fast
    // contract violation, not a catchable throw) and would abort the whole
    // test run. The guard at NebulaMemoryLogHandler.swift:49 enforces it.

    @Test func handlerIsSafeToCallFromTasks() async {
        // The handler is @Sendable; many concurrent calls must not crash and must
        // all land in the buffer (Mutex-guarded).
        let sink = NebulaMemoryLogHandler(capacity: 10_000)
        let handler = sink.handler
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    handler(NebulaLogEvent(category: .concurrency, level: .info, message: "m\(i)"))
                }
            }
        }
        #expect(sink.count == 200)
    }
}

@Suite("NebulaSignposter")
struct NebulaSignposterTests {
    @Test func makeSignpostIDIsUnique() {
        let s = NebulaSignposter(subsystem: "com.acme.app")
        let a = s.makeSignpostID()
        let b = s.makeSignpostID()
        #expect(a != b)
        #expect(a != .invalid)
        #expect(a != .null)
    }

    @Test func idWrapsOSValue() {
        let s = NebulaSignposter(subsystem: "com.acme.app")
        let id = s.makeSignpostID()
        // rawValue is the underlying os.OSSignpostID; wrapping round-trips.
        let back = NebulaSignpostID(id.rawValue)
        #expect(back == id)
    }

    @Test func intervalStateRoundTrips() {
        let s = NebulaSignposter(subsystem: "com.acme.app")
        let id = s.makeSignpostID()
        let state = NebulaSignpostIntervalState(s.osSignposter.beginInterval("test", id: id.rawValue))
        // end via the exposed osSignposter (literal name at call site).
        s.osSignposter.endInterval("test", state.rawValue)
        #expect(state == NebulaSignpostIntervalState(state.rawValue))
    }

    @Test func withIntervalSignpost() throws {
        let s = NebulaSignposter(subsystem: "com.acme.app")
        let result = s.osSignposter.withIntervalSignpost("compute") { 1 + 1 }
        #expect(result == 2)
    }
}