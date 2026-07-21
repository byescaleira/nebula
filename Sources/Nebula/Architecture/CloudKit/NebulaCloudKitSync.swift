//
//  NebulaCloudKitSync.swift
//  Nebula
//
//  Wave N19c — CloudKit glue slice. The CloudKit sync port: a `Sendable`
//  protocol with two low-level async requirements (`sendChanges()` /
//  `fetchChanges()`), mirroring the `NebulaMetrics` / `NebulaPreferences` port
//  shape (a tiny low-level contract an app or adapter conforms to). A concrete
//  `CKSyncEngine`-backed conformer is ``NebulaCloudKitSyncEngine`` — *another
//  conformer*, not new architecture. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import _Concurrency

/// A `Sendable` CloudKit sync port.
///
/// The architecture seam for driving CloudKit record sync. The contract is
/// intentionally tiny — two `async throws` requirements — so an app can swap the
/// backend (a `CKSyncEngine`-backed conformer for production, a test double for
/// tests, a no-op stub when CloudKit is disabled) without reimplementing sync
/// ergonomics.
///
/// - ``sendChanges()`` — push pending local record changes to CloudKit;
/// - ``fetchChanges()`` — pull pending server record changes from CloudKit.
///
/// Both are `async throws` — CloudKit sync is fallible (network, account,
/// quota). A conformer may no-op when its configuration is disabled (the
/// ``NebulaCloudKitSyncEngine`` precedent).
public protocol NebulaCloudKitSync: Sendable {

    /// Pushes pending local record changes to CloudKit. Throws on network,
    /// account, or quota failure.
    func sendChanges() async throws

    /// Pulls pending server record changes from CloudKit. Throws on network,
    /// account, or quota failure.
    func fetchChanges() async throws
}

public extension NebulaCloudKitSync {

    /// Pushes pending local changes and then pulls pending server changes in a
    /// single call — the canonical "sync now" ergonomics built on the two
    /// primitive requirements. Every conformer (``NebulaCloudKitSyncEngine``, a
    /// test double, a disabled stub) inherits this for free, mirroring how
    /// ``NebulaMetrics`` / ``NebulaAnalytics`` layer ergonomics on their
    /// primitive requirements. `sendChanges()` runs first so a freshly-recorded
    /// batch is uploaded before the pull reconciles server state.
    func sync() async throws {
        try await sendChanges()
        try await fetchChanges()
    }
}
