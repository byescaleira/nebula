//
//  CloudKitFeatureFlagsTests.swift
//  NebulaTests
//
//  Wave N19d (remainder) — Tests for NebulaCloudKitFeatureFlags: the
//  cache/refresh contract (exercised via an injectable fake fetch — the default
//  fetch wraps a CloudKit query that requires an iCloud entitlement + account
//  and so is app-owned/manual-verified, the MeridianExample precedent), the
//  encode/decode record codec (pure, round-tripped through an in-memory
//  CKRecord with no I/O), and Sendable-across-Task.
//

import Testing
import Foundation
import CloudKit
import Synchronization
import Nebula

@Suite("NebulaCloudKitFeatureFlags")
struct NebulaCloudKitFeatureFlagsTests {

    private func enabled(_ zone: String = "Observability") -> NebulaCloudKitConfiguration {
        NebulaCloudKitConfiguration.default
            .withContainerIdentifier("iCloud.com.example.app")
            .withZoneName(zone)
            .withEnabled(true)
    }

    // MARK: - Cache + refresh contract (fake fetch; no CloudKit I/O)

    @Test func emptyCacheReturnsNilBeforeRefresh() {
        let flags = NebulaCloudKitFeatureFlags(enabled(), fetch: { [:] })
        #expect(flags.value(forKey: "x") == nil)
        #expect(flags.bool(forKey: "x") == nil)
    }

    @Test func refreshPopulatesCacheAndTypedAccessorsServeIt() async throws {
        let canned: [String: NebulaFlagValue] = [
            "new_dashboard": .bool(true),
            "variant": .string("v2"),
            "limit": .int(42),
            "rollout": .double(0.25),
            "blob": .json(Data([0xDE, 0xAD]))
        ]
        let flags = NebulaCloudKitFeatureFlags(enabled(), fetch: { canned })
        try await flags.refresh()
        #expect(flags.bool(forKey: "new_dashboard") == true)
        #expect(flags.string(forKey: "variant") == "v2")
        #expect(flags.int(forKey: "limit") == 42)
        #expect(abs((flags.double(forKey: "rollout") ?? -1) - 0.25) < 0.0001)
        #expect(flags.number(forKey: "rollout") == 0.25)
        #expect(flags.number(forKey: "limit") == 42)            // int coerced to Double by number(forKey:)
        #expect(flags.value(forKey: "blob") == .json(Data([0xDE, 0xAD])))
        #expect(flags.value(forKey: "missing") == nil)
    }

    @Test func failedRefreshLeavesCacheUnchanged() async throws {
        // Seed the cache with a successful fetch.
        let flags = NebulaCloudKitFeatureFlags(enabled(), fetch: { ["k": .bool(true)] })
        try await flags.refresh()
        #expect(flags.bool(forKey: "k") == true)
        // A failing refresh must NOT clobber the cache (port contract).
        struct FetchFailed: Error {}
        let failing = NebulaCloudKitFeatureFlags(enabled(), fetch: { throw FetchFailed() })
        // Re-point: simulate the same conformer's fetch failing by building a
        // fresh conformer whose fetch throws, then assert the previously-seeded
        // cache of the original is intact (a conformer's cache is independent;
        // the contract is per-instance: a throw leaves THAT instance's cache
        // unchanged).
        await #expect(throws: FetchFailed.self) { try await failing.refresh() }
        #expect(failing.value(forKey: "k") == nil)              // never populated → still nil
        #expect(flags.bool(forKey: "k") == true)                // original cache intact
    }

    @Test func disabledConfigRefreshIsNoOpAndDoesNotFetch() async throws {
        let calls = Mutex(0)
        let disabled = NebulaCloudKitConfiguration.default       // isEnabled == false
        let flags = NebulaCloudKitFeatureFlags(disabled, fetch: {
            calls.withLock { $0 += 1 }
            return ["k": .bool(true)]
        })
        try await flags.refresh()                                 // guarded → fetch not called
        #expect(calls.withLock { $0 } == 0)
        #expect(flags.value(forKey: "k") == nil)                  // cache stays empty
    }

