//
//  ErrorTests.swift
//  NebulaTests
//
//  Wave C — errors module tests (Swift Testing). Covers envelope construction,
//  equality, LocalizedError/CustomNSError bridging, lossy mapping from
//  NSError/DecodingError/URLError/CocoaError/any Error (kind inference, one-
//  level underlying flatten), wrap(_:), config fluent builders, and the
//  Mutex-backed process-wide config.
//

import Testing
import Foundation
import Synchronization
import Nebula

/// Thread-safe single-error capture for `@Sendable` handlers in tests (a
/// `var` capture would be a Swift 6 data-race error). Mirrors the
/// `NebulaMemoryLogHandler` pattern: `final class @unchecked Sendable` + a
/// `let Mutex`.
final class ErrorCapture: @unchecked Sendable {
    private let mutex = Mutex<NebulaError?>(nil)
    func set(_ e: NebulaError) { mutex.withLock { $0 = e } }
    var value: NebulaError? { mutex.withLock { $0 } }
}

@Suite("NebulaError envelope")
struct NebulaErrorEnvelopeTests {
    @Test func constructionStoresFields() {
        let e = NebulaError(
            code: .init(domain: "App", code: 42),
            kind: .validation,
            message: "invalid",
            failureReason: "reason",
            recoverySuggestions: ["retry", "reset"],
            helpAnchor: "anchor",
            metadata: ["k": "v"]
        )
        #expect(e.code.domain == "App")
        #expect(e.code.code == 42)
        #expect(e.kind == .validation)
        #expect(e.message == "invalid")
        #expect(e.failureReason == "reason")
        #expect(e.recoverySuggestions == ["retry", "reset"])
        #expect(e.helpAnchor == "anchor")
        #expect(e.metadata == ["k": "v"])
        #expect(e.underlying == nil)
    }

    @Test func equalityIncludesAllFields() {
        // Auto-synthesized `==` includes `date`; pin the same date for the
        // equal-pair assertions (two separate `Date()` defaults would differ).
        let date = Date()
        let a = NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m", date: date)
        let b = NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m", date: date)
        #expect(a == b)
        // A different message breaks equality.
        let c = NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m2", date: date)
        #expect(a != c)
        // A different date breaks equality (auto-synthesized `==` includes date).
        var d = a
        d.date = Date(timeIntervalSince1970: 1)
        #expect(a != d)
    }

    @Test func kindIsCaseIterable() {
        #expect(NebulaError.Kind.allCases.contains(.network))
        #expect(NebulaError.Kind.allCases.contains(.decoding))
        #expect(NebulaError.Kind.allCases.contains(.unknown))
    }
}

@Suite("NebulaError LocalizedError & CustomNSError")
struct NebulaErrorBridgingTests {
    private func sample() -> NebulaError {
        NebulaError(
            code: .init(domain: "App", code: 7),
            kind: .validation,
            message: "invalid input",
            failureReason: "reason",
            recoverySuggestions: ["retry", "reset"],
            helpAnchor: "anchor",
            metadata: ["k": "v"]
        )
    }

    @Test func localizedErrorSurface() {
        let e = sample()
        #expect(e.errorDescription == "invalid input")
        #expect(e.failureReason == "reason")
        #expect(e.recoverySuggestion == "retry reset")
        #expect(e.helpAnchor == "anchor")
    }

    @Test func recoverySuggestionIsNilWhenEmpty() {
        let e = NebulaError(code: .init(domain: "D", code: 0), kind: .unknown, message: "m")
        #expect(e.recoverySuggestion == nil)
    }

    @Test func customNSErrorBridge() {
        let e = sample()
        let ns = e as NSError
        #expect(ns.domain == "Nebula.NebulaError")
        #expect(ns.code == 7)
        #expect(ns.userInfo[NSLocalizedDescriptionKey] as? String == "invalid input")
        #expect(ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String == "reason")
        #expect(ns.userInfo["NebulaKind"] as? String == "validation")
        #expect(ns.userInfo["NebulaDomain"] as? String == "App")
        #expect(ns.userInfo["Nebula.k"] as? String == "v")
    }

