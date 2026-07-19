//
//  NebulaRegistryConfiguration.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The registry configuration: a Sendable
//  value holding `@Sendable () -> Any` factories keyed by ``NebulaRegistryKey``.
//  Sendable ONLY (NOT `Equatable` — the stored `@Sendable` closures are not
//  `Equatable`, mirroring ``NebulaErrorConfiguration``). See
//  vault/03-padroes/nebula-registry-di.md.
//

import Foundation

/// A registry configuration: a map of ``NebulaRegistryKey`` to transient
/// `@Sendable () -> Any` factories.
///
/// `Sendable` ONLY (NOT `Equatable` — it stores `@Sendable` closures, which are
/// not `Equatable`; synthesized `Equatable` is rejected, mirroring
/// ``NebulaErrorConfiguration``). Factories are **transient**: each
/// ``NebulaRegistry/resolve(_:as:)`` call invokes the factory afresh.
///
/// ```swift
/// let cfg = NebulaRegistryConfiguration()
///     .withFactory(for: "com.acme.account.repo") { AccountRepository() }
/// ```
public struct NebulaRegistryConfiguration: Sendable {
    /// A transient `@Sendable` factory.
    public typealias Factory = @Sendable () -> Any

    /// The factory bindings.
    public let factories: [NebulaRegistryKey: Factory]

    /// Creates a configuration with the given factory bindings (empty by default).
    public init(factories: [NebulaRegistryKey: Factory] = [:]) {
        self.factories = factories
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive).
    public static let `default` = NebulaRegistryConfiguration()

    /// Returns a copy with `factory` bound to `key` (replacing any prior binding).
    public func withFactory(for key: NebulaRegistryKey, _ factory: @escaping Factory) -> NebulaRegistryConfiguration {
        var updated = factories
        updated[key] = factory
        return .init(factories: updated)
    }

    /// Returns a copy with the binding for `key` removed (if present).
    public func removingFactory(for key: NebulaRegistryKey) -> NebulaRegistryConfiguration {
        var updated = factories
        updated.removeValue(forKey: key)
        return .init(factories: updated)
    }

    /// Invokes the factory bound to `key`, or returns `nil` when unbound.
    public func make(_ key: NebulaRegistryKey) -> Any? {
        guard let factory = factories[key] else { return nil }
        return factory()
    }
}