//
//  AuroraEntityMapping.swift
//  Aurora
//
//  Wave N3 — the `@Model`↔Sendable entity mapping that bridges SwiftData's
//  non-`Sendable` `@Model`/`ModelContext` to Nebula's `Sendable` `NebulaEntity`
//  DTOs. The app conforms this per `@Model` type; ``AuroraRepository`` is
//  generic over a conforming `Mapping` and does the rest. The mapping is
//  type-level (static methods) so the repository holds no per-instance mapping
//  state — only the `@ModelActor`-synthesized `ModelContext`. See
//  vault/03-padroes/nebula-data-network-architecture.md.
//

import Foundation
import SwiftData
import Nebula

/// A type-level mapping between a SwiftData `@Model` and a Nebula
/// ``NebulaEntity`` DTO, used by ``AuroraRepository``.
///
/// SwiftData's `@Model` classes and `ModelContext` are **not** `Sendable`
/// (verified against the Xcode 27 Beta 3 SDK) — they live behind a
/// `@ModelActor` isolation boundary. The domain layer, though, speaks
/// `Sendable` ``NebulaEntity`` values. An `AuroraEntityMapping` is the bridge:
/// the app declares, per `@Model` type, how to convert in both directions and
/// how to build the `FetchDescriptor`s the repository needs.
///
/// The mapping is **type-level** (static methods) so ``AuroraRepository`` holds
/// no per-instance mapping state — only the `@ModelActor`-synthesized
/// `ModelContext`. Conform with `enum` (a namespace) so no instance can exist:
///
/// ```swift
/// @Model
/// final class AccountRecord {
///     var uid: UUID
///     var balance: Decimal
///     init(uid: UUID, balance: Decimal) { self.uid = uid; self.balance = balance }
/// }
///
/// struct Account: NebulaEntity {
///     typealias ID = NebulaID<Account>
///     let id: ID
///     let balance: Decimal
/// }
///
/// enum AccountMapping: AuroraEntityMapping, Sendable {
///     typealias Model = AccountRecord
///     typealias Entity = Account
///
///     static func toEntity(_ model: AccountRecord) -> Account {
///         Account(id: Account.ID(rawValue: model.uid), balance: model.balance)
///     }
///     static func insert(_ entity: Account, in context: ModelContext) -> AccountRecord {
///         let record = AccountRecord(uid: entity.id.rawValue, balance: entity.balance)
///         context.insert(record)
///         return record
///     }
///     static func update(_ model: AccountRecord, from entity: Account) {
///         model.balance = entity.balance
///     }
///     static func descriptor(for id: Account.ID) -> FetchDescriptor<AccountRecord> {
///         let raw = id.rawValue
///         return FetchDescriptor(predicate: #Predicate { $0.uid == raw })
///     }
///     static func descriptor() -> FetchDescriptor<AccountRecord> {
///         FetchDescriptor()
///     }
/// }
/// ```
public protocol AuroraEntityMapping {

    /// The SwiftData `@Model` persistence representation.
    associatedtype Model: PersistentModel

    /// The Nebula ``NebulaEntity`` domain DTO (the repository's `Element`).
    associatedtype Entity: NebulaEntity

    /// Maps a fetched `@Model` to the Sendable domain entity.
    ///
    /// Called inside the `@ModelActor` isolation — the non-`Sendable` `Model`
    /// does not escape; only the `Sendable` `Entity` is yielded out.
    static func toEntity(_ model: Model) -> Entity

    /// Creates and inserts a **new** `@Model` from `entity`.
    ///
    /// Called by ``AuroraRepository/save(_:)`` when no existing record is found
    /// for `entity.id`. The mapping owns the `@Model` initializer shape.
    static func insert(_ entity: Entity, in context: ModelContext) -> Model

    /// Mutates an existing `@Model` from `entity` (add-or-replace by id).
    ///
    /// Called by ``AuroraRepository/save(_:)`` when an existing record is found.
    /// The identity field(s) are assumed immutable — only the mutable state is
    /// written.
    static func update(_ model: Model, from entity: Entity)

    /// A `FetchDescriptor` selecting the single `@Model` for `id` (empty result
    /// when absent). Used by `find(id:)`, `delete(_:)`, and the `save(_:)`
    /// lookup.
    static func descriptor(for id: Entity.ID) -> FetchDescriptor<Model>

    /// A `FetchDescriptor` selecting all `@Model` instances. Used by
    /// `stream()` and `count()`.
    static func descriptor() -> FetchDescriptor<Model>
}