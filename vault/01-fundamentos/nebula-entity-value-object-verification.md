---
tags: [nebula, ddd, entity, value-object, sendable, identifiable, verification, adversarial-verify]
aliases: [entity-value-object-verification, nebula-entity-verification]
related: ["[[nebula-errors]]", "[[Home]]"]
---

# Entity / Value-Object in value-type-Sendable Swift — adversarial verification

Verification run for the ARCHITECTURE toolkit dimension "Entity / value-object in
value-type-Sendable Swift". Apple-API claims re-checked against the Xcode 27 Beta 3
SDK `.swiftinterface` (arm64e-apple-macos slice); Nebula-source claims checked
against `Sources/Nebula/Errors/NebulaError.swift`. DDD-theory citations checked via
WebFetch (allowed — restriction only forbids WebFetch for *Apple API availability*).

## Ground-truth grep lines

- `Identifiable` lives in **Swift.swiftmodule**, NOT Foundation:
  `Swift.swiftmodule:12443` `public protocol Identifiable<ID> {`
  `12444` `associatedtype ID : Swift::Hashable`
  `12445` `var id: Self.ID { get }`
  `12446` `}`
  `12448` `extension Swift::Identifiable where Self : AnyObject {` (conditional
  default `id: ObjectIdentifier` for class types — NOT a requirement of the
  protocol; no AnyObject constraint on the protocol itself).
  Availability `macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0` (below the `.v26`
  floor — no gating needed).
- `Sendable` is a `@_marker` protocol with no required methods:
  `Swift.swiftmodule:5676` `@_marker public protocol SendableMetatype : ~Copyable, ~Escapable`
  `5678` `@_marker public protocol Sendable : Swift::SendableMetatype`
- `Equatable` `Swift.swiftmodule:9619` `public protocol Equatable : ~Copyable, ~Escapable` —
  no `AnyObject`/class requirement.
- `Hashable` `Swift.swiftmodule:11981` `public protocol Hashable : Swift::Equatable, ~Copyable, ~Escapable` —
  no `AnyObject`/class requirement. Auto-synthesis available to structs/enums of
  `Hashable` fields; the protocol itself imposes no class bound.

## Nebula source precedent

`Sources/Nebula/Errors/NebulaError.swift`:
- `92-102` `Box` — `public final class Box: Sendable, Hashable` with `public let value: NebulaError`;
  derived `Sendable` (no `@unchecked`). Comment at `92-94` explicitly states
  "Breaks the value-type recursion: a Swift `struct` cannot contain itself."
- `100` `public static func == (l: Box, r: Box) -> Bool { l.value == r.value }` —
  hand-written `==` on a reference Box where semantics differ from synthesis.

## Verdicts

- Claim 1 (Fowler VO = value equality + immutability): **confirmed** —
  WebFetch of `martinfowler.com/bliki/ValueObject.html` returns "value objects
  should be immutable" and equality by property values.
- Claim 2 (Evans Entity vs VO partition): **confirmed** —
  WebFetch of `EvansClassification.html` returns Entity "distinct identity that
  runs through time", VO "matters only as combination of attributes", "two value
  objects with the same values for all their attributes are considered equal".
  Caveat: "identifying attribute immutable once assigned" is Evans-book detail,
  not in the Fowler summary.
- Claim 3 (Evans Aggregate rules + Car/Tire): **uncertain** — the cited
  `EvansClassification.html` URL does NOT contain aggregate/Car/Tire content
  (WebFetch confirms the page only defines Entity/VO/Service). The aggregate
  rules come from Evans DDD ch. 15 (book, not fetchable here). Substance is
  genuine DDD but the Fowler-URL citation is misattributed.
- Claim 4 (value-composition aggregate, no Mutex in domain model): **uncertain** —
  synthesis claim, not grep-citable; consistent with Swift value semantics but
  no interface/source backing.
- Claim 5 (parse-don't-validate, typealias insufficient): **uncertain** —
  `hackingwithswift.com/articles/188/...` returned HTTP 403; specific citation
  content unverifiable. Principle is well-established (Wlaschin, Secure by
  Design) but not confirmed against the cited URL.
- Claim 6 (Sendable `@_marker`, no required methods): **confirmed** —
  `Swift.swiftmodule:5678`. Sub-claim "explicit conformance needed for
  public/non-frozen structs" is general Swift knowledge, not interface-citable.
- Claim 7 (synthesized Equatable footgun for entities; NebulaError Box L100
  precedent): **confirmed** — `NebulaError.swift:100` hand-written `==` on Box.
  Synthesized-Equatable-compares-all-fields semantics is standard Swift.
- Claim 8 (Identifiable signature, no redeclaration, let id ok): **confirmed
  with corrected citation** — signature correct at `Swift.swiftmodule:12443-12446`,
  but the claim's guessed location "Foundation.swiftinterface" is WRONG. No
  AnyObject requirement (the `where Self : AnyObject` extension at `12448` is
  conditional, not a constraint). `let id` satisfies the get-only requirement.
- Claim 9 (recursive aggregate → final class Box: Sendable derived): **confirmed** —
  `NebulaError.swift:92-102`.
- Claim 10 (aggregate = design rule, not type-system rule; marker-only
  NebulaAggregate refining NebulaEntity): **uncertain** — Evans DDD content,
  not grep-citable; "Swift cannot express no-outside-references" is
  self-evidently true (no such type-system feature).

## Verify targets

- Hashable/Equatable auto-synthesis for structs: confirmed — protocols at
  `Swift.swiftmodule:9619` (Equatable) and `11981` (Hashable) are
  `~Copyable, ~Escapable` with NO `AnyObject`/class requirement.
- No hidden AnyObject/class requirement on Identifiable: confirmed — the
  `AnyObject` extension at `12448` is a conditional default, not a protocol
  constraint.

## Binding-constraint flag

Claim 8's citation location must be corrected: `Identifiable` is in the Swift
core stdlib (`Swift.swiftmodule`), not `Foundation.swiftinterface`. This does
not affect the proposed `NebulaEntity: Sendable, Identifiable where ID:
Sendable` design — the signature, the `let id` immutability, and the
no-redeclaration argument all hold. But the ADR/vault text must cite
`Swift.swiftmodule:12443-12446`, not Foundation.