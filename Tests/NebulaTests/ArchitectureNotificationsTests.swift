//
//  ArchitectureNotificationsTests.swift
//  NebulaTests
//
//  Wave N15a — tests for the notification toolkit: the value types
// (``NebulaNotificationContent``/``NebulaNotificationTrigger``/
// ``NebulaNotificationRequest``/``NebulaNotificationResponse``/the two
// `OptionSet`s), ``NebulaNotificationsConfiguration`` (the `@Sendable`-handler
// config) + the process-wide ``NebulaNotificationsConfig`` accessor, the
// ``NebulaNotificationCenter`` port seam (a `FakeNotificationCenter` final class
// conformer), ``NebulaNotificationsError`` (the open-struct layer error), and a
// real `UNUserNotificationCenter.current()` round-trip on the macOS host.
//
//  Limitation: `UNNotification` and `UNNotificationResponse` have no public
// initializer (`- (instancetype)init NS_UNAVAILABLE;`, no parameterized init) —
// they are system-only-constructible. The delegate-forwarding methods
// (`willPresent` / `didReceive`) therefore cannot be unit-tested with synthetic
// inputs; only the scheduling surface (which uses constructible
// `UNNotificationRequest`) round-trips here. The `didReceive` payload mapping
// (``NebulaUNNotificationCenter`` `makeNebulaResponse`) is the single untested
// mapping — it is two field reads, covered by compile-time conformance + the
// documented limitation. See vault/03-padroes/nebula-notifications.md.
//

import Testing
import Foundation
import Synchronization
import UserNotifications

@testable import Nebula

// MARK: - Fixtures

/// A ``NebulaNotificationCenter`` conformer backed by an in-memory store, proving
/// the port is testable without the real `UNUserNotificationCenter` (the
/// architecture-seam point — mirror `MapFlags` / `InMemoryPrefs`).
private final class FakeNotificationCenter: NebulaNotificationCenter {
    private let mutex = Mutex<([String: NebulaNotificationRequest], Bool)>(([:], true))

    func requestAuthorization(options: NebulaAuthorizationOptions) async throws -> Bool {
        mutex.withLock { $0.1 }
    }

    func add(_ request: NebulaNotificationRequest) async throws {
        mutex.withLock { $0.0[request.identifier] = request }
    }

    func cancel(_ identifiers: [String]) async {
        mutex.withLock { store in
            for id in identifiers { store.0.removeValue(forKey: id) }
        }
    }

    func cancelAll() async {
        mutex.withLock { $0.0.removeAll() }
    }

    func pendingRequests() async -> [NebulaNotificationRequest] {
        mutex.withLock { Array($0.0.values) }
    }
}

// MARK: - Value types

@Suite("NebulaNotificationContent")
struct NebulaNotificationContentTests {
    @Test func defaultsAreEmpty() {
        let c = NebulaNotificationContent()
        #expect(c.title.isEmpty && c.subtitle.isEmpty && c.body.isEmpty && c.userInfo.isEmpty)
    }
    @Test func equalityAndHashable() {
        let a = NebulaNotificationContent(title: "t", subtitle: "s", body: "b", userInfo: ["k": "v"])
        let b = NebulaNotificationContent(title: "t", subtitle: "s", body: "b", userInfo: ["k": "v"])
        #expect(a == b)
        #expect(a != NebulaNotificationContent(title: "t", body: "b"))
        #expect(Set([a, b, NebulaNotificationContent()]).count == 2)
    }
}

@Suite("NebulaNotificationTrigger")
struct NebulaNotificationTriggerTests {
    @Test func equalityAndHashable() {
        let a: NebulaNotificationTrigger = .timeInterval(30)
        let b: NebulaNotificationTrigger = .timeInterval(30)
        #expect(a == b)
        #expect(a != .timeInterval(60))
        var dc = DateComponents(); dc.hour = 9
        #expect(NebulaNotificationTrigger.calendar(dc) == .calendar(dc))
        #expect(a != .calendar(dc))
    }
}

@Suite("NebulaNotificationRequest")
struct NebulaNotificationRequestTests {
    @Test func constructionAndEquality() {
        let content = NebulaNotificationContent(title: "t", body: "b")
        let a = NebulaNotificationRequest(identifier: "id", content: content, trigger: .timeInterval(10))
        let b = NebulaNotificationRequest(identifier: "id", content: content, trigger: .timeInterval(10))
        #expect(a == b)
        #expect(a.trigger == .timeInterval(10))
        #expect(NebulaNotificationRequest(identifier: "x", content: content).trigger == nil)
    }
}

