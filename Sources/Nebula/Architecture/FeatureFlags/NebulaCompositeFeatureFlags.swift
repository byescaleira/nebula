//
//  NebulaCompositeFeatureFlags.swift
//  Nebula
//
//  Wave N14 — Clean Architecture toolkit. The priority-ordered composite: a
//  `Sendable` **struct** holding an immutable `[any NebulaFeatureFlags]` and
//  resolving ``value(forKey:)`` by first-non-nil across the sources in order.
//  The app wires the priority — conventionally `[localOverrides, remote,
//  builtInDefaults]` — so the composite is a generic first-non-nil resolver,
//  not a hardcoded local/remote/defaults ladder. `Sendable` by derived
//  conformance (`[any NebulaFeatureFlags]` where the protocol is `: Sendable`),
//  **no `@unchecked`**, the shape mirroring ``NebulaHTTPInterceptorChain``.
//  ``withSource(_:)`` appends and returns a new composite (immutable after
//  init). See vault/03-padroes/nebula-feature-flags.md.
//

import Foundation

/// A priority-ordered composite of ``NebulaFeatureFlags`` sources.
///
/// `Sendable` by derived conformance — the stored `[any NebulaFeatureFlags]` is
/// `Sendable` (the protocol requires it); **no `@unchecked`**. Not `Equatable`
/// (the flag protocol is not `Equatable`). Use ``withSource(_:)`` to append and
/// build a new composite (immutable after init, mirroring
/// ``NebulaHTTPInterceptorChain``).
///
/// ``value(forKey:)`` resolves by **first-non-nil**: the first source, in
/// order, that holds the key wins. The composite is a generic resolver — it
/// does not hardcode local/remote/defaults; the app wires the priority
/// conventionally as `[localOverrides, remote, builtInDefaults]`, so a local
/// override shadows the remote fetch, and the remote shadows the built-in
/// defaults. Conforms to ``NebulaFeatureFlags``, so the typed accessors
/// (`bool`/`string`/`number`/`json`) flow through the composite for free.
///
/// ```swift
/// let local = NebulaLocalFeatureFlags()
/// let remote = AcmeRemoteFeatureFlags()   // conforms NebulaRemoteFeatureFlags
/// let defaults = NebulaLocalFeatureFlags(["theme": .string("system")])
/// let flags = NebulaCompositeFeatureFlags([local, remote, defaults])
///
/// local.setValue(.string("dark"), forKey: "theme")
/// flags.string(forKey: "theme")   // "dark" — the local override wins
/// ```
public struct NebulaCompositeFeatureFlags: NebulaFeatureFlags {

    /// The sources, consulted in order (first-non-nil wins).
    public let sources: [any NebulaFeatureFlags]

    /// Creates a composite. Defaults to empty (an empty composite resolves
    /// every key to `nil`).
    public init(_ sources: [any NebulaFeatureFlags] = []) {
        self.sources = sources
    }

    /// Returns a new composite with `source` appended.
    public func withSource(_ source: any NebulaFeatureFlags) -> NebulaCompositeFeatureFlags {
        NebulaCompositeFeatureFlags(sources + [source])
    }

    public func value(forKey key: String) -> NebulaFlagValue? {
        for source in sources {
            if let value = source.value(forKey: key) { return value }
        }
        return nil
    }
}