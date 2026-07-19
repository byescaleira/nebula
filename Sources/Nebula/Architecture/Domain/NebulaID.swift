//
//  NebulaID.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A phantom-typed identity value: a
//  `NebulaID<Account>` cannot be confused with a `NebulaID<Order>` even when
//  both wrap a `UUID`. `Sendable`, `Hashable` (and thus `Equatable`) are
//  derived from the `UUID` raw value; ``NebulaValue`` and `Identifiable` are
//  conformed here so an ID is itself a value and its own identity. The raw
//  representation is fixed to `UUID` — the common case; entities with non-UUID
//  identities use their own `Sendable & Hashable` `ID` type (the toolkit's
//  ``NebulaEntity`` only requires `ID: Sendable, Hashable`, not `NebulaID`).
//  `Codable` is intentionally not conformed on the type so the raw encoding is
//  the entity's decision. See vault/03-padroes/nebula-validation-invariants.md.
//
//  NOTE: a generic-parameter *default* (e.g. `<Entity, Raw: Sendable & Hashable
//  = UUID>`) is not supported on a `struct` declaration on this toolchain
//  (verified: `swiftc -parse` rejects it for both structs and typealiases), so
//  the raw type is pinned to `UUID` rather than defaulted.
//

import Foundation

/// A phantom-typed identity value for a ``NebulaEntity``, backed by a `UUID`.
///
/// The phantom type parameter `Entity` is never stored — it exists only in the
/// type system so that a `NebulaID<Account>` and a `NebulaID<Order>` are
/// distinct types even though both wrap a `UUID`. Because `Entity` is not
/// stored, it does **not** need to be `Sendable`.
///
/// `Sendable`, `Equatable`, and `Hashable` are derived from the `UUID` raw
/// value. `NebulaID` conforms to ``NebulaValue`` and to `Identifiable` (its
/// `id` is itself), so an ID value can stand in wherever a value or an
/// `Identifiable` is expected. `Codable` is intentionally **not** conformed on
/// the type: the raw encoding (a `UUID` vs. a string vs. a tagged int) is the
/// entity's decision, so entities opt in by conforming themselves.
///
/// ```swift
/// struct Account: NebulaEntity {
///     typealias ID = NebulaID<Account>
///     let id: ID
///     let balance: Decimal
/// }
///
/// let id = Account.ID()              // random UUID
/// // let x: Order.ID = id            // ✗ type mismatch — phantom protects
/// ```
///
/// For a non-UUID identity (e.g. a server-assigned `Int` key), define a custom
/// `ID` type that is `Sendable & Hashable` and use it as the entity's
/// `typealias ID` — ``NebulaEntity`` only constrains `ID` to `Sendable, Hashable`.
public struct NebulaID<Entity>: NebulaValue, CustomStringConvertible, Identifiable {

    /// The underlying identity value.
    public let rawValue: UUID

    /// Creates an identity from its raw `UUID`.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates an identity by adopting `rawValue` (labeled form for call-site
    /// clarity when the raw value is the natural argument).
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates a new identity with a random `UUID`.
    public init() {
        self.rawValue = UUID()
    }

    /// `Identifiable.id` — an ID is its own identity.
    public var id: Self { self }

    /// A debug-friendly description mirroring the raw `UUID`.
    public var description: String { rawValue.uuidString }
}