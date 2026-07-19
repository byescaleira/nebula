//
//  NebulaRepositoryError.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A repository-layer error: a persistence
//  / data-access failure surfaced by a ``NebulaRepository``. Carries a coarse
//  open-struct ``Kind`` (with presets, mirroring ``NebulaLogCategory``) so
//  consumers invent repository error categories without a library release, a
//  fine free-form `code`, a ``Source`` (local/remote/unknown), and the entity
//  type/id the error concerns. Bridges to the closed ``NebulaError/Kind`` via
//  the caller-picked ``toNebulaError(kind:)``. Derives `Sendable`, `Equatable`,
//  `Hashable`. See vault/03-padroes/nebula-repository.md and nebula-domain-error.md.
//

import Foundation

/// A Clean Architecture **repository-layer** error: a persistence / data-access
/// failure surfaced by a ``NebulaRepository``.
///
/// Repository errors carry more structure than domain or validation errors
/// because the repository is the infrastructure boundary: a ``Source``
/// (local/remote/unknown), the entity type and id the error concerns, and a
/// coarse open-struct ``Kind`` (with presets) plus a fine free-form `code`.
///
/// `Sendable`, `Equatable`, and `Hashable` are derived from its fields, so a
/// test can assert a specific repository error:
///
/// ```swift
/// #expect(throws: NebulaRepositoryError.notFound("Account", id: "abc")) {
///     try await repo.find(id: id).get()
/// }
/// ```
public struct NebulaRepositoryError: NebulaFailure, Equatable, Hashable {

    /// Where the repository error originated.
    public enum Source: Sendable, Equatable, Hashable, CaseIterable {
        /// A local store (Core Data, SQLite, in-memory) failure.
        case local
        /// A remote (network/API) failure.
        case remote
        /// The source is unknown or does not fit local/remote.
        case unknown
    }

    /// A coarse, open-struct repository error category (extensible by a string
    /// literal without a library release, mirroring ``NebulaLogCategory``).
    public struct Kind: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
        /// The underlying category string.
        public let rawValue: String

        /// Creates a kind from its raw string.
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// Creates a kind from a string literal.
        public init(stringLiteral value: String) { self.rawValue = value }
        /// Mirrors the raw value.
        public var description: String { rawValue }

        // MARK: - Presets (mirror NebulaLogCategory.swift:46-56)

        /// The entity was not found.
        public static let notFound: Kind = "not-found"
        /// The entity already exists (duplicate identity).
        public static let alreadyExists: Kind = "already-exists"
        /// The store failed to read/write (a generic store-level failure).
        public static let storeFailure: Kind = "store-failure"
        /// Mapping to/from a domain entity failed.
        public static let mapping: Kind = "mapping"
        /// A persistence constraint was violated (unique, foreign key, …).
        public static let constraintViolation: Kind = "constraint-violation"
        /// The operation was cancelled.
        public static let cancelled: Kind = "cancelled"
        /// Anything else.
        public static let unknown: Kind = "unknown"
    }

    /// The coarse category.
    public var kind: Kind
    /// A fine free-form code (defaults to the coarse kind's raw value).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Where the error originated.
    public var source: Source
    /// The entity type name the error concerns, if any.
    public var entityType: String?
    /// The entity id (stringified) the error concerns, if any.
    public var id: String?
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed, reusing ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a repository error.
    public init(
        kind: Kind,
        code: String? = nil,
        message: String,
        source: Source = .unknown,
        entityType: String? = nil,
        id: String? = nil,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.kind = kind
        self.code = code ?? kind.rawValue
        self.message = message
        self.source = source
        self.entityType = entityType
        self.id = id
        self.metadata = metadata
        self.underlying = underlying
    }

    /// The default ``NebulaError/Kind`` a repository error maps to. A
    /// constraint violation is `.validation`; a mapping failure is `.decoding`;
    /// a remote source is `.network`; otherwise `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .constraintViolation: return .validation
        case .mapping:              return .decoding
        default:                    return source == .remote ? .network : .unknown
        }
    }

    /// Bridges to a ``NebulaError`` under `kind`. The coarse kind, code, source,
    /// entity type, and id are preserved as metadata.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        meta["NebulaSource"] = String(describing: source)
        if let entityType { meta["NebulaEntityType"] = entityType }
        if let id { meta["NebulaEntityId"] = id }
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaRepositoryError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A not-found error.
    public static func notFound(_ message: String = "Entity not found", entityType: String? = nil, id: String? = nil) -> NebulaRepositoryError {
        .init(kind: .notFound, message: message, source: .local, entityType: entityType, id: id)
    }

    /// An already-exists error (duplicate identity).
    public static func alreadyExists(_ message: String = "Entity already exists", entityType: String? = nil, id: String? = nil) -> NebulaRepositoryError {
        .init(kind: .alreadyExists, message: message, source: .local, entityType: entityType, id: id)
    }

    /// A store-level read/write failure.
    public static func storeFailure(_ message: String = "Store failure", source: Source = .local, entityType: String? = nil, underlying: NebulaError.Box? = nil) -> NebulaRepositoryError {
        .init(kind: .storeFailure, message: message, source: source, entityType: entityType, underlying: underlying)
    }

    /// A mapping (to/from domain entity) failure.
    public static func mapping(_ message: String = "Mapping failure", source: Source = .local, underlying: NebulaError.Box? = nil) -> NebulaRepositoryError {
        .init(kind: .mapping, message: message, source: source, underlying: underlying)
    }

    /// A persistence-constraint violation.
    public static func constraintViolation(_ message: String = "Constraint violation", entityType: String? = nil, id: String? = nil) -> NebulaRepositoryError {
        .init(kind: .constraintViolation, message: message, source: .local, entityType: entityType, id: id)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "Operation cancelled") -> NebulaRepositoryError {
        .init(kind: .cancelled, message: message, source: .unknown)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown repository error", source: Source = .unknown, entityType: String? = nil, underlying: NebulaError.Box? = nil) -> NebulaRepositoryError {
        .init(kind: .unknown, message: message, source: source, entityType: entityType, underlying: underlying)
    }
}