    @Test func underlyingBridgesIntoNSErrorUserInfo() {
        let inner = NebulaError(code: .init(domain: "Inner", code: 1), kind: .unknown, message: "inner")
        let outer = NebulaError(code: .init(domain: "Outer", code: 2), kind: .unknown, message: "outer", underlying: NebulaError.Box(inner))
        let ns = outer as NSError
        let boxed = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        #expect(boxed?.domain == "Nebula.NebulaError")
        #expect(boxed?.userInfo[NSLocalizedDescriptionKey] as? String == "inner")
    }
}

@Suite("NebulaError lossy mapping")
struct NebulaErrorMappingTests {
    @Test func nsErrorMapsDomainCodeAndUserInfo() {
        let ns = NSError(domain: "AppDomain", code: 99, userInfo: [
            NSLocalizedDescriptionKey: "desc",
            NSLocalizedFailureReasonErrorKey: "why",
            NSLocalizedRecoverySuggestionErrorKey: "try this",
            "Extra": "value",
            NSUnderlyingErrorKey: NSError(domain: "Inner", code: 5),
        ])
        let e = NebulaError(ns)
        #expect(e.code.domain == "AppDomain")
        #expect(e.code.code == 99)
        #expect(e.message == "desc")
        #expect(e.failureReason == "why")
        #expect(e.recoverySuggestions == ["try this"])
        #expect(e.metadata["Extra"] == "value")
        #expect(e.kind == .unknown) // unknown domain
        // One level of underlying only.
        #expect(e.underlying?.value.kind == .unknown)
        #expect(e.underlying?.value.underlying == nil)
    }

    @Test func nsErrorInfersKindFromDomain() {
        #expect(NebulaError(NSError(domain: NSURLErrorDomain, code: 1)).kind == .network)
        #expect(NebulaError(NSError(domain: NSCocoaErrorDomain, code: 1)).kind == .cocoa)
        #expect(NebulaError(NSError(domain: "Custom", code: 1)).kind == .unknown)
    }

    @Test func decodingErrorMapsKindAndCodingPath() throws {
        struct Root: Decodable { let a: Int }
        struct Wrap: Decodable { let root: Root }
        let bad = "{\"root\":{\"a\":\"not-an-int\"}}".data(using: .utf8)!
        let decoder = JSONDecoder()
        do {
            _ = try decoder.decode(Wrap.self, from: bad)
            Issue.record("expected decoding to throw")
        } catch {
            let e = NebulaError(error: error)
            #expect(e.kind == .decoding)
            #expect(e.code.domain == "Swift.DecodingError")
            #expect(e.context != nil)
            // The coding path should mention the failing key.
            let path = e.context?.codingPath.joined(separator: ".") ?? ""
            #expect(path.contains("a"))
        }
    }

    @Test func urlErrorMapsKindNetworkAndCode() {
        let url = URLError(.badURL)
        let e = NebulaError(urlError: url)
        #expect(e.kind == .network)
        #expect(e.code.domain == NSURLErrorDomain)
        #expect(e.code.code == NSURLErrorBadURL)
    }

    @Test func cocoaErrorMapsKindCocoa() {
        let url = URL(fileURLWithPath: "/definitely/does/not/exist/\(UUID().uuidString)")
        _ = try? Data(contentsOf: url) // ensure it would fail
        do {
            _ = try Data(contentsOf: url, options: [])
            Issue.record("expected read to throw")
        } catch {
            let e = NebulaError(error: error)
            #expect(e.kind == .cocoa)
            #expect(e.code.domain == NSCocoaErrorDomain)
        }
    }

