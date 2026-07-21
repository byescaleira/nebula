//
//  NebulaEnvironment.swift
//  Nebula
//
//  Wave N13 — Environment value + reader pattern. Apple provides no Foundation
//  `Environment` value type: the idiom is the Xcode `Configuration` build
//  setting (`Debug`/`Release`/custom) fed from `.xcconfig` + schemes and written
//  into the app's `Info.plist` (a key, conventionally `Configuration`, set from
//  `$(CONFIGURATION)`). Nebula ships the *value + reader* — a closed enum that
//  round-trips that string, plus a ``fromBundle(_:key:)`` builder that reads the
//  key and resolves it safely. The `.xcconfig`/scheme/`Info.plist` wiring itself
//  is app-tier (the consuming app's Xcode project) and is explicitly deferred.
//
//  `Bundle` is `@unchecked Sendable` (Sendable on the `.v26` floor). The reader
//  is a pure function with no shared mutable state — no `Mutex` is needed. The
//  load-bearing Sendability step is casting `object(forInfoDictionaryKey:)`'s
//  `Any?` to `String?` *before* it is stored or returned: `infoDictionary`
//  values are `Any` and are NOT Sendable, so an un-cast `Any` must never cross
//  an isolation boundary.
//
//  See vault/03-padroes/nebula-environment.md for the shipped design. Foundation-
//  only; no UIKit, no SwiftUI, no SwiftData. 5-platform, below-floor APIs only.
//

import Foundation

/// The environment a Nebula-using app build is running in.
///
/// A closed `String`-backed enum that round-trips the value an app writes into
/// its `Info.plist` (conventionally the `Configuration` key, fed from
/// `$(CONFIGURATION)` via `.xcconfig` + schemes). Apple has no Foundation
/// `Environment` value type — the Xcode build-configuration machinery is the
/// idiom — so Nebula supplies the value plus ``fromBundle(_:key:)`` to read it.
///
/// `Sendable`, `Equatable`, `Hashable`, and `CaseIterable` are all **derived**
/// (pure value, no `@unchecked Sendable`). ``default`` is ``production``: an
/// app that never wires the key resolves to the safest posture rather than
/// accidentally talking to a development URL.
public enum NebulaEnvironment: String, Sendable, Equatable, Hashable, CaseIterable, CustomStringConvertible {
    /// The development environment (local/debug builds).
    case development
    /// The staging environment (pre-release/QA builds).
    case staging
    /// The production environment (App Store/release builds).
    case production

    /// The developer-facing label (the raw `Info.plist` string).
    public var description: String { rawValue }

    /// The safe default when no environment is configured: ``production``.
    ///
    /// An app that never wires the `Configuration` key resolves to ``production``
    /// so it never accidentally reaches a development or staging service. This is
    /// the value ``fromBundle(_:key:)`` returns on an absent or unparseable key.
    public static let `default`: NebulaEnvironment = .production

    /// Resolves the environment from a bundle's `Info.plist` key.
    ///
    /// Reads `key` (conventionally `"Configuration"`, the value Xcode writes from
    /// `$(CONFIGURATION)`) via `object(forInfoDictionaryKey:)`, casts the `Any?`
    /// to `String?` **before** it crosses isolation (the `infoDictionary` values
    /// are `Any` and not Sendable), and maps it through `init(rawValue:)`.
    ///
    /// Safe-fail-to-``production``: an absent key, an unknown string, or a
    /// non-`String` value all resolve to ``default`` — the function never
    /// returns `nil`, because an app always has *an* environment. The reader is
    /// a pure function over the Sendable `Bundle`; there is no shared mutable
    /// state, so no `Mutex` is involved.
    ///
    /// - Parameters:
    ///   - bundle: The bundle whose `Info.plist` is read. Defaults to
    ///     `Bundle.main` (the common case; pass an explicit bundle for tests or
    ///     extensions).
    ///   - key: The `Info.plist` key holding the configuration string. Defaults
    ///     to `"Configuration"` (the `$(CONFIGURATION)` idiom).
    /// - Returns: The resolved environment, or ``default`` (``production``) if
    ///     the key is absent, unparseable, or non-`String`.
    public static func fromBundle(
        _ bundle: Bundle = .main,
        key: String = "Configuration"
    ) -> NebulaEnvironment {
        // Cast Any -> String BEFORE crossing isolation: infoDictionary values
        // are `Any` and are not Sendable. A `let String?` is safe to return.
        let raw = bundle.object(forInfoDictionaryKey: key) as? String
        return raw.flatMap(NebulaEnvironment.init(rawValue:)) ?? .default
    }
}