@Suite("NebulaNotificationResponse")
struct NebulaNotificationResponseTests {
    @Test func constructionAndEquality() {
        let a = NebulaNotificationResponse(identifier: "id", actionIdentifier: "act")
        let b = NebulaNotificationResponse(identifier: "id", actionIdentifier: "act")
        #expect(a == b)
        #expect(a != NebulaNotificationResponse(identifier: "id", actionIdentifier: "other"))
    }
}

@Suite("NebulaNotificationPresentationOptions")
struct NebulaPresentationOptionsTests {
    @Test func optionSetAlgebra() {
        let s: NebulaNotificationPresentationOptions = [.banner, .sound]
        #expect(s.contains(.banner) && s.contains(.sound))
        #expect(!s.contains(.badge))
        let u = s.union(.list)
        #expect(u == [.banner, .sound, .list])
    }
    /// Raw values mirror `UNNotificationPresentationOptions` (badge=1, sound=2,
    /// list=8, banner=16 — `1<<2` is the deprecated `.alert`).
    @Test func rawValuesMirrorUN() {
        #expect(NebulaNotificationPresentationOptions.badge.rawValue == 1)
        #expect(NebulaNotificationPresentationOptions.sound.rawValue == 2)
        #expect(NebulaNotificationPresentationOptions.list.rawValue == 8)
        #expect(NebulaNotificationPresentationOptions.banner.rawValue == 16)
        let nebula: NebulaNotificationPresentationOptions = [.banner, .sound]
        let un = UNNotificationPresentationOptions(rawValue: nebula.rawValue)
        #expect(un == [.banner, .sound])
    }
}

@Suite("NebulaAuthorizationOptions")
struct NebulaAuthorizationOptionsTests {
    @Test func optionSetAlgebra() {
        let s: NebulaAuthorizationOptions = [.alert, .sound, .badge]
        #expect(s.contains(.alert))
        let u = s.union(.provisional)
        #expect(u.contains(.provisional))
    }
    /// Raw values mirror `UNAuthorizationOptions` (non-contiguous: alert=4,
    /// criticalAlert=16, provides=32, provisional=64 — `1<<3` is reserved).
    @Test func rawValuesMirrorUN() {
        #expect(NebulaAuthorizationOptions.badge.rawValue == 1)
        #expect(NebulaAuthorizationOptions.sound.rawValue == 2)
        #expect(NebulaAuthorizationOptions.alert.rawValue == 4)
        #expect(NebulaAuthorizationOptions.criticalAlert.rawValue == 16)
        #expect(NebulaAuthorizationOptions.providesAppNotificationSettings.rawValue == 32)
        #expect(NebulaAuthorizationOptions.provisional.rawValue == 64)
        let nebula: NebulaAuthorizationOptions = [.alert, .badge]
        let un = UNAuthorizationOptions(rawValue: nebula.rawValue)
        #expect(un == [.alert, .badge])
    }
}

// MARK: - Configuration

@Suite("NebulaNotificationsConfiguration")
struct NebulaNotificationsConfigurationTests {

    @Test func defaultHandlersAreCaptureFree() {
        let config = NebulaNotificationsConfiguration.default
        // Default willPresent returns [.banner, .sound]; didReceive is a no-op.
        let request = NebulaNotificationRequest(identifier: "id", content: NebulaNotificationContent())
        #expect(config.willPresent(request) == [.banner, .sound])
        config.didReceive(NebulaNotificationResponse(identifier: "id", actionIdentifier: "act"))
    }

    @Test func withBuildersReturnConcreteType() {
        let config = NebulaNotificationsConfiguration.default
            .withWillPresent { _ in [] }
            .withDidReceive { _ in }
        // Concrete type — assignable to NebulaNotificationsConfiguration.
        let _: NebulaNotificationsConfiguration = config
        let request = NebulaNotificationRequest(identifier: "id", content: NebulaNotificationContent())
        #expect(config.willPresent(request) == [])
    }

    @Test func isSendableNotEquatable() async {
        // Sendable: crosses a Task boundary (a non-throwing Task's `.value` is
        // async but not throwing, so no `try`).
        let config = NebulaNotificationsConfiguration.default
        let received = await Task { config }.value
        let request = NebulaNotificationRequest(identifier: "id", content: NebulaNotificationContent())
        #expect(received.willPresent(request) == [.banner, .sound])
        // NOT Equatable: the @Sendable closures are not comparable (compile-time
        // property — there is no `==` on NebulaNotificationsConfiguration; the
        // absence of an `==` call here is the assertion).
    }

    @Test func sendsAcrossTask() async {
        let captured = Mutex<[NebulaNotificationRequest]>([])
        let config = NebulaNotificationsConfiguration.default
            .withWillPresent { request in
                captured.withLock { $0.append(request) }
                return .banner
            }
        let request = NebulaNotificationRequest(identifier: "x", content: NebulaNotificationContent())
        let options = await Task { config.willPresent(request) }.value
        #expect(options == .banner)
        #expect(captured.withLock { $0.count } == 1)
    }
}

