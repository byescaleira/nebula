---
tags: [padroes, architecture, ddd, value-object, entity, validation, swift6, nebula]
aliases: [NebulaValue, NebulaEntity, NebulaAggregate, NebulaID, NebulaValidator, NebulaInvariant, nebula-validation-invariants]
related: [[nebula-clean-architecture-toolkit]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-usecase]], [[nebula-errors]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "0.2.0"
---

# Nebula Domain Modeling + Validation / Invariants

The Entities-layer of the toolkit: `NebulaValue` / `NebulaEntity` / `NebulaAggregate` markers, `NebulaID<Entity>` typed IDs, identity equality, and the validation/invariant seam (`NebulaValidator` / `NebulaAsyncValidator` / `NebulaInvariant`). Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## Value Object vs Entity (Fowler/Evans, verified)

- **Value Object** — equality by property values; "value objects should be immutable" (change = replacement, not mutation) — Fowler, [ValueObject](https://martinfowler.com/bliki/ValueObject.html) (verbatim). Maps onto Swift structs (value equality + copy-on-assignment for free).
- **Entity** — identity-defined; the identifying attribute is immutable once assigned (Evans, *DDD* ch. 15 — the "thread of continuity and identity" phrasing is Evans', not Fowler's EvansClassification page). Entities require **identity-based** equality; value objects require **whole-value** equality.
- **Aggregate** (Evans *DDD* ch. 15) — one root `Entity` with global identity; inner entities have **local** identity (unique only within the aggregate); nothing outside holds references to inner entities except the root; cross-aggregate references are by **identity (ID)**, not object reference; a delete removes everything inside the boundary; all invariants hold on commit. NOTE: the aggregate rules come from Evans' book, NOT Fowler's EvansClassification bliki (which contains no aggregate content — verified; re-cite Evans ch. 15).

## `NebulaValue` — value-object marker

`public protocol NebulaValue: Sendable, Equatable, Hashable` — no required members. Conforming structs synthesize `Sendable`/`Equatable`/`Hashable` when all stored fields are. No `@unchecked`. A value object wrapping a non-Sendable field (e.g. a closure) fails to compile — correct, that is not a pure value. Foundation-only; no UIKit/SwiftUI/`@MainActor`.

The "make illegal states unrepresentable" school (Wlaschin / Minsky origin; "parse, don't validate" — Alexis King) implements value objects as wrapping structs with failable/throwing initializers so **instance existence proves validity** — `typealias` is insufficient (the compiler treats it as the primitive); a wrapping `struct` is required (corroborated via [Hacking with Swift](https://www.hackingwithswift.com/articles/188/improving-your-swift-code-using-value-objects)). This is the validation contract `NebulaValue` documents.

## `NebulaEntity` — identity, NOT whole-value equality

```swift
public protocol NebulaEntity: Sendable, Identifiable where ID: Sendable {
    // no Equatable/Hashable refinement — identity equality is opt-in
}
public extension NebulaEntity {
    func isSameIdentity(as other: Self) -> Bool { id == other.id }
}
```

- **Reuses stdlib `Identifiable`** — NOT redeclared (CLAUDE.md "never redeclare stdlib APIs"). Ground truth: `Swift.swiftmodule:12443-12446` `public protocol Identifiable<ID> { associatedtype ID : Swift::Hashable; var id: Self.ID { get } }`. A `let id: SomeID` stored property satisfies the get-only `var id: Self.ID { get }` and keeps identity immutable per Evans. The class-only `id: ObjectIdentifier` extension (`:12447`, `@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)`) is an opt-in on `AnyObject` — `NebulaEntity` does not require it.
- **Adds `ID: Sendable`** (beyond `Identifiable`'s `Hashable`) so DDD IDs crossing actor boundaries are `Sendable`. Valid: `ID: Hashable` is already required; adding `ID: Sendable` is a stricter, additive constraint.
- **Deliberately NOT `Equatable`**: synthesized `Equatable` compares **all** stored fields (SE-0185) — a footgun for entities (two snapshots of the same identity at different lifecycle moments compare *unequal*). Identity equality is an opt-in `isSameIdentity(as:)` comparing `id`. Any `Equatable` on an entity must be hand-written (the `NebulaError.Box` precedent — hand-written `==` at `Sources/Nebula/Errors/NebulaError.swift:100` where synthesis semantics would differ).
- **`Sendable`**: derived on conforming structs (all stored fields, including child entities/value objects and `id`, Sendable).

## `NebulaAggregate` — consistency-boundary marker

`public protocol NebulaAggregate: NebulaEntity {}` — no extra type requirements. An aggregate is **not** a richer entity type-systemically; it is an entity *designated* as a consistency boundary. The boundary contract is **semantic and documented**, not compiled — Swift cannot express "no outside references to inner entities" in the type system. In value-type Swift, aggregate ownership is **value composition** (stored struct properties), not reference holding: the root struct owns children by value; `root.id` is global identity; child entities carry local `id`; cross-aggregate links are typed `NebulaID<X>` value objects, never references; mutation is copy-on-write producing a new root — **no `Mutex`/`actor` needed in the domain model** (the shared-state boundary is the repository/persistence layer, not the domain model).

## `NebulaID<Entity>` — typed identity

`public struct NebulaID<Entity>: NebulaValue` — phantom-typed on an `Entity` tag, `Raw: Sendable, Hashable`. Derived `Sendable`/`Equatable`/`Hashable`. The phantom `Entity` parameter is **never stored** → it need not be `Sendable` (compile-time tag only) — document so users do not over-constrain the tag. Default raw `UUID` (Foundation) when the default alias is used; consumers may pick a different raw type with zero Foundation-UUID dependency. Tradeoff: the phantom tag does not enforce `<Entity>: NebulaEntity` (a typo `NebulaID<Cusomer>` compiles silently) — constraining it would create a forward-reference cycle (the ID is referenced from inside the Entity's own definition), so it stays unconstrained; document the convention.

## Recursive aggregates — the `Box` exception

A recursive aggregate (a node containing itself, e.g. a tree/category) **cannot** be a plain struct (a Swift struct cannot contain itself). The constrained exception is a `final class Box: Sendable` with a `Sendable let` (derived `Sendable`, **not `@unchecked`**) — mirroring `Sources/Nebula/Errors/NebulaError.swift:91-99` `public final class Box: Sendable, Hashable { public let value: NebulaError; … }`. Used **only** to break value-type recursion, never for shared mutable state. This introduces a reference type inside an otherwise-value aggregate; the `let` makes it immutable (no shared *mutable* state), but it must be explained as the constrained exception, not a license for general reference-type use.

## Validation / invariant seam

Two complementary mechanisms (the marker protocols above enforce *structure*; validation enforces *rules*):

- **Parse-don't-validate on `NebulaValue`**: the wrapping struct's failable/throwing `init` is the validator — instance existence proves validity.
- **`NebulaValidator<T>`** — a `Sendable` value (struct or `@Sendable` closure) that checks a `T` and throws/returns `NebulaValidationError` ([[nebula-domain-error]]). Synchronous, pure. Shape mirrors the toolkit's closure-witness preference (see [[nebula-usecase]]): prefer a generic `Sendable` struct over a PAT protocol; `any NebulaValidator<T>` is `Sendable` when `T: Sendable`.
- **`NebulaAsyncValidator<T>`** — the async variant for rules needing I/O (e.g. uniqueness against a `NebulaReadOnlyRepository`). `@Sendable (T) async throws -> Void` / `throws(NebulaValidationError)`. Async because a uniqueness check must query a repo; the synchronous `NebulaValidator` covers all pure rules.
- **`NebulaInvariant`** — the aggregate invariant contract: a `func validateInvariants() throws(NebulaError)` (or `throws(NebulaValidationError)`) invoked on every mutating factory/method of a `NebulaAggregate`, asserting the whole-aggregate invariants hold on commit (Evans). This is **behavior**, not identity — the open question is whether it belongs in a foundation library or is purely the app's responsibility ([[clean-architecture-open-questions]]).

> The `NebulaValidator` / `NebulaAsyncValidator` / `NebulaInvariant` shapes are derived from the binding constraints (Sendable, no `@unchecked`, open-struct error taxonomy, closure-witness preference) + the `NebulaValidationError` defined in [[nebula-error-taxonomy-toolkit]] + the parse-don't-validate finding. Open ergonomics questions (struct vs closure, composable rule combinators, error accumulation vs short-circuit) are tracked in [[clean-architecture-open-questions]].

## Sendable strategy

- Markers/IDs: derived `Sendable` (all-value, Sendable fields). No `@unchecked` on Nebula-defined value types.
- `NebulaEntity`: derived; `ID: Sendable` added beyond `Identifiable`'s `Hashable`.
- `NebulaAggregate`: inherited from `NebulaEntity`.
- Validators: derived `Sendable` (struct over a `@Sendable` closure, or `@Sendable` closure typealias) — **NOT `Equatable`** if they store a `@Sendable` closure (mirrors `NebulaErrorConfiguration`).
- Recursive `Box`: derived `Sendable` on `final class` with `Sendable let` (the `NebulaError.Box` precedent) — the one constrained exception to "value types only".

## Risks (see [[clean-architecture-toolkit-risks]])

- **Markers are documentation, not compile-time enforcement** — the toolkit cannot literally "GUARANTEE Clean Architecture" from a marker; a conforming struct can still be mutable, hold non-Sendable fields, or violate invariants. State honestly: the guarantee is limited to what the refined protocols (`Sendable`/`Equatable`/`Hashable`/`Identifiable`) already prove.
- **Synthesized `Equatable` on an entity is a footgun** the type system cannot forbid — a user adding `: Equatable` gets whole-value comparison that wrongly distinguishes two snapshots of the same identity. The non-`Equatable` default is the strongest signal available; document loudly.
- **`NebulaEntity` migration friction**: existing app types conforming to `Identifiable` with a non-Sendable ID cannot conform to `NebulaEntity` without changing their ID. Rare for domain IDs; document.
- **Recursive `Box` weakens the "no reference types" story** for those specific domains — explain as the constrained exception.
- **Phantom-typed `NebulaID<Entity>` does not enforce `<Entity>: NebulaEntity`** — a typo compiles silently. Constraining creates a forward-reference cycle. Document the convention.
- **`NebulaAggregate` boundary rule is unenforceable** — a consumer can hand out a child entity struct by value. Because structs are values, this is a snapshot not a live reference (less catastrophic than reference-type DDD), but it still violates the invariant contract. Document as a discipline rule.

## Open questions (see [[clean-architecture-open-questions]])

- `NebulaAggregateInvariant` protocol (`validateInvariants() throws(NebulaError)`) in Nebula, or purely the app's responsibility? Lean: document the contract; ship the protocol only if it earns a second use.
- `NebulaID<Entity>` default `Codable`/`LosslessStringConvertible`/`CustomStringConvertible` (raw UUID), or opt-in per entity? Cross-aggregate IDs are frequently serialized for DTOs/persistence.
- `NebulaValue: Hashable` always, or split `NebulaValue` (Sendable+Equatable) and `NebulaHashableValue` (adds `Hashable`)? Rare non-`Hashable` composite value objects may want value equality without Set/Dict membership.
- `NebulaEntity` + `Codable`: ship a `NebulaCodableEntity` refinement, or leave `Codable` fully opt-in?
- `NebulaLocalEntity` marker (local identity within a parent aggregate) distinct from `NebulaEntity`, or pure documentation?
- Validator ergonomics: composable rule combinators, error-accumulating vs short-circuit, struct-vs-closure — open, tracked in [[clean-architecture-open-questions]] Q6.

## Sources

- Martin Fowler, [ValueObject](https://martinfowler.com/bliki/ValueObject.html) (verbatim: "value objects should be immutable").
- Martin Fowler, [EvansClassification](https://martinfowler.com/bliki/EvansClassification.html) (Entity vs Value partition — verified; aggregate content is NOT on this page).
- Evans, *Domain-Driven Design*, ch. 15 (Aggregates: root/local identity, identity-only cross refs, cascade delete, invariant-on-commit, "thread of continuity and identity").
- [Hacking with Swift — Value Objects](https://www.hackingwithswift.com/articles/188/improving-your-swift-code-using-value-objects) (wrapping struct + failable init; "the existence of a User means it must be valid"; `typealias` gives no enforcement). "Make illegal states unrepresentable" — Wlaschin/Minsky; "parse, don't validate" — Alexis King.
- `Swift.swiftmodule` (Xcode 27 Beta 3): `Sendable` `@_marker` `:5678`, `Identifiable<ID>` `:12443-12446`, class-only `id` extension `:12447`.
- Nebula source: `NebulaError.swift:91-100` (`Box` recursive precedent + hand-written `==`), `NebulaErrorConfiguration.swift:47` (Sendable-only-not-Equatable precedent).
- Sibling notes: [[nebula-domain-error]] (`NebulaValidationError`), [[nebula-error-taxonomy-toolkit]], [[nebula-repository]] (`NebulaEntity` ID constraint), [[nebula-swift6-concurrency]] (derived Sendable).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.