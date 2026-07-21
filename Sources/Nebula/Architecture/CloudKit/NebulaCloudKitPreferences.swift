//
//  NebulaCloudKitPreferences.swift
//  Nebula
//
//  Wave N19d — CloudKit-backed observability suite. A `NebulaPreferences`
//  conformer backed by a local in-memory cache (synchronous, the port contract)
//  with an injectable async sink that flushes each change to CloudKit. The
//  default sink maps a key/value change to a `CKRecord` (recordType
//  `NebulaPreference`, recordID name = the key, in the configured zone) and
//  saves / deletes it on the configured database — constructed stateless per
//  call (the `NebulaKeychain` precedent), so NO `CKDatabase` is stored on this
//  conformer and the preconcurrency Sendability of `CKContainer`/`CKDatabase`
//  never reaches a Nebula `Sendable` derivation. `Sendable` is derived — no
//  `@unchecked`: the stored fields are `NebulaCloudKitConfiguration` (Sendable
//  struct), `Mutex<[String: Data]>` (absorbed behind this `final class`), and a
//  `@Sendable` closure. See vault/03-padroes/nebula-cloudkit-observability.md.
//
//  The port is intentionally synchronous and non-throwing: reads serve the
//  local cache (immediate, no network), and writes update the cache then
//  enqueue a fire-and-forget `Task.detached` flush. A failed flush is swallowed
//  (the cache already holds the value, so reads stay correct; the next
//  `refresh()` reconciles with the server). `refresh()` / `ensureZone()` are
//  extras beyond the port — the app drives them at its own cadence.
//

import Foundation
import CloudKit
import Synchronization

/// A single key/value change enqueued to a CloudKit preferences sink.
///
/// Carried to the ``NebulaCloudKitPreferences/sink`` closure so the default
/// CloudKit sink (and any test double) can react to a write or a remove without
/// the port itself going `async`. `Sendable, Equatable` by derived conformance.
public struct NebulaCloudKitKVChange: Sendable, Equatable {

    /// The change kind.
    public enum Op: Sendable, Equatable {

        /// A value was written for the key.
        case set(Data)

        /// The key was removed.
        case remove
    }

    /// The affected key (the CloudKit record name in the configured zone).
    public let key: String
    /// The change kind.
    public let op: Op

    /// Creates a change.
    public init(key: String, op: Op) {
        self.key = key
        self.op = op
    }
}

/// A `NebulaPreferences` conformer backed by a local cache with an async
/// CloudKit flush sink.
///
/// The architecture seam: reads serve a local `Mutex<[String: Data]>` cache
/// (synchronous, matching the ``NebulaPreferences`` contract); writes update
/// the cache then enqueue a fire-and-forget `Task.detached` flush to a
/// `@Sendable` sink. The default sink maps the change to a `CKRecord` and
/// saves / deletes it on the configured CloudKit database — constructed
/// **stateless per call** (the `NebulaKeychain` precedent), so no `CKDatabase`
/// is stored here and the conformer derives `Sendable` with **no `@unchecked`**.
///
/// An app injects its own `sink` for tests (a recording closure, a no-op), or
/// omits it to use the default CloudKit sink. The default sink requires an
/// iCloud entitlement + a pre-created record zone (see ``ensureZone()``) and
/// is therefore app-owned at runtime; Nebula ships it compile-verified.
///
/// ```swift
/// let prefs: NebulaPreferences = NebulaCloudKitPreferences(
///     .default.withContainerIdentifier("iCloud.com.example.app")
///             .withZoneName("Preferences")
///             .withEnabled(true))
/// try prefs.setValue(["theme": "dark"], forKey: "settings")   // sync cache write + async flush
/// let s: [String: String]? = try prefs.value([String: String].self, forKey: "settings")
/// ```
public final class NebulaCloudKitPreferences: NebulaPreferences {

    /// The resolved CloudKit sync configuration (a `let`; rebuild the conformer
    /// to change it).
    public let configuration: NebulaCloudKitConfiguration

    /// The local synchronous cache. `Mutex` is `~Copyable` /
    /// `@_staticExclusiveOnly`, so it is held by value inside this copyable,
    /// `Sendable` reference (the `NebulaDefaults` / `NebulaLocalMetrics`
    /// precedent).
    @usableFromInline
    let cache: Mutex<[String: Data]>

    /// Invoked (off the calling thread, in a `Task.detached`) with each change.
    /// Defaults to ``defaultSink(_:change:)``. `@Sendable`.
    private let sink: @Sendable (NebulaCloudKitKVChange) async -> Void

