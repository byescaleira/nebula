//
//  NebulaCloudKitFeatureFlags.swift
//  Nebula
//
//  Wave N19d (remainder) — CloudKit-backed observability suite. A
//  ``NebulaRemoteFeatureFlags`` conformer backed by a local in-memory cache
//  (synchronous, the base-port contract) whose `refresh()` pulls flag records
//  from CloudKit and replaces the cache. The conformer is **read-only** — the
//  ``NebulaRemoteFeatureFlags`` port has no write requirement (a remote flag
//  backend is app-owned; the app writes `NebulaFlag` records server-side or via
//  CloudKit, Nebula only fetches and serves them). This mirrors
//  ``NebulaCloudKitPreferences``'s stateless-per-call CloudKit boundary: no
//  `CKDatabase` is stored on this conformer, so the preconcurrency Sendability
//  of `CKContainer`/`CKDatabase` never reaches a Nebula `Sendable` derivation.
//  `Sendable` is derived — no `@unchecked`: the stored fields are
//  ``NebulaCloudKitConfiguration`` (Sendable struct),
//  `Mutex<[String: NebulaFlagValue]>` (absorbed behind this `final class`), and
//  a `@Sendable` closure. See vault/03-padroes/nebula-cloudkit-observability.md.
//
//  `value(forKey:)` serves the local cache (immediate, no network). `refresh()`
//  re-fetches on demand; a failed fetch leaves the cache unchanged (the port
//  contract — reads keep resolving to the last good fetch). The fetch is
//  injectable so the cache/refresh contract is unit-tested without CloudKit I/O;
//  the default fetch (``defaultFetch(configuration:)``) is compile-verified
//  (runtime needs an iCloud entitlement + account — app-owned, the
//  MeridianExample precedent). Flag records are encoded/decoded via
//  ``encode(_:into:)`` / ``decode(from:)`` (a `kind` tag + a per-kind field), so
//  the codec is unit-testable with a plain in-memory `CKRecord` — no iCloud.
//

import Foundation
import CloudKit
import Synchronization

/// A ``NebulaRemoteFeatureFlags`` conformer backed by a local cache refreshed
/// from CloudKit.
///
/// The architecture seam: ``value(forKey:)`` serves a local
/// `Mutex<[String: NebulaFlagValue]>` cache (synchronous, matching the
/// ``NebulaFeatureFlags`` contract); ``refresh()`` pulls `NebulaFlag` records
/// from the configured CloudKit database and replaces the cache. The conformer
/// is **read-only** — the port has no write requirement, and writing flag
/// records to CloudKit is app-owned (a remote flag backend is necessarily
/// app-supplied; `dependencies: []` forbids Firebase / LaunchDarkly). The
/// CloudKit boundary is stateless per call (the ``NebulaKeychain`` /
/// ``NebulaCloudKitPreferences`` precedent) — no `CKDatabase` is stored here, so
/// the conformer derives `Sendable` with **no `@unchecked`**.
///
/// An app injects its own `fetch` for tests (a recording closure, a canned
/// dictionary) or omits it to use the default CloudKit fetch. The default fetch
/// requires an iCloud entitlement + a pre-created record zone and is therefore
/// app-owned at runtime; Nebula ships it compile-verified. Flag records are
/// mapped to/from ``NebulaFlagValue`` by ``encode(_:into:)`` /
/// ``decode(from:)``.
///
/// ```swift
/// let flags: NebulaRemoteFeatureFlags = NebulaCloudKitFeatureFlags(
///     .default.withContainerIdentifier("iCloud.com.example.app")
///             .withZoneName("Observability")
///             .withEnabled(true))
/// try await flags.refresh()                       // pull from CloudKit
/// let on: Bool? = flags.bool(forKey: "new_dashboard")   // serves the cache
/// ```
public final class NebulaCloudKitFeatureFlags: NebulaRemoteFeatureFlags {

    /// The resolved CloudKit sync configuration (a `let`; rebuild the conformer
    /// to change it).
    public let configuration: NebulaCloudKitConfiguration

    /// The local synchronous cache. `Mutex` is `~Copyable` /
    /// `@_staticExclusiveOnly`, so it is held by value inside this copyable,
    /// `Sendable` reference (the ``NebulaDefaults`` / ``NebulaLocalMetrics`` /
    /// ``NebulaCloudKitPreferences`` precedent).
    @usableFromInline
    let cache: Mutex<[String: NebulaFlagValue]>

    /// Invoked by ``refresh()`` to pull the fresh flag map. Defaults to
    /// ``defaultFetch(configuration:)``. `@Sendable`.
    private let fetch: @Sendable () async throws -> [String: NebulaFlagValue]

