//
//  NebulaRemoteFeatureFlags.swift
//  Nebula
//
//  Wave N14 — Clean Architecture toolkit. The remote feature-flag port: refines
//  ``NebulaFeatureFlags`` with a `refresh() async throws` requirement. A
//  conformer serves the **last-fetched** flag values through ``value(forKey:)``
//  (the base-port requirement) and refreshes them on demand. There is no
//  Apple-native remote-config API, and `dependencies: []` forbids Firebase /
//  LaunchDarkly, so the backend is app-supplied — the app conforms this port
//  with its own fetcher. The composite (``NebulaCompositeFeatureFlags``) never
//  calls `refresh`; the app does, so a throwing signature is honest about fetch
//  failure (a remote fetch failing is the whole point of local fallback). See
//  vault/03-padroes/nebula-feature-flags.md.
//

import Foundation

/// A remote feature-flag port: ``NebulaFeatureFlags`` plus a `refresh()`
/// requirement.
///
/// The conformer serves the **last-fetched** flag values through
/// ``NebulaFeatureFlags/value(forKey:)`` (the base-port requirement) and updates its cache when
/// ``refresh()`` is called. The backend is app-supplied — `dependencies: []`
/// forbids Firebase / LaunchDarkly, so an app conforms this port with its own
/// fetcher (a `URLSession` against a remote-config endpoint, a `NebulaGateway`
/// call, anything).
///
/// `refresh()` is `async throws`: a remote fetch can fail, and a failed
/// refresh should leave the cached values unchanged (the conformer's
/// responsibility) so reads keep resolving to the last good fetch. The
/// ``NebulaCompositeFeatureFlags`` never calls `refresh` — the app drives
/// refresh at its own cadence (launch, app foreground, a timer) and the
/// composite simply reads the cache, so a throwing signature costs the
/// composite nothing and is honest about the network.
public protocol NebulaRemoteFeatureFlags: NebulaFeatureFlags {

    /// Re-fetches flag values from the backend and updates the cache.
    ///
    /// Throws on failure; a failed refresh leaves the cached values unchanged
    /// so reads keep resolving to the last good fetch.
    func refresh() async throws
}