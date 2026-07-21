//
//  ArchitectureFeatureFlagsTests.swift
//  NebulaTests
//
//  Wave N14 — tests for the feature-flag toolkit: ``NebulaFlagValue`` (the
//  storage enum), ``NebulaFeatureFlags`` (the one-requirement port + its
//  typed default extension), ``NebulaLocalFeatureFlags`` (the `Mutex`-backed
//  in-memory façade), ``NebulaRemoteFeatureFlags`` (the port refining the base
//  with `refresh() async throws`), and ``NebulaCompositeFeatureFlags`` (the
//  priority-ordered first-non-nil resolver). A `MapFlags` final class proves
//  the default extension works on any conformer; a `FakeRemoteFlags` proves
//  the remote port refines the base. See vault/03-padroes/nebula-feature-flags.md.
//

import Foundation
import Synchronization
import Testing

@testable import Nebula

// MARK: - Fixtures

private struct Theme: Codable, Equatable {
    let name: String
    let dark: Bool
}

/// A non-`NebulaLocalFeatureFlags` ``NebulaFeatureFlags`` conformer: a
/// `Mutex`-backed in-memory `[String: NebulaFlagValue]` store. Proves the typed
/// default extension is reusable on any conformer (the architecture-seam point).
private final class MapFlags: NebulaFeatureFlags {
    private let mutex = Mutex<[String: NebulaFlagValue]>([:])
    func value(forKey key: String) -> NebulaFlagValue? { mutex.withLock { $0[key] } }
    func setValue(_ value: NebulaFlagValue, forKey key: String) {
        mutex.withLock { $0[key] = value }
    }
}

/// A ``NebulaRemoteFeatureFlags`` conformer with a cached map and a
/// `refresh() async throws` that populates the cache. Proves the remote port
/// refines ``NebulaFeatureFlags`` (assignable to `any NebulaFeatureFlags`) and
/// `refresh()` populates `value(forKey:)`.
private final class FakeRemoteFlags: NebulaRemoteFeatureFlags {
    private let mutex = Mutex<[String: NebulaFlagValue]>([:])
    private let fetched: [String: NebulaFlagValue]

    init(fetched: [String: NebulaFlagValue]) {
        self.fetched = fetched
    }

    func value(forKey key: String) -> NebulaFlagValue? { mutex.withLock { $0[key] } }

    func refresh() async throws {
        mutex.withLock { store in
            for (k, v) in fetched { store[k] = v }
        }
    }
}

// MARK: - NebulaFlagValue

@Suite("NebulaFlagValue")
struct NebulaFlagValueTests {

    @Test func equatableSamePayload() {
        #expect(NebulaFlagValue.bool(true) == .bool(true))
        #expect(NebulaFlagValue.string("a") == .string("a"))
        #expect(NebulaFlagValue.int(1) == .int(1))
        #expect(NebulaFlagValue.double(1.5) == .double(1.5))
        #expect(NebulaFlagValue.json(Data([1, 2])) == .json(Data([1, 2])))
    }

    @Test func equatableDistinctCasesNotCoerced() {
        // `.int(1)` and `.double(1.0)` carry distinct payloads — no coercion.
        #expect(NebulaFlagValue.int(1) != .double(1))
        #expect(NebulaFlagValue.bool(true) != .string("true"))
        #expect(NebulaFlagValue.string("1") != .int(1))
    }

    @Test func hashableIntoASet() {
        let set: Set<NebulaFlagValue> = [.bool(true), .bool(true), .int(1), .string("x")]
        #expect(set.count == 3)   // the duplicate `.bool(true)` collapses
    }

    @Test func customStringConvertible() {
        #expect(NebulaFlagValue.bool(true).description == "NebulaFlagValue.bool(true)")
        #expect(NebulaFlagValue.string("a").description == "NebulaFlagValue.string(\"a\")")
        #expect(NebulaFlagValue.int(42).description == "NebulaFlagValue.int(42)")
        #expect(NebulaFlagValue.double(1.5).description == "NebulaFlagValue.double(1.5)")
        #expect(NebulaFlagValue.json(Data([0xDE, 0xAD])).description == "NebulaFlagValue.json(2 bytes)")
    }