    @Test func anyErrorDispatchPrefersConcrete() {
        // A thrown NebulaError is preserved as-is (not re-mapped).
        let original = NebulaError(code: .init(domain: "Keep", code: 1), kind: .validation, message: "keep")
        let mapped = NebulaError(error: original)
        #expect(mapped == original)
        #expect(mapped.code.domain == "Keep")
    }

    @Test func anyErrorFallsBackToNSError() {
        enum CustomErr: Error { case boom }
        let e = NebulaError(error: CustomErr.boom)
        #expect(e.kind == .unknown)
        // Custom Swift enums bridge to NSError with a mangled domain; code 0.
        #expect(e.code.code == 0)
        #expect(e.underlying == nil)
    }
}

@Suite("NebulaError.wrap")
struct NebulaErrorWrapTests {
    @Test func successPath() {
        let r = NebulaError.wrap { 1 + 1 }
        if case .success(let v) = r {
            #expect(v == 2)
        } else {
            Issue.record("expected success")
        }
    }

    @Test func failurePreservesNebulaError() {
        let original = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "x")
        let r = NebulaError.wrap { throw original }
        if case .failure(let e) = r {
            #expect(e == original)
        } else {
            Issue.record("expected failure")
        }
    }

    @Test func failureMapsArbitraryError() {
        enum Boom: Error { case it }
        let r = NebulaError.wrap { throw Boom.it }
        if case .failure(let e) = r {
            #expect(e.kind == .unknown)
        } else {
            Issue.record("expected failure")
        }
    }
}

@Suite("NebulaErrorConfiguration")
struct NebulaErrorConfigurationTests {
    @Test func defaultShape() {
        let d = NebulaErrorConfiguration.default
        #expect(d.isEnabled)
        #expect(d.category == "Nebula")
    }

    @Test func fluentBuilders() {
        let cfg = NebulaErrorConfiguration.default
            .withEnabled(false)
            .withCategory("App")
        #expect(cfg.isEnabled == false)
        #expect(cfg.category == "App")
        // builders return new values; default untouched
        #expect(NebulaErrorConfiguration.default.isEnabled)
    }

    @Test func reportGatesOnEnabled() {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: false, category: "App") { event in
            capture.set(event.error)
        }
        cfg.report(NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m"))
        #expect(capture.value == nil)
    }

    @Test func reportInvokesHandlerWhenEnabled() {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: true, category: "App") { event in
            capture.set(event.error)
        }
        let err = NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m")
        cfg.report(err)
        #expect(capture.value == err)
    }
}

@Suite("NebulaErrorConfig (process-wide)")
struct NebulaErrorConfigTests {
    @Test func getSetRoundTrips() {
        let saved = NebulaErrorConfig.get()
        defer { NebulaErrorConfig.set(saved) }
        let cfg = NebulaErrorConfiguration.default.withCategory("Test-\(UUID().uuidString)")
        NebulaErrorConfig.set(cfg)
        #expect(NebulaErrorConfig.get().category == cfg.category)
    }

    @Test func reportUsesCurrentConfig() {
        let saved = NebulaErrorConfig.get()
        defer { NebulaErrorConfig.set(saved) }
        let capture = ErrorCapture()
        NebulaErrorConfig.set(NebulaErrorConfiguration(isEnabled: true, category: "C") { e in
            capture.set(e.error)
        })
        let err = NebulaError(code: .init(domain: "D", code: 1), kind: .unknown, message: "m")
        NebulaErrorConfig.report(err)
        #expect(capture.value == err)
    }
}

@Suite("NebulaLogConfig (process-wide)")
struct NebulaLogConfigTests {
    @Test func getSetRoundTrips() {
        let saved = NebulaLogConfig.get()
        defer { NebulaLogConfig.set(saved) }
        let cfg = NebulaLogConfiguration.default.withSubsystem("test-\(UUID().uuidString)")
        NebulaLogConfig.set(cfg)
        #expect(NebulaLogConfig.get().subsystem == cfg.subsystem)
    }
}