    /// Creates a CloudKit-backed remote feature-flag store.
    ///
    /// - Parameters:
    ///   - configuration: The CloudKit sync configuration. Defaults to
    ///     ``NebulaCloudKitConfiguration/default`` (default container, private
    ///     database, disabled — a disabled conformer never fetches, so reads
    ///     resolve to an empty cache out of the box; enable + `refresh()` to
    ///     populate).
    ///   - fetch: An optional `@Sendable` async closure returning the fresh
    ///     `[String: NebulaFlagValue]`. `nil` (the default) uses
    ///     ``defaultFetch(configuration:)`` — the real CloudKit pull (requires
    ///     an iCloud entitlement + a pre-created zone). Pass a custom fetch for
    ///     tests or for a non-CloudKit backend.
    public init(
        _ configuration: NebulaCloudKitConfiguration = .default,
        fetch: (@Sendable () async throws -> [String: NebulaFlagValue])? = nil
    ) {
        self.configuration = configuration
        self.cache = Mutex([:])
        self.fetch = fetch ?? { try await Self.defaultFetch(configuration: configuration) }
    }

    // MARK: - NebulaFeatureFlags

    public func value(forKey key: String) -> NebulaFlagValue? {
        cache.withLock { $0[key] }
    }

    // MARK: - NebulaRemoteFeatureFlags

    public func refresh() async throws {
        guard configuration.isEnabled else { return }
        // A failed fetch leaves the cache unchanged (the port contract): the
        // cache is only replaced after `fetch` returns successfully.
        let pulled = try await fetch()
        cache.withLock { $0 = pulled }
    }

    // MARK: - CloudKit record codec (pure; unit-testable with no iCloud)

    /// The CloudKit record type used by the flag store.
    public static let recordType: CKRecord.RecordType = "NebulaFlag"
    /// The field holding the `kind` tag (`"bool"`/`"string"`/`"int"`/
    /// `"double"`/`"json"`).
    public static let kindField: CKRecord.FieldKey = "kind"
    /// The field holding a `.bool(_:)` payload.
    public static let boolField: CKRecord.FieldKey = "boolValue"
    /// The field holding a `.string(_:)` payload.
    public static let stringField: CKRecord.FieldKey = "stringValue"
    /// The field holding a `.int(_:)` payload.
    public static let intField: CKRecord.FieldKey = "intValue"
    /// The field holding a `.double(_:)` payload.
    public static let doubleField: CKRecord.FieldKey = "doubleValue"
    /// The field holding a `.json(_:)` payload.
    public static let dataField: CKRecord.FieldKey = "dataValue"

    /// Encodes `value` into `record` under a `kind` tag + a per-kind field.
    /// Pure (no I/O); app-owned code calls this when writing `NebulaFlag`
    /// records to CloudKit.
    public static func encode(_ value: NebulaFlagValue, into record: CKRecord) {
        switch value {
        case .bool(let b):
            record[kindField] = "bool" as CKRecordValue
            record[boolField] = NSNumber(value: b) as CKRecordValue
        case .string(let s):
            record[kindField] = "string" as CKRecordValue
            record[stringField] = s as CKRecordValue
        case .int(let i):
            record[kindField] = "int" as CKRecordValue
            record[intField] = NSNumber(value: i) as CKRecordValue
        case .double(let d):
            record[kindField] = "double" as CKRecordValue
            record[doubleField] = NSNumber(value: d) as CKRecordValue
        case .json(let data):
            record[kindField] = "json" as CKRecordValue
            record[dataField] = data as CKRecordValue
        }
    }

    /// Decodes a ``NebulaFlagValue`` from `record` (the inverse of
    /// ``encode(_:into:)``). Returns `nil` when the `kind` tag is absent or the
    /// payload field is missing/mistyped. Pure (no I/O).
    public static func decode(from record: CKRecord) -> NebulaFlagValue? {
        guard let kind = record[kindField] as? String else { return nil }
        switch kind {
        case "bool":   guard let b = record[boolField] as? Bool else { return nil };       return .bool(b)
        case "string": guard let s = record[stringField] as? String else { return nil };   return .string(s)
        case "int":    guard let i = record[intField] as? Int else { return nil };         return .int(i)
        case "double": guard let d = record[doubleField] as? Double else { return nil };   return .double(d)
        case "json":   guard let data = record[dataField] as? Data else { return nil };    return .json(data)
        default: return nil
        }
    }

    // MARK: - Default fetch (stateless per call — the NebulaKeychain precedent)

    /// The default CloudKit fetch: queries all `NebulaFlag` records in the
    /// configured zone and decodes each into a ``NebulaFlagValue``. Stateless
    /// per call (resolves the container + database fresh). A disabled
    /// configuration is a no-op (``refresh()`` guards on `isEnabled` before
    /// calling). Compile-verified — runtime needs an iCloud entitlement +
    /// account.
    @Sendable
    public static func defaultFetch(
        configuration: NebulaCloudKitConfiguration
    ) async throws -> [String: NebulaFlagValue] {
        let database = NebulaCloudKitPreferences.resolveDatabase(configuration)
        let zoneID = NebulaCloudKitPreferences.zoneID(configuration)
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        // `records(matching:inZoneWith:)` returns `(matchResults, queryCursor)`;
        // flatten the results, dropping any per-record failure (a partial pull
        // keeps the cache consistent with whatever the server returned).
        let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return Dictionary(
            matchResults.compactMap { (recordID, result) -> (String, NebulaFlagValue)? in
                guard let record = try? result.get() else { return nil }
                guard let value = decode(from: record) else { return nil }
                return (recordID.recordName, value)
            },
            uniquingKeysWith: { _, new in new }
        )
    }
}