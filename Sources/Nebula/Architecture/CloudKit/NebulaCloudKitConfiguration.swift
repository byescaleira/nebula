//
//  NebulaCloudKitConfiguration.swift
//  Nebula
//
//  Wave N19c — CloudKit glue slice. The CloudKit sync configuration: a
//  `Sendable`, `Equatable` value carrying the container identifier, the
//  database environment, the record-zone name, and an `isEnabled` gate. Fluent
//  `.with*` builders mirror the Cosmos sibling's configuration shape WITHOUT
//  SwiftUI `@Entry`/`@Observable`. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//
//  NOTE on `environment`: the contract specified `CKContainer.Environment`, but
//  that type does NOT exist as a Swift type in the Xcode 27 Beta 3 SDK —
//  verified across the iOS and macOS `CloudKit.swiftmodule` interfaces (zero
//  occurrences of "Environment") and the CloudKit Objective-C headers (the
//  iCloud "environment" is a Development/Production entitlement on the
//  provisioning profile, not a runtime enum). The three database scopes a sync
//  engine actually selects between — private / public / shared — are exposed via
//  `CKContainer.privateCloudDatabase` / `.publicCloudDatabase` /
//  `.sharedCloudDatabase`, backed by the `CKDatabaseScope` C enum. So Nebula
//  owns ``NebulaCloudKitEnvironment`` (a Sendable, Equatable enum with the three
//  scope cases) and maps it to the database property at the CloudKit boundary in
//  ``NebulaCloudKitSyncEngine``. This keeps the public Nebula surface free of an
//  Apple type that does not exist while preserving the contract's intent
//  (`.private` default, Sendable, Equatable).
//

import Foundation

/// The CloudKit database scope a sync engine targets.
///
/// A Nebula-owned `Sendable`, `Equatable` sum type with the three CloudKit
/// database scopes. Nebula owns this type rather than reusing an Apple type
/// because the contract's `CKContainer.Environment` does not exist as a Swift
/// type in the Xcode 27 Beta 3 SDK (verified against the
/// `CloudKit.swiftmodule` interfaces and the Objective-C headers). The iCloud
/// "environment" (Development / Production) is an entitlement on the app's
/// provisioning profile, not a runtime enum; the runtime database selection a
/// sync engine performs is the scope — private / public / shared — exposed via
/// `CKContainer.privateCloudDatabase` / `.publicCloudDatabase` /
/// `.sharedCloudDatabase`. ``NebulaCloudKitSyncEngine`` maps this enum to the
/// matching `CKContainer` database property at the CloudKit boundary.
public enum NebulaCloudKitEnvironment: Sendable, Equatable {
    /// The user's private database (per-user, requires an iCloud account).
    case `private`
    /// The app's public database (read access without an account; writes
    /// require an iCloud account).
    case `public`
    /// The shared database (records other iCloud users have shared with the
    /// current user).
    case shared
}

/// The Nebula CloudKit sync configuration.
///
/// A `Sendable`, `Equatable` value (all four fields are plain `Sendable`,
/// `Equatable` values — no `@Sendable` closure is stored, so unlike
/// ``NebulaMetricsConfiguration`` / ``NebulaMeasureConfiguration`` this config
/// IS `Equatable`) describing how a ``NebulaCloudKitSyncEngine`` resolves its
/// `CKContainer` / `CKDatabase`:
/// - ``containerIdentifier`` is the iCloud container identifier (`nil` →
///   `CKContainer.default()`, the container matching the app's
///   `com.apple.developer.icloud-container-identifiers` entitlement);
/// - ``environment`` selects the database scope
///   (``NebulaCloudKitEnvironment``-`.private` by default);
/// - ``zoneName`` is the record-zone name used by the observability suite
///   (`"NebulaObservability"` by default);
/// - ``isEnabled`` gates whether ``NebulaCloudKitSyncEngine/sendChanges()``
///   and ``NebulaCloudKitSyncEngine/fetchChanges()`` actually drive the
///   underlying `CKSyncEngine`. `false` by default — CloudKit sync is opt-in (a
///   foundation does not implicitly hit the network).
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct + fluent
/// `.with*` builders — but with no SwiftUI `@Entry`/`@Observable`: a foundation
/// does not own UI-thread affinity, so configurations are constructed and
/// passed explicitly.
public struct NebulaCloudKitConfiguration: Sendable, Equatable {
    /// The iCloud container identifier, or `nil` to use `CKContainer.default()`.
    public let containerIdentifier: String?
    /// The database scope to sync against. Defaults to
    /// ``NebulaCloudKitEnvironment/private``.
    public let environment: NebulaCloudKitEnvironment
    /// The record-zone name used by the observability suite. Defaults to
    /// `"NebulaObservability"`.
    public let zoneName: String
    /// Whether sync is enabled. `false` by default — CloudKit sync is opt-in.
    public let isEnabled: Bool

    /// Creates a CloudKit sync configuration.
    ///
    /// - Parameters:
    ///   - containerIdentifier: The iCloud container identifier, or `nil` to
    ///     use `CKContainer.default()`. Defaults to `nil`.
    ///   - environment: The database scope. Defaults to `.private`.
    ///   - zoneName: The record-zone name. Defaults to `"NebulaObservability"`.
    ///   - isEnabled: Whether sync is enabled. Defaults to `false` (opt-in).
    public init(
        containerIdentifier: String? = nil,
        environment: NebulaCloudKitEnvironment = .private,
        zoneName: String = "NebulaObservability",
        isEnabled: Bool = false
    ) {
        self.containerIdentifier = containerIdentifier
        self.environment = environment
        self.zoneName = zoneName
        self.isEnabled = isEnabled
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive). Override pieces with the
    /// `.with*` builders.
    public static let `default` = NebulaCloudKitConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the container identifier replaced (`nil` →
    /// `CKContainer.default()`).
    public func withContainerIdentifier(_ containerIdentifier: String?) -> NebulaCloudKitConfiguration {
        .init(containerIdentifier: containerIdentifier, environment: environment, zoneName: zoneName, isEnabled: isEnabled)
    }

    /// Returns a copy with the environment (database scope) replaced.
    public func withEnvironment(_ environment: NebulaCloudKitEnvironment) -> NebulaCloudKitConfiguration {
        .init(containerIdentifier: containerIdentifier, environment: environment, zoneName: zoneName, isEnabled: isEnabled)
    }

    /// Returns a copy with the zone name replaced.
    public func withZoneName(_ zoneName: String) -> NebulaCloudKitConfiguration {
        .init(containerIdentifier: containerIdentifier, environment: environment, zoneName: zoneName, isEnabled: isEnabled)
    }

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaCloudKitConfiguration {
        .init(containerIdentifier: containerIdentifier, environment: environment, zoneName: zoneName, isEnabled: isEnabled)
    }
}
