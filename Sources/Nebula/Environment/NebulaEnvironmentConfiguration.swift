//
//  NebulaEnvironmentConfiguration.swift
//  Nebula
//
//  Wave N13 — the environment *configuration* value: the resolved
//  ``NebulaEnvironment`` plus the app's per-environment base URLs and string
//  overrides. Mirrors the cross-cutting configuration-struct family
//  (`NebulaLogConfiguration` / `NebulaErrorConfiguration` / `NebulaStandards` /
//  `NebulaMeasureConfiguration`): `Sendable` value struct + fluent `.with*`
//  builders + `static let default` once-token, no SwiftUI `@Entry`/`@Observable`.
//  Named `…Configuration` (value) paired with `NebulaEnvironmentConfig` (accessor)
//  to follow the family's `Configuration`/`Config` split and avoid the
//  `NebulaEnvironmentConfigConfig` stutter.
//
//  `Sendable`-only (NOT `Equatable`) — follows the family posture: the other
//  structs reject `Equatable` because their `@Sendable` handler closures are not
//  `Equatable`; this struct carries no handler but keeps the posture for
//  consistency. All fields are pure values that derive `Sendable` (no
//  `@unchecked`).
//
//  See vault/03-padroes/nebula-environment.md. Foundation-only; no UIKit/SwiftUI/
//  SwiftData. 5-platform, below-floor APIs only.
//

import Foundation

/// The environment configuration: the resolved environment plus per-environment
/// base URLs and string overrides.
///
/// A `Sendable` value struct — the fifth of Nebula's cross-cutting configuration
/// contracts (alongside ``NebulaLogConfiguration``, ``NebulaErrorConfiguration``,
/// ``NebulaStandards``, ``NebulaMeasureConfiguration``). It carries no
/// `@Sendable` handler (the environment is resolved data, not a fan-out path),
/// so it follows the family's `Sendable`-only posture for consistency.
///
/// Construct explicitly and pass it in, or read it process-wide via
/// ``NebulaEnvironmentConfig``. The app supplies all base URLs and overrides —
/// Nebula ships no built-in URLs. Resolve a URL with ``baseURL(for:)`` and an
/// override string with ``value(for:)``.
public struct NebulaEnvironmentConfiguration: Sendable {
    /// The environment this configuration is bound to.
    public let environment: NebulaEnvironment
    /// Per-environment base URLs. The app supplies these; Nebula ships none.
    public let baseURLs: [NebulaEnvironment: URL]
    /// String overrides the app resolves via ``value(for:)`` (e.g. feature-flag
    /// defaults, display strings keyed by environment).
    public let overrides: [String: String]

    /// Creates an environment configuration.
    ///
    /// All fields default to empty/``NebulaEnvironment/default`` so
    /// `NebulaEnvironmentConfiguration()` is the no-op default; populate with
    /// the `.with*` builders (or the `init`).
    public init(
        environment: NebulaEnvironment = .default,
        baseURLs: [NebulaEnvironment: URL] = [:],
        overrides: [String: String] = [:]
    ) {
        self.environment = environment
        self.baseURLs = baseURLs
        self.overrides = overrides
    }

    /// The default configuration (``NebulaEnvironment/default``, no URLs, no
    /// overrides). Idempotent via the once-token `static let` initializer
    /// side-effect (no lock primitive). Override pieces with the `.with*`
    /// builders.
    public static let `default` = NebulaEnvironmentConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the environment replaced (URLs/overrides unchanged).
    public func withEnvironment(_ environment: NebulaEnvironment) -> NebulaEnvironmentConfiguration {
        NebulaEnvironmentConfiguration(environment: environment, baseURLs: baseURLs, overrides: overrides)
    }

    /// Returns a copy with the base URLs replaced (environment/overrides unchanged).
    public func withBaseURLs(_ baseURLs: [NebulaEnvironment: URL]) -> NebulaEnvironmentConfiguration {
        NebulaEnvironmentConfiguration(environment: environment, baseURLs: baseURLs, overrides: overrides)
    }

    /// Returns a copy with the overrides replaced (environment/URLs unchanged).
    public func withOverrides(_ overrides: [String: String]) -> NebulaEnvironmentConfiguration {
        NebulaEnvironmentConfiguration(environment: environment, baseURLs: baseURLs, overrides: overrides)
    }

    // MARK: - Resolution

    /// Returns the base URL registered for `environment`, or `nil` if unset.
    ///
    /// The app supplies all URLs; Nebula ships none, so an unregistered
    /// environment yields `nil` rather than a fallback. The parameter is
    /// independent of ``environment`` so a caller can resolve any environment's
    /// URL (e.g. an admin tool listing all endpoints).
    public func baseURL(for environment: NebulaEnvironment) -> URL? {
        baseURLs[environment]
    }

    /// Returns the override string for `key`, or `nil` if absent.
    public func value(for key: String) -> String? {
        overrides[key]
    }
}