    /// Creates a CloudKit-backed preferences store.
    ///
    /// - Parameters:
    ///   - configuration: The CloudKit sync configuration. Defaults to
    ///     ``NebulaCloudKitConfiguration/default`` (default container, private
    ///     database, disabled — a disabled sink is a no-op, so the conformer is
    ///     a safe in-memory cache out of the box).
    ///   - sink: An optional `@Sendable` async closure invoked with each
    ///     change. `nil` (the default) uses ``defaultSink(_:change:)`` — the
    ///     real CloudKit flush (requires an iCloud entitlement + a pre-created
    ///     zone). Pass a custom sink for tests or for a non-CloudKit backend.
    public init(
        _ configuration: NebulaCloudKitConfiguration = .default,
        sink: (@Sendable (NebulaCloudKitKVChange) async -> Void)? = nil
    ) {
        self.configuration = configuration
        self.cache = Mutex([:])
        self.sink = sink ?? { change in await Self.defaultSink(configuration: configuration, change: change) }
    }

    // MARK: - NebulaPreferences

    public func data(forKey key: String) -> Data? {
        cache.withLock { $0[key] }
    }

    public func setData(_ value: Data?, forKey key: String) {
        cache.withLock { store in
            if let value {
                store[key] = value
            } else {
                store.removeValue(forKey: key)
            }
        }
        let op: NebulaCloudKitKVChange.Op = value.map { .set($0) } ?? .remove
        let change = NebulaCloudKitKVChange(key: key, op: op)
        // Fire-and-forget flush off the calling thread; a failed flush is
        // swallowed (the cache already holds the value, so reads stay correct).
        Task.detached { [sink] in await sink(change) }
    }

    public func remove(forKey key: String) {
        setData(nil, forKey: key)
    }

    // MARK: - CloudKit extras (beyond the NebulaPreferences port)

    /// Ensures the configured record zone exists on the CloudKit database before
    /// writes. Idempotent — saving an existing zone returns an error that is
    /// swallowed. The app calls this once at setup (it requires an iCloud
    /// entitlement + account); Nebula ships it compile-verified.
    public func ensureZone() async throws {
        guard configuration.isEnabled else { return }
        let database = Self.resolveDatabase(configuration)
        // Idempotent: saving an existing zone returns an error that is swallowed.
        _ = try? await database.save(CKRecordZone(zoneID: Self.zoneID(configuration)))
    }

    /// Pulls all `NebulaPreference` records in the configured zone from CloudKit
    /// and replaces the local cache with them. The app drives this at its own
    /// cadence (launch, foreground); the port itself stays synchronous. Requires
    /// an iCloud entitlement + account.
    public func refresh() async throws {
        guard configuration.isEnabled else { return }
        let database = Self.resolveDatabase(configuration)
        let zoneID = Self.zoneID(configuration)
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        // `records(matching:inZoneWith:)` returns `(matchResults, queryCursor)`;
        // the disfavored `[CKRecord]` overload is not selected here. Flatten the
        // results, dropping any per-record failure (a partial pull keeps the
        // cache consistent with whatever the server returned).
        let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
        let pulled: [String: Data] = Dictionary(
            matchResults.compactMap { (recordID, result) -> (String, Data)? in
                guard let record = try? result.get() else { return nil }
                let key = recordID.recordName
                guard let value = record[Self.dataField] as? Data else { return nil }
                return (key, value)
            },
            uniquingKeysWith: { _, new in new }
        )
        cache.withLock { $0 = pulled }
    }

    // MARK: - Defaults (stateless per call — the NebulaKeychain precedent)

    /// The CloudKit record type used by the preferences store.
    public static let recordType: CKRecord.RecordType = "NebulaPreference"
    /// The CloudKit field name holding the raw `Data` payload.
    public static let dataField: CKRecord.FieldKey = "data"

    /// The default CloudKit sink: maps a change to a `CKRecord` and saves /
    /// deletes it on the configured database. Stateless per call (resolves the
    /// container + database fresh). A disabled configuration is a no-op.
    @Sendable
    public static func defaultSink(
        configuration: NebulaCloudKitConfiguration,
        change: NebulaCloudKitKVChange
    ) async {
        guard configuration.isEnabled else { return }
        let database = resolveDatabase(configuration)
        let zoneID = zoneID(configuration)
        let recordID = CKRecord.ID(recordName: change.key, zoneID: zoneID)
        switch change.op {
        case .set(let data):
            let record = CKRecord(recordType: recordType, recordID: recordID)
            record[dataField] = data as CKRecordValue
            _ = try? await database.save(record)
        case .remove:
            _ = try? await database.deleteRecord(withID: recordID)
        }
    }

    /// Resolves the `CKContainer` / `CKDatabase` for the configuration
    /// (stateless; constructed fresh per call). Mirrors the resolution in
    /// ``NebulaCloudKitSyncEngine`` but returns the database instead of storing
    /// it.
    static func resolveDatabase(_ configuration: NebulaCloudKitConfiguration) -> CKDatabase {
        let container: CKContainer
        if let identifier = configuration.containerIdentifier {
            container = CKContainer(identifier: identifier)
        } else {
            container = CKContainer.default()
        }
        switch configuration.environment {
        case .private:  return container.privateCloudDatabase
        case .public:   return container.publicCloudDatabase
        case .shared:   return container.sharedCloudDatabase
        }
    }

    /// The record-zone ID for the configuration.
    static func zoneID(_ configuration: NebulaCloudKitConfiguration) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: configuration.zoneName)
    }
}