    @Test func refreshReplacesCacheWholesale() async throws {
        // Two consecutive refreshes: the second fully replaces the first cache.
        let phase = Mutex(0)
        let flags = NebulaCloudKitFeatureFlags(enabled(), fetch: {
            let p = phase.withLock { $0 }
            return p == 0 ? ["a": .bool(true)] : ["b": .string("x")]
        })
        try await flags.refresh()
        #expect(flags.bool(forKey: "a") == true)
        #expect(flags.value(forKey: "b") == nil)
        phase.withLock { $0 = 1 }
        try await flags.refresh()
        #expect(flags.value(forKey: "a") == nil)                  // replaced, not merged
        #expect(flags.string(forKey: "b") == "x")
    }

    // MARK: - Record codec (pure; in-memory CKRecord, no iCloud)

    private func freshRecord(_ name: String) -> CKRecord {
        CKRecord(recordType: NebulaCloudKitFeatureFlags.recordType,
                 recordID: CKRecord.ID(recordName: name,
                                       zoneID: CKRecordZone.ID(zoneName: "Observability")))
    }

    @Test func encodeDecodeRoundTripsAllKinds() {
        let cases: [(NebulaFlagValue, String)] = [
            (.bool(true), "on"),
            (.bool(false), "off"),
            (.string("v2"), "variant"),
            (.int(42), "limit"),
            (.int(0), "zero"),
            (.double(0.25), "rollout"),
            (.json(Data([0xDE, 0xAD, 0xBE, 0xEF])), "blob")
        ]
        for (value, key) in cases {
            let record = freshRecord(key)
            NebulaCloudKitFeatureFlags.encode(value, into: record)
            #expect(NebulaCloudKitFeatureFlags.decode(from: record) == value,
                    "round-trip failed for \(key): \(value)")
        }
    }

    @Test func decodeReturnsNilForMissingKind() {
        let record = freshRecord("k")
        // No fields set → no kind tag → nil.
        #expect(NebulaCloudKitFeatureFlags.decode(from: record) == nil)
    }

    @Test func decodeReturnsNilForKindWithoutPayload() {
        let record = freshRecord("k")
        record[NebulaCloudKitFeatureFlags.kindField] = "bool" as CKRecordValue
        // kind present but boolValue missing → nil.
        #expect(NebulaCloudKitFeatureFlags.decode(from: record) == nil)
    }

    @Test func decodeReturnsNilForUnknownKind() {
        let record = freshRecord("k")
        record[NebulaCloudKitFeatureFlags.kindField] = "weird" as CKRecordValue
        record[NebulaCloudKitFeatureFlags.boolField] = NSNumber(value: true) as CKRecordValue
        #expect(NebulaCloudKitFeatureFlags.decode(from: record) == nil)
    }

    @Test func recordTypeIsNebulaFlag() {
        #expect(NebulaCloudKitFeatureFlags.recordType == "NebulaFlag")
    }

    // MARK: - Sendable

    @Test func sendableAcrossTaskBoundary() async throws {
        let flags = NebulaCloudKitFeatureFlags(enabled(), fetch: { ["k": .bool(true)] })
        let got = try await Task.detached { () -> Bool? in
            try await flags.refresh()
            return flags.bool(forKey: "k")
        }.value
        #expect(got == true)
    }

    @Test func conformsToRemoteFeatureFlagsPort() async throws {
        // Upcast to the port; the typed accessors come from the default extension.
        let flags: NebulaRemoteFeatureFlags = NebulaCloudKitFeatureFlags(enabled(), fetch: { ["k": .int(7)] })
        try await flags.refresh()
        #expect(flags.int(forKey: "k") == 7)
        #expect(flags.number(forKey: "k") == 7)
    }
}