    @Test func usableAcrossTaskBoundary() async {
        // Capturing a Sendable `NebulaFlagValue` in a child Task is the point.
        let value = NebulaFlagValue.string("variant-b")
        let read = await Task { value }.value
        #expect(read == .string("variant-b"))
    }
}

// MARK: - NebulaLocalFeatureFlags (façade)

@Suite("NebulaLocalFeatureFlags façade")
struct NebulaLocalFeatureFlagsTests {

    @Test func emptyFaçadeResolvesNil() {
        let flags = NebulaLocalFeatureFlags()
        #expect(flags.value(forKey: "absent") == nil)
        #expect(flags.bool(forKey: "absent") == nil)
        #expect(flags.string(forKey: "absent") == nil)
        #expect(flags.number(forKey: "absent") == nil)
    }

    @Test func setThenReadEachCase() {
        let flags = NebulaLocalFeatureFlags()
        flags.setValue(.bool(true), forKey: "b")
        flags.setValue(.string("s"), forKey: "s")
        flags.setValue(.int(7), forKey: "i")
        flags.setValue(.double(3.5), forKey: "d")
        flags.setValue(.json(Data([1, 2, 3])), forKey: "j")

        #expect(flags.value(forKey: "b") == .bool(true))
        #expect(flags.value(forKey: "s") == .string("s"))
        #expect(flags.value(forKey: "i") == .int(7))
        #expect(flags.value(forKey: "d") == .double(3.5))
        #expect(flags.value(forKey: "j") == .json(Data([1, 2, 3])))
    }

    @Test func typedAccessorsReadTheirPayload() {
        let flags = NebulaLocalFeatureFlags([
            "b": .bool(false),
            "s": .string("x"),
            "i": .int(9),
            "d": .double(2.5),
        ])
        #expect(flags.bool(forKey: "b") == false)
        #expect(flags.string(forKey: "s") == "x")
        #expect(flags.int(forKey: "i") == 9)
        #expect(flags.double(forKey: "d") == 2.5)
    }

    @Test func typedAccessorsReturnNilForMismatchedCase() {
        // `bool(forKey:)` on a `.string` flag returns nil — no coercion.
        let flags = NebulaLocalFeatureFlags(["k": .string("true")])
        #expect(flags.bool(forKey: "k") == nil)
        #expect(flags.int(forKey: "k") == nil)
        #expect(flags.double(forKey: "k") == nil)
    }

    @Test func numberCoercesIntAndDouble() {
        let flags = NebulaLocalFeatureFlags([
            "i": .int(3),
            "d": .double(1.25),
            "s": .string("not-a-number"),
        ])
        #expect(flags.number(forKey: "i") == 3.0)   // .int → Double
        #expect(flags.number(forKey: "d") == 1.25)
        #expect(flags.number(forKey: "s") == nil)   // non-numeric
    }

    @Test func setValueNilRemovesTheKey() {
        let flags = NebulaLocalFeatureFlags(["k": .bool(true)])
        #expect(flags.value(forKey: "k") != nil)
        flags.setValue(nil, forKey: "k")
        #expect(flags.value(forKey: "k") == nil)
    }

    @Test func removeValueAndRemoveAll() {
        let flags = NebulaLocalFeatureFlags(["a": .bool(true), "b": .int(1)])
        flags.removeValue(forKey: "a")
        #expect(flags.value(forKey: "a") == nil)
        #expect(flags.value(forKey: "b") != nil)
        flags.removeAll()
        #expect(flags.value(forKey: "b") == nil)
    }

    @Test func conformsToPort() {
        // Assignable to `any NebulaFeatureFlags` — the port is a reusable seam.
        let flags: any NebulaFeatureFlags = NebulaLocalFeatureFlags(["k": .bool(true)])
        #expect(flags.bool(forKey: "k") == true)
    }