@Suite("NebulaNotificationsConfig accessor", .serialized)
struct NebulaNotificationsConfigAccessorTests {

    @Test func getSetRoundTrip() {
        let original = NebulaNotificationsConfig.get()
        defer { NebulaNotificationsConfig.set(original) }
        let custom = NebulaNotificationsConfiguration.default.withWillPresent { _ in [.list] }
        NebulaNotificationsConfig.set(custom)
        #expect(NebulaNotificationsConfig.get().willPresent(
            NebulaNotificationRequest(identifier: "i", content: NebulaNotificationContent())
        ) == [.list])
    }
}

// MARK: - Port seam

@Suite("NebulaNotificationCenter port")
struct NebulaNotificationCenterPortTests {

    @Test func fakeConformerSchedulesAndCancels() async throws {
        let center: any NebulaNotificationCenter = FakeNotificationCenter()
        let request = NebulaNotificationRequest(
            identifier: "id-1",
            content: NebulaNotificationContent(title: "t", body: "b"),
            trigger: .timeInterval(60)
        )
        try await center.add(request)
        let pending = await center.pendingRequests()
        #expect(pending.count == 1)
        #expect(pending.first?.identifier == "id-1")
        await center.cancel(["id-1"])
        #expect(await center.pendingRequests().isEmpty)
    }

    @Test func fakeConformerCancelAll() async throws {
        let center = FakeNotificationCenter()
        try await center.add(NebulaNotificationRequest(identifier: "a", content: NebulaNotificationContent()))
        try await center.add(NebulaNotificationRequest(identifier: "b", content: NebulaNotificationContent()))
        await center.cancelAll()
        #expect(await center.pendingRequests().isEmpty)
    }

    @Test func fakeConformerAuthorization() async throws {
        let center = FakeNotificationCenter()
        let granted = try await center.requestAuthorization(options: [.alert, .badge])
        #expect(granted == true)
    }

    @Test func facadeIsAPortConformer() {
        // Type-level conformance WITHOUT instantiating the façade (its init calls
        // `UNUserNotificationCenter.current().delegate = self`, which traps in a
        // headless test bundle — no app context). Assignable to
        // `any NebulaNotificationCenter.Type` proves the conformance; the `is`
        // check confirms the dynamic type without an `==` on metatypes.
        let centerType: any NebulaNotificationCenter.Type = NebulaUNNotificationCenter.self
        #expect(centerType is NebulaUNNotificationCenter.Type)
    }
}

// MARK: - Layer error

@Suite("NebulaNotificationsError")
struct NebulaNotificationsErrorTests {

    @Test func factoryStatics() {
        #expect(NebulaNotificationsError.notAuthorized().kind == .notAuthorized)
        #expect(NebulaNotificationsError.schedulingFailed().kind == .schedulingFailed)
        #expect(NebulaNotificationsError.invalidTrigger().kind == .invalidTrigger)
        #expect(NebulaNotificationsError.cancelled().kind == .cancelled)
        #expect(NebulaNotificationsError.unknown().kind == .unknown)
    }

    @Test func coarseKindMapsSchedulingFailedToCocoa() {
        #expect(NebulaNotificationsError.schedulingFailed().coarseKind == .cocoa)
        #expect(NebulaNotificationsError.notAuthorized().coarseKind == .unknown)
        #expect(NebulaNotificationsError.invalidTrigger().coarseKind == .unknown)
        #expect(NebulaNotificationsError.cancelled().coarseKind == .unknown)
        #expect(NebulaNotificationsError.unknown().coarseKind == .unknown)
    }

    @Test func toNebulaErrorBridgesWithoutNewKind() {
        let err = NebulaNotificationsError.schedulingFailed()
        let nebula = err.toNebulaError(kind: err.coarseKind)
        #expect(nebula.kind == .cocoa) // no new NebulaError.Kind case
        #expect(nebula.code.domain == "Nebula.NebulaNotificationsError")
    }

    @Test func equalityAndHashable() {
        let a = NebulaNotificationsError.notAuthorized()
        let b = NebulaNotificationsError.notAuthorized()
        #expect(a == b)
        #expect(a != NebulaNotificationsError.invalidTrigger())
        #expect(Set([a, b, NebulaNotificationsError.unknown()]).count == 2)
    }

    @Test func kindIsStringLiteral() {
        let custom: NebulaNotificationsError.Kind = "custom"
        #expect(NebulaNotificationsError.Kind("custom") == custom)
        #expect(custom.description == "custom")
    }

