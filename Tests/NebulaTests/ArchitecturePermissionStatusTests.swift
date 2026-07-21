//
//  ArchitecturePermissionStatusTests.swift
//  NebulaTests
//
//  Wave N15a — tests for ``NebulaPermissionStatus``: the `Sendable` union-superset
// value enum + the `init?(UNAuthorizationStatus:)` bridge. `UNAuthorizationStatus`
// is available on all 5 platforms; `.ephemeral` is iOS-only (`API_UNAVAILABLE(macos,
// watchos, tvos)`) so its bridge arm is `#if os(iOS)`. See
// vault/03-padroes/nebula-notifications.md.
//

import Testing
import Foundation
import UserNotifications

@testable import Nebula

@Suite("NebulaPermissionStatus")
struct NebulaPermissionStatusTests {

    @Test func caseIterableCountIsEight() {
        #expect(NebulaPermissionStatus.allCases.count == 8)
    }

    @Test func equalityAndInequality() {
        #expect(NebulaPermissionStatus.authorized == .authorized)
        #expect(NebulaPermissionStatus.authorized != .denied)
        #expect(NebulaPermissionStatus.notDetermined != .restricted)
        #expect(NebulaPermissionStatus.authorizedAlways != .authorizedWhenInUse)
    }

    @Test func isHashable() {
        let set: Set<NebulaPermissionStatus> = [
            .notDetermined, .restricted, .denied, .authorized,
            .provisional, .ephemeral, .authorizedAlways, .authorizedWhenInUse,
            .authorized
        ]
        #expect(set.count == 8)
    }

    @Test func descriptionIsPrefixedEnumCase() {
        #expect(NebulaPermissionStatus.notDetermined.description == "NebulaPermissionStatus.notDetermined")
        #expect(NebulaPermissionStatus.authorized.description == "NebulaPermissionStatus.authorized")
        #expect(NebulaPermissionStatus.authorizedWhenInUse.description == "NebulaPermissionStatus.authorizedWhenInUse")
    }

    // MARK: - UNAuthorizationStatus bridge

    @Test func bridgesCommonStatuses() {
        #expect(NebulaPermissionStatus(UNAuthorizationStatus.notDetermined) == .notDetermined)
        #expect(NebulaPermissionStatus(UNAuthorizationStatus.denied) == .denied)
        #expect(NebulaPermissionStatus(UNAuthorizationStatus.authorized) == .authorized)
        #expect(NebulaPermissionStatus(UNAuthorizationStatus.provisional) == .provisional)
    }

    @Test func bridgesEphemeralOnIOSOnly() {
        // `.ephemeral` is `API_UNAVAILABLE(macos, watchos, tvos)` (iOS-14, App Clips).
        #if os(iOS)
        #expect(NebulaPermissionStatus(UNAuthorizationStatus.ephemeral) == .ephemeral)
        #else
        // On non-iOS the UN enum has no `.ephemeral` case; the Nebula case still
        // exists (a future non-UN bridge may produce it) but is unreachable here.
        #expect(NebulaPermissionStatus.ephemeral == .ephemeral)
        #endif
    }

    @Test func sendsAcrossTask() async {
        let status = NebulaPermissionStatus.authorized
        let received = await Task { status }.value
        #expect(received == .authorized)
    }
}