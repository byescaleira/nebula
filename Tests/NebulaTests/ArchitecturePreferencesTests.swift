//
//  ArchitecturePreferencesTests.swift
//  NebulaTests
//
//  Wave N2 — tests for `NebulaPreferences` (the port + its Codable/
//  RawRepresentable default extension) and `NebulaDefaults` (the `Mutex`-
//  wrapped `UserDefaults` façade). Each test uses an isolated
//  `UserDefaults(suiteName:)` (handed to `NebulaDefaults` via the `sending`
//  init, so the suite can't be touched afterward) — no `.standard` pollution.
//  An `InMemoryPrefs` final class proves the default extension works on any
//  conformer, not just `UserDefaults`. See vault/03-padroes/nebula-preferences.md.
//

import Foundation
import Synchronization
import Testing

@testable import Nebula

// MARK: - Fixtures

private struct Settings: Codable, Equatable {
    let theme: String
    let volume: Int
}

private enum Theme: String, Codable, RawRepresentable, Equatable {
    case light, dark, auto
}

private enum Level: Int, Codable, RawRepresentable, Equatable {
    case off, low, high
}

/// A non-`UserDefaults` ``NebulaPreferences`` conformer: a `Mutex`-backed
/// in-memory `[String: Data]` store. Proves the Codable/RawRepresentable default
/// extension is reusable on any conformer (the architecture-seam point).
private final class InMemoryPrefs: NebulaPreferences {
    private let mutex = Mutex<[String: Data]>([:])
    func data(forKey key: String) -> Data? { mutex.withLock { $0[key] } }
    func setData(_ value: Data?, forKey key: String) {
        mutex.withLock { (store: inout [String: Data]) -> Void in
            if let value { store[key] = value } else { store.removeValue(forKey: key) }
        }
    }
    func remove(forKey key: String) {
        mutex.withLock { (store: inout [String: Data]) -> Void in store.removeValue(forKey: key) }
    }
}

// MARK: - Byte-level (NebulaDefaults over UserDefaults)

@Suite("NebulaDefaults byte-level")
struct NebulaDefaultsByteTests {

    private func make() -> NebulaDefaults {
        NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.\(#function).\(UUID())")!)
    }

    @Test func dataRoundTripsThroughSetGetRemove() throws {
        let prefs = make()
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(prefs.data(forKey: "k") == nil)

        prefs.setData(payload, forKey: "k")
        #expect(prefs.data(forKey: "k") == payload)

        prefs.remove(forKey: "k")
        #expect(prefs.data(forKey: "k") == nil)
    }

    @Test func setDataNilRemovesTheKey() {
        let prefs = make()
        prefs.setData(Data([1, 2, 3]), forKey: "k")
        #expect(prefs.data(forKey: "k") != nil)
        prefs.setData(nil, forKey: "k")
        #expect(prefs.data(forKey: "k") == nil)
    }

    @Test func removeIsNoOpForAbsentKey() {
        let prefs = make()
        prefs.remove(forKey: "never-set")
        #expect(prefs.data(forKey: "never-set") == nil)
    }
}

// MARK: - Codable bridge (default extension)

@Suite("NebulaPreferences Codable bridge")
struct NebulaPreferencesCodableTests {

    private func make() -> NebulaDefaults {
        NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.\(#function).\(UUID())")!)
    }

    @Test func codableRoundTrips() throws {
        let prefs = make()
        try prefs.setValue(Settings(theme: "dark", volume: 7), forKey: "settings")
        let read: Settings? = try prefs.value(Settings.self, forKey: "settings")
        #expect(read == Settings(theme: "dark", volume: 7))
    }

    @Test func codableAbsentKeyReturnsNil() throws {
        let prefs = make()
        let read: Settings? = try prefs.value(Settings.self, forKey: "absent")
        #expect(read == nil)
    }

    @Test func setValueNilRemovesTheKey() throws {
        let prefs = make()
        try prefs.setValue(Settings(theme: "light", volume: 1), forKey: "settings")
        #expect(try prefs.value(Settings.self, forKey: "settings") != nil)
        try prefs.setValue(Settings?.none, forKey: "settings")
        #expect(try prefs.value(Settings.self, forKey: "settings") == nil)
    }

    @Test func corruptDataThrowsDecodingError() throws {
        let prefs = make()
        prefs.setData(Data([0x00, 0xFF, 0x00]), forKey: "settings") // not valid JSON for Settings
        #expect(throws: DecodingError.self) {
            let _: Settings? = try prefs.value(Settings.self, forKey: "settings")
        }
    }
}

// MARK: - RawRepresentable bridge (default extension)

@Suite("NebulaPreferences RawRepresentable bridge")
struct NebulaPreferencesRawTests {

    private func make() -> NebulaDefaults {
        NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.\(#function).\(UUID())")!)
    }

    @Test func rawRepresentableStringRoundTrips() throws {
        let prefs = make()
        try prefs.setRawValue(Theme.dark, forKey: "theme")
        let read: Theme? = try prefs.rawValue(Theme.self, forKey: "theme")
        #expect(read == .dark)
    }

    @Test func rawRepresentableIntRoundTrips() throws {
        let prefs = make()
        try prefs.setRawValue(Level.high, forKey: "level")
        let read: Level? = try prefs.rawValue(Level.self, forKey: "level")
        #expect(read == .high)
    }

    @Test func rawRepresentableAbsentReturnsNil() throws {
        let prefs = make()
        let read: Theme? = try prefs.rawValue(Theme.self, forKey: "absent")
        #expect(read == nil)
    }

    @Test func rawRepresentableUnmappableRawReturnsNil() throws {
        let prefs = make()
        // Store a raw value that is not a valid Theme case.
        try prefs.setValue("midnight" as String, forKey: "theme")
        let read: Theme? = try prefs.rawValue(Theme.self, forKey: "theme")
        #expect(read == nil) // "midnight" is not light/dark/auto → R(rawValue:) returns nil
    }

    @Test func setRawValueNilRemovesTheKey() throws {
        let prefs = make()
        try prefs.setRawValue(Theme.light, forKey: "theme")
        #expect(try prefs.rawValue(Theme.self, forKey: "theme") != nil)
        try prefs.setRawValue(Theme?.none, forKey: "theme")
        #expect(try prefs.rawValue(Theme.self, forKey: "theme") == nil)
    }
}

// MARK: - Port is a reusable seam (default extension on a non-UserDefaults conformer)

@Suite("NebulaPreferences port seam")
struct NebulaPreferencesPortTests {

    @Test func inMemoryConformerGetsCodableBridgeForFree() throws {
        let prefs = InMemoryPrefs()
        try prefs.setValue(Settings(theme: "auto", volume: 3), forKey: "settings")
        let read: Settings? = try prefs.value(Settings.self, forKey: "settings")
        #expect(read == Settings(theme: "auto", volume: 3))
    }

    @Test func inMemoryConformerGetsRawRepresentableBridgeForFree() throws {
        let prefs = InMemoryPrefs()
        try prefs.setRawValue(Level.low, forKey: "level")
        let read: Level? = try prefs.rawValue(Level.self, forKey: "level")
        #expect(read == .low)
    }

    @Test func existentialHoldsEitherConformer() throws {
        // `any NebulaPreferences` is itself Sendable — both impls fit the seam.
        let stores: [NebulaPreferences] = [
            NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.existential.\(UUID())")!),
            InMemoryPrefs()
        ]
        for prefs in stores {
            try prefs.setValue(Settings(theme: "dark", volume: 9), forKey: "s")
            let read: Settings? = try prefs.value(Settings.self, forKey: "s")
            #expect(read == Settings(theme: "dark", volume: 9))
        }
    }
}

// MARK: - Sendable + concurrency

@Suite("NebulaDefaults Sendable + concurrency")
struct NebulaDefaultsConcurrencyTests {

    @Test func usableAcrossTaskBoundary() async throws {
        let prefs = NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.sendable.\(UUID())")!)
        try prefs.setValue(Settings(theme: "dark", volume: 5), forKey: "s")
        // Capturing a Sendable `NebulaDefaults` in a child Task is the whole point.
        let read: Settings? = try await Task {
            try prefs.value(Settings.self, forKey: "s")
        }.value
        #expect(read == Settings(theme: "dark", volume: 5))
    }

    @Test func concurrentAccessIsMutexSerialized() async throws {
        let prefs = NebulaDefaults(UserDefaults(suiteName: "NebulaTests.Preferences.concurrent.\(UUID())")!)
        // 50 tasks each write a unique key then read it back through the same
        // Sendable façade. The Mutex must serialize access; a data race would
        // crash or return a wrong value.
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let key = "k\(i)"
                    do {
                        try prefs.setValue(i, forKey: key)
                        let read: Int? = try prefs.value(Int.self, forKey: key)
                        return read == i
                    } catch {
                        return false
                    }
                }
            }
            var allOK = true
            for await ok in group { if !ok { allOK = false } }
            #expect(allOK)
        }
    }
}