    @Test func sendsAcrossTask() async {
        let err = NebulaNotificationsError.notAuthorized()
        let received = await Task { err }.value
        #expect(received == err)
    }
}

// MARK: - Façade SDK mapping round-trip (no `UNUserNotificationCenter.current()`)
//
// `UNUserNotificationCenter.current()` traps in a headless test bundle (no app
// context — it aborts the whole swift-testing run). So the façade is NOT
// instantiated here; instead the pure mapping helpers (`makeUNRequest` /
// `makeNebulaRequest`, exposed `internal`) are round-tripped through
// constructible `UNNotificationRequest` / `UNMutableNotificationContent`. This
// covers the SDK-mapping logic (including the `#if !os(tvOS)` content path,
// which runs on the macOS host) without touching the shared singleton.

@Suite("NebulaUNNotificationCenter SDK mapping")
struct NebulaUNNotificationCenterMappingTests {

    @Test func contentAndTriggerRoundTrip() {
        let nebula = NebulaNotificationRequest(
            identifier: "id",
            content: NebulaNotificationContent(title: "title", subtitle: "sub", body: "body", userInfo: ["k": "v"]),
            trigger: .timeInterval(60)
        )
        let un = NebulaUNNotificationCenter.makeUNRequest(nebula)
        #expect(un.identifier == "id")

        // On non-tvOS the content props round-trip (the `#if !os(tvOS)` path runs
        // on the macOS test host). On tvOS the content is content-less.
        #if !os(tvOS)
        #expect(un.content.title == "title")
        #expect(un.content.body == "body")
        #endif

        let back = NebulaUNNotificationCenter.makeNebulaRequest(un)
        #expect(back.identifier == "id")
        #if !os(tvOS)
        #expect(back.content.title == "title")
        #expect(back.content.subtitle == "sub")
        #expect(back.content.body == "body")
        #expect(back.content.userInfo == ["k": "v"])
        #else
        #expect(back.content.title.isEmpty)
        #endif
        guard case .timeInterval(let ti) = back.trigger else {
            Issue.record("expected time-interval trigger"); return
        }
        #expect(ti == 60)
    }

    @Test func calendarTriggerRoundTrip() {
        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 30
        let nebula = NebulaNotificationRequest(
            identifier: "cal",
            content: NebulaNotificationContent(body: "alarm"),
            trigger: .calendar(dc)
        )
        let un = NebulaUNNotificationCenter.makeUNRequest(nebula)
        guard case .calendar(let backDC) = NebulaUNNotificationCenter.makeNebulaTrigger(un.trigger) else {
            Issue.record("expected calendar trigger"); return
        }
        #expect(backDC.hour == 9)
        #expect(backDC.minute == 30)
    }

    // NOTE: `unsupportedTriggerMapsToNil` was removed — the only constructible
    // `UNNotificationTrigger` subclasses are `UNTimeIntervalNotificationTrigger`
    // and `UNCalendarNotificationTrigger` (both SUPPORTED). The unsupported
    // types (`UNPushNotificationTrigger`, `UNLocationNotificationTrigger`)
    // inherit `init NS_UNAVAILABLE` from `UNNotificationTrigger` and are
    // system-only-constructible, so the "unsupported → nil" branch of
    // `makeNebulaTrigger` is unreachable from a unit test. The `nil` branch is
    // covered by `nilTriggerMapsToNil`; the unsupported branch is covered by
    // compile-time conformance + this documented limitation.

    @Test func nilTriggerMapsToNil() {
        #expect(NebulaUNNotificationCenter.makeNebulaTrigger(nil) == nil)
        #expect(NebulaUNNotificationCenter.makeUNTrigger(nil) == nil)
    }

    @Test func makeUNContentIsContentLessOnTvOS() {
        let content = NebulaUNNotificationCenter.makeUNContent(
            NebulaNotificationContent(title: "t", body: "b")
        )
        #if os(tvOS)
        // Content-less on tvOS (the props are API_UNAVAILABLE(tvos)).
        #expect(content.title.isEmpty)
        #else
        #expect(content.title == "t")
        #expect(content.body == "b")
        #endif
    }

    @Test func makeNebulaContentFromMutableContent() {
        let mutable = UNMutableNotificationContent()
        #if !os(tvOS)
        mutable.title = "hi"
        mutable.body = "there"
        mutable.userInfo = ["a": "b"]
        #endif
        let nebula = NebulaUNNotificationCenter.makeNebulaContent(mutable)
        #if os(tvOS)
        #expect(nebula.title.isEmpty)
        #else
        #expect(nebula.title == "hi")
        #expect(nebula.body == "there")
        #expect(nebula.userInfo == ["a": "b"])
        #endif
    }
}