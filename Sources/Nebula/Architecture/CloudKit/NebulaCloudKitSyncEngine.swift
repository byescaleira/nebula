//
//  NebulaCloudKitSyncEngine.swift
//  Nebula
//
//  Wave N19c — CloudKit glue slice. A `final class` conforming to
//  ``NebulaCloudKitSync`` that wraps `CKSyncEngine`. CloudKit core types
//  (`CKContainer` / `CKDatabase` / `CKSyncEngine`) are available on all 5
//  platforms below the `.v26` floor (verified against the Xcode 27 Beta 3
//  `CloudKit.swiftmodule`), so NO `@available` gate and NO `#if os()` are needed
//  for the core sync path. `CKSyncEngine` is a clean `final class : Sendable`
//  (no `@unchecked`), so this wrapper derives `Sendable` — all stored
//  properties are `Sendable` (the engine, the Nebula config, and a Nebula-owned
//  `@Sendable`-closure delegate adapter). See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import CloudKit

/// A `CKSyncEngine`-backed ``NebulaCloudKitSync`` conformer.
///
/// A `final class` that resolves a `CKContainer` (default or by identifier),
/// selects the database for the configured ``NebulaCloudKitEnvironment``
/// (private / public / shared), and drives a `CKSyncEngine` for record sync.
/// `Sendable` is derived — no `@unchecked` conformance is authored:
/// - `CKSyncEngine` is a clean `final class : Sendable` (verified in the
///   `CloudKit.swiftmodule` interface);
/// - ``NebulaCloudKitConfiguration`` is a `Sendable` value type;
/// - the nested `Delegate` adapter is a Nebula-owned `final class` whose
///   stored properties are `@Sendable` closures, so it is `Sendable` by the
///   SE-0302 final-class rule.
///
/// The `CKContainer` / `CKDatabase` are constructed locally in `init`, used to
/// build the `CKSyncEngine.Configuration`, and then discarded — they are NOT
/// stored on this conformer, so their (preconcurrency) Sendability never
/// reaches a Nebula `Sendable` derivation. The `CKSyncEngine` retains its
/// database internally.
///
/// `sendChanges()` / `fetchChanges()` are gated on
/// ``NebulaCloudKitConfiguration/isEnabled`` (no-op when disabled), and the
/// underlying `CKSyncEngine.Configuration.automaticallySync` is set to match
/// `isEnabled` at construction — so a disabled engine never auto-syncs and
/// ignores manual sync calls.
public final class NebulaCloudKitSyncEngine: NebulaCloudKitSync {

