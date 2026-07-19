//
//  NebulaRegistryKey.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A registry key: an open struct (mirror
//  ``NebulaLogCategory``) so consumers invent keys via a string literal without
//  a library release. `Sendable`, `Hashable`, `ExpressibleByStringLiteral`.
//  See vault/03-padroes/nebula-registry-di.md.
//

import Foundation

/// A key identifying a factory binding in a ``NebulaRegistry``.
///
/// An open `Sendable` `ExpressibleByStringLiteral` struct backed by a `String`
/// raw value (mirrors ``NebulaLogCategory``). Consumers invent keys via a
/// string literal without a library release:
///
/// ```swift
/// let key: NebulaRegistryKey = "com.acme.account.repository"
/// ```
public struct NebulaRegistryKey: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The underlying key string.
    public let rawValue: String

    /// Creates a key from its raw string value.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    // MARK: - Common presets

    /// A repository binding.
    public static let repository: NebulaRegistryKey = "repository"
    /// A gateway binding.
    public static let gateway: NebulaRegistryKey = "gateway"
    /// A use case binding.
    public static let useCase: NebulaRegistryKey = "use-case"
}