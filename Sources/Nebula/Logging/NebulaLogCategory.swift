//
//  NebulaLogCategory.swift
//  Nebula
//
//  A String-rawValue log category struct with presets. `os.Logger` takes a
//  plain `String` category, so a flexible struct (not a closed enum) lets
//  consumers add categories without forking an enum. See
//  vault/01-fundamentos/nebula-logging.md.
//

import Foundation

/// A Nebula log category.
///
/// A `Sendable` `ExpressibleByStringLiteral` struct backed by a `String` raw
/// value. Mirrors the `subsystem`/`category` split `os.Logger` uses: the
/// subsystem (typically the consumer's bundle identifier) scopes logs in
/// Console.app, and the category distinguishes parts of that subsystem.
///
/// Because `os.Logger` accepts a plain `String` category, Nebula models the
/// category as an extensible struct rather than a closed enum — consumers can
/// invent categories via a string literal without a library release:
///
/// ```swift
/// let logger = NebulaLogger(subsystem: "com.acme.app", category: .networking)
/// let custom: NebulaLogCategory = "background-sync"
/// ```
public struct NebulaLogCategory: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The underlying `String` passed to `os.Logger(subsystem:category:)`.
    public let rawValue: String

    /// Creates a category from its raw string value.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    // MARK: - Presets

    /// Networking / I/O categories (HTTP, sockets, downloads).
    public static let networking: NebulaLogCategory = "networking"
    /// Persistence categories (Core Data, files, caches).
    public static let persistence: NebulaLogCategory = "persistence"
    /// Formatting / standards categories (FormatStyle, Measurement, lists).
    public static let formatting: NebulaLogCategory = "formatting"
    /// Measurement categories (Duration/Clock timing, signposts).
    public static let measure: NebulaLogCategory = "measure"
    /// Concurrency categories (actors, tasks, synchronization).
    public static let concurrency: NebulaLogCategory = "concurrency"
    /// The default, unscoped category.
    public static let general: NebulaLogCategory = "general"
}