    /// The Nebula-owned `@Sendable`-closure adapter bridging
    /// `CKSyncEngineDelegate`.
    ///
    /// `CKSyncEngineDelegate` is `AnyObject & Sendable`, so the adapter must be
    /// a class. It is `final` and its stored properties are `@Sendable` async
    /// closures (Sendable), so `Sendable` is derived (SE-0302 final-class rule)
    /// — no `@unchecked`. The engine retains the delegate (it stores
    /// `Configuration.delegate`), so this class does not need to outlive the
    /// engine; ``NebulaCloudKitSyncEngine`` keeps an extra `let` reference for
    /// explicit lifetime ownership.
    private final class Delegate: CKSyncEngineDelegate {
        /// Invoked for every sync-engine event. Defaults to a capture-free
        /// no-op.
        let eventHandler: @Sendable (CKSyncEngine.Event, CKSyncEngine) async -> Void
        /// Provides the next batch of record-zone changes to send. Defaults to
        /// returning `nil` (no pending changes to push).
        let batchProvider: @Sendable (CKSyncEngine.SendChangesContext, CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch?

        init(
            eventHandler: @escaping @Sendable (CKSyncEngine.Event, CKSyncEngine) async -> Void = { _, _ in },
            batchProvider: @escaping @Sendable (CKSyncEngine.SendChangesContext, CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? = { _, _ in nil }
        ) {
            self.eventHandler = eventHandler
            self.batchProvider = batchProvider
        }

        func handleEvent(
            _ event: CKSyncEngine.Event,
            syncEngine: CKSyncEngine
        ) async {
            await eventHandler(event, syncEngine)
        }

        func nextRecordZoneChangeBatch(
            _ context: CKSyncEngine.SendChangesContext,
            syncEngine: CKSyncEngine
        ) async -> CKSyncEngine.RecordZoneChangeBatch? {
            await batchProvider(context, syncEngine)
        }

        // `nextFetchChangesOptions` is provided by the `CKSyncEngineDelegate`
        // default extension (returns `CKSyncEngine.FetchChangesOptions()`); no
        // override is needed here.
    }

    /// The resolved configuration (a `let` — to change it, construct a new
    /// engine).
    public let configuration: NebulaCloudKitConfiguration
    /// The delegate adapter (retained for the engine's lifetime; the engine
    /// also retains it via `Configuration.delegate`).
    private let delegate: Delegate
    /// The wrapped CloudKit sync engine.
    private let engine: CKSyncEngine

    /// Creates a CloudKit sync engine.
    ///
    /// - Parameters:
    ///   - configuration: The CloudKit sync configuration. Defaults to
    ///     ``NebulaCloudKitConfiguration/default`` (default container, private
    ///     database, disabled).
    ///   - handleEvent: An optional `@Sendable` closure invoked for every
    ///     `CKSyncEngine.Event` (state updates, fetched/sent change batches,
    ///     account changes). Defaults to a no-op. Use this to fan events out to
    ///     metrics / analytics / logging sinks.
    ///   - nextRecordZoneChangeBatch: An optional `@Sendable` closure that
    ///     provides the next `CKSyncEngine.RecordZoneChangeBatch` of pending
    ///     local changes to push. Defaults to returning `nil` (no changes). An
    ///     observability adapter supplies records to push here.
    public init(
        _ configuration: NebulaCloudKitConfiguration = .default,
        handleEvent: (@Sendable (CKSyncEngine.Event, CKSyncEngine) async -> Void)? = nil,
        nextRecordZoneChangeBatch: (@Sendable (CKSyncEngine.SendChangesContext, CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch?)? = nil
    ) {
        self.configuration = configuration

        // Resolve the CKContainer: explicit identifier, or the app's default.
        // CKContainer is available macOS 10.12 / iOS 9.3 / tvOS 9.2 / watchOS 3.0
        // (+ visionOS via *) — below the .v26 floor, so no @available gate.
        let container: CKContainer
        if let identifier = configuration.containerIdentifier {
            container = CKContainer(identifier: identifier)
        } else {
            container = CKContainer.default()
        }

        // Select the database for the configured environment (database scope).
        // The three properties are available below the .v26 floor on all 5
        // platforms (sharedCloudDatabase: macOS 10.12 / iOS 10.0 / tvOS 10.0 /
        // watchOS 3.0; private/public on the container's base availability).
        let database: CKDatabase
        switch configuration.environment {
        case .private:
            database = container.privateCloudDatabase
        case .public:
            database = container.publicCloudDatabase
        case .shared:
            database = container.sharedCloudDatabase
        }

        let delegate = Delegate(
            eventHandler: handleEvent ?? { _, _ in },
            batchProvider: nextRecordZoneChangeBatch ?? { _, _ in nil }
        )
        self.delegate = delegate

        // CKSyncEngine.Configuration is a Sendable struct; the designated
        // init takes database / stateSerialization / delegate. The
        // `automaticallySync` var is set AFTER construction (it is a public
        // `var`) so a disabled Nebula config produces an engine that never
        // auto-syncs — CloudKit's default is `true`, which would otherwise
        // begin syncing on init.
        var ckConfiguration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: nil,
            delegate: delegate
        )
        ckConfiguration.automaticallySync = configuration.isEnabled
        self.engine = CKSyncEngine(ckConfiguration)
    }

    /// The wrapped `CKSyncEngine` (exposed for consumers that need to drive
    /// `CKSyncEngine` APIs directly, e.g. `cancelOperations()` or read
    /// `state`).
    public var syncEngine: CKSyncEngine { engine }

    // MARK: - NebulaCloudKitSync

    /// Pushes pending local record changes to CloudKit via the underlying
    /// `CKSyncEngine`. A no-op when ``configuration`` is disabled
    /// (`isEnabled == false`).
    public func sendChanges() async throws {
        guard configuration.isEnabled else { return }
        try await engine.sendChanges()
    }

    /// Pulls pending server record changes from CloudKit via the underlying
    /// `CKSyncEngine`. A no-op when ``configuration`` is disabled
    /// (`isEnabled == false`).
    public func fetchChanges() async throws {
        guard configuration.isEnabled else { return }
        try await engine.fetchChanges()
    }
}
