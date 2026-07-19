//
//  NebulaRegistry.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The explicit-injection registry: a
//  `Sendable` struct wrapping a snapshot of ``NebulaRegistryConfiguration`` so a
//  dependency graph can be passed by constructor (the testable path). The
//  process-wide path lives in ``NebulaRegistryConfig``. Decision #5 — both global
//  AND explicit param. See vault/03-padroes/nebula-registry-di.md.
//

import Foundation

/// A `Sendable` registry wrapping a snapshot of ``NebulaRegistryConfiguration``,
/// for explicit constructor-injection (the testable DI path).
///
/// `NebulaRegistry` is the explicit-injection surface: build a
/// ``NebulaRegistryConfiguration``, hand it to a `NebulaRegistry`, and pass the
/// registry down a dependency graph. The process-wide convenience lives in
/// ``NebulaRegistryConfig``. Both paths share ``NebulaRegistryConfiguration`` as
/// the value type (decision #5). `Sendable` is derived (the wrapped config is
/// `Sendable`).
///
/// ```swift
/// let cfg = NebulaRegistryConfiguration()
///     .withFactory(for: "com.acme.account.repo") { AccountRepository() }
/// let registry = NebulaRegistry(cfg)
/// let repo = registry.resolve("com.acme.account.repo", as: AccountRepository.self)
/// ```
public struct NebulaRegistry: Sendable {
    /// The wrapped configuration snapshot.
    public let configuration: NebulaRegistryConfiguration

    /// Creates a registry from a configuration snapshot.
    public init(_ configuration: NebulaRegistryConfiguration) {
        self.configuration = configuration
    }

    /// Creates an empty registry.
    public init() {
        self.configuration = .default
    }

    /// Resolves `key` to a typed instance via the bound factory, or `nil` when
    /// the key is unbound or the factory returns a value not castable to `T`.
    public func resolve<T>(_ key: NebulaRegistryKey, as type: T.Type = T.self) -> T? {
        configuration.make(key) as? T
    }
}