    @Test func jsonDecodesAndThrowsOnCorruptData() throws {
        let good = try JSONEncoder().encode(Theme(name: "dark", dark: true))
        let flags = NebulaLocalFeatureFlags([
            "theme": .json(good),
            "bad": .json(Data([0x00, 0xFF])),
        ])
        let theme = try flags.json(Theme.self, forKey: "theme")
        #expect(theme == Theme(name: "dark", dark: true))

        #expect(throws: DecodingError.self) {
            let _: Theme? = try flags.json(Theme.self, forKey: "bad")
        }
    }

    @Test func jsonReturnsNilForAbsentOrNonJson() throws {
        let flags = NebulaLocalFeatureFlags(["s": .string("x")])
        #expect(try flags.json(Theme.self, forKey: "absent") == nil)   // absent
        #expect(try flags.json(Theme.self, forKey: "s") == nil)       // non-`.json` case
    }
}

// MARK: - NebulaLocalFeatureFlags Sendable + concurrency

@Suite("NebulaLocalFeatureFlags Sendable + concurrency")
struct NebulaLocalFeatureFlagsConcurrencyTests {

    @Test func usableAcrossTaskBoundary() async {
        let flags = NebulaLocalFeatureFlags(["k": .bool(true)])
        // Capturing a Sendable `NebulaLocalFeatureFlags` in a child Task.
        let read = await Task { flags.bool(forKey: "k") }.value
        #expect(read == true)
    }

    @Test func concurrentAccessIsMutexSerialized() async {
        let flags = NebulaLocalFeatureFlags()
        // 50 tasks each write a unique key then read it back through the same
        // Sendable façade. The Mutex must serialize access; a data race would
        // crash or return a wrong value.
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let key = "k\(i)"
                    flags.setValue(.int(i), forKey: key)
                    return flags.int(forKey: key) == i
                }
            }
            var allOK = true
            for await ok in group { if !ok { allOK = false } }
            #expect(allOK)
        }
    }
}

// MARK: - NebulaFeatureFlags port seam (default extension on any conformer)

@Suite("NebulaFeatureFlags port seam")
struct NebulaFeatureFlagsPortTests {

    @Test func customConformerGetsTypedAccessorsForFree() {
        let flags = MapFlags()
        flags.setValue(.bool(true), forKey: "b")
        flags.setValue(.string("s"), forKey: "s")
        flags.setValue(.int(5), forKey: "i")
        flags.setValue(.double(2.0), forKey: "d")

        #expect(flags.bool(forKey: "b") == true)
        #expect(flags.string(forKey: "s") == "s")
        #expect(flags.int(forKey: "i") == 5)
        #expect(flags.double(forKey: "d") == 2.0)
        #expect(flags.number(forKey: "i") == 5.0)   // coercion works on any conformer
    }

    @Test func customConformerGetsJsonBridgeForFree() throws {
        let flags = MapFlags()
        let payload = try JSONEncoder().encode(Theme(name: "auto", dark: false))
        flags.setValue(.json(payload), forKey: "theme")
        let read: Theme? = try flags.json(Theme.self, forKey: "theme")
        #expect(read == Theme(name: "auto", dark: false))
    }

    @Test func existentialHoldsEitherConformer() {
        // `any NebulaFeatureFlags` is itself Sendable — both impls fit the seam.
        let stores: [any NebulaFeatureFlags] = [
            NebulaLocalFeatureFlags(["k": .bool(true)]),
            MapFlags(),
        ]
        for flags in stores {
            #expect(flags.bool(forKey: "absent") == nil)   // both resolve absent → nil
        }
    }
}

// MARK: - NebulaRemoteFeatureFlags (refines the base port)

@Suite("NebulaRemoteFeatureFlags remote port")
struct NebulaRemoteFeatureFlagsTests {

    @Test func refinesTheBasePort() {
        // Assignable to `any NebulaFeatureFlags` — a remote fetcher is a valid
        // composite source.
        let remote: any NebulaFeatureFlags = FakeRemoteFlags(fetched: ["k": .bool(true)])
        #expect(remote.bool(forKey: "k") == nil)   // nothing fetched yet
    }

    @Test func refreshPopulatesTheCache() async throws {
        let remote = FakeRemoteFlags(fetched: ["new_ui": .bool(true), "limit": .int(10)])
        #expect(remote.value(forKey: "new_ui") == nil)   // empty before refresh
        try await remote.refresh()
        #expect(remote.bool(forKey: "new_ui") == true)
        #expect(remote.int(forKey: "limit") == 10)
    }

    @Test func refreshIsCallableAsRemotePort() async throws {
        // The remote port is usable as a composite source after refresh.
        let remote = FakeRemoteFlags(fetched: ["theme": .string("dark")])
        try await remote.refresh()
        let composite = NebulaCompositeFeatureFlags([remote])
        #expect(composite.string(forKey: "theme") == "dark")
    }
}

// MARK: - NebulaCompositeFeatureFlags (priority-ordered first-non-nil)

@Suite("NebulaCompositeFeatureFlags composite")
struct NebulaCompositeFeatureFlagsTests {

    private func sources() -> [NebulaLocalFeatureFlags] {
        [
            NebulaLocalFeatureFlags(["a": .bool(true), "shared": .string("from-0")]),
            NebulaLocalFeatureFlags(["b": .int(1), "shared": .string("from-1")]),
            NebulaLocalFeatureFlags(["c": .double(2.5), "shared": .string("from-2")]),
        ]
    }

    @Test func resolvesFirstNonNilAcrossSources() {
        let composite = NebulaCompositeFeatureFlags(sources())
        #expect(composite.value(forKey: "a") == .bool(true))
        #expect(composite.value(forKey: "b") == .int(1))
        #expect(composite.value(forKey: "c") == .double(2.5))
    }

    @Test func firstSourceShadowsLaterSources() {
        let composite = NebulaCompositeFeatureFlags(sources())
        // `shared` exists in all three; source 0 wins.
        #expect(composite.string(forKey: "shared") == "from-0")
    }

    @Test func absentInAllResolvesNil() {
        let composite = NebulaCompositeFeatureFlags(sources())
        #expect(composite.value(forKey: "absent") == nil)
        #expect(composite.bool(forKey: "absent") == nil)
    }

    @Test func emptyCompositeResolvesNil() {
        let composite = NebulaCompositeFeatureFlags()
        #expect(composite.value(forKey: "anything") == nil)
    }

    @Test func withSourceAppendsAndLeavesOriginalUnchanged() {
        let base = NebulaCompositeFeatureFlags([NebulaLocalFeatureFlags(["a": .bool(true)])])
        let grown = base.withSource(NebulaLocalFeatureFlags(["b": .int(1)]))
        #expect(base.value(forKey: "b") == nil)         // original unchanged
        #expect(grown.value(forKey: "b") == .int(1))    // the new source resolves
        #expect(grown.sources.count == 2)
        #expect(base.sources.count == 1)
    }

    @Test func conformsToPortAndTypedAccessorsFlowThrough() {
        let composite: any NebulaFeatureFlags = NebulaCompositeFeatureFlags([
            NebulaLocalFeatureFlags(["b": .bool(true), "s": .string("x")]),
        ])
        #expect(composite.bool(forKey: "b") == true)
        #expect(composite.string(forKey: "s") == "x")
        #expect(composite.bool(forKey: "absent") == nil)
    }

    @Test func localOverridesWinOverRemoteAndDefaults() async throws {
        // The canonical wiring: [local, remote, defaults].
        let local = NebulaLocalFeatureFlags()
        let remote = FakeRemoteFlags(fetched: ["theme": .string("remote-theme")])
        let defaults = NebulaLocalFeatureFlags(["theme": .string("default-theme")])
        try await remote.refresh()

        let flags = NebulaCompositeFeatureFlags([local, remote, defaults])
        #expect(flags.string(forKey: "theme") == "remote-theme")   // remote > defaults

        local.setValue(.string("local-theme"), forKey: "theme")
        #expect(flags.string(forKey: "theme") == "local-theme")   // local override wins
    }

    @Test func usableAcrossTaskBoundary() async {
        // `NebulaCompositeFeatureFlags` is a Sendable struct.
        let composite = NebulaCompositeFeatureFlags([
            NebulaLocalFeatureFlags(["k": .bool(true)]),
        ])
        let read = await Task { composite.bool(forKey: "k") }.value
        #expect(read == true)
    }
}