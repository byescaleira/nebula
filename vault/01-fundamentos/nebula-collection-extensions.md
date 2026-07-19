---
tags: [foundation, collection-extensions]
aliases: [Nebula Collections, nebula collections]
related: [[nebula-logging], [nebula-errors], [nebula-date-time-extensions], [nebula-string-extensions], [nebula-number-measurement-extensions], [nebula-primitive-extensions], [nebula-codable-foundation], [nebula-data-url-extensions], [nebula-standardize-measure], [nebula-spm-architecture], [nebula-swift6-concurrency]]
---

# Nebula Collection (Array/Set/Dictionary) Extensions

This note fixes the design of Nebula's collection-ergonomics layer: safe index access, chunking/windowing, uniquing, stable partitioning, key-path sort/min/max/filter, dictionary merging (up to 3), grouping, and a `CountedSet`-like frequency counter. The binding constraints come from the root docs ([[nebula-spm-architecture]], [[nebula-swift6-concurrency]]): single SPM target `Nebula`, no third-party runtime deps, Swift language mode v6 / strict concurrency, all public value types `Sendable`, `Nebula` public prefix, `.v26` floor on iOS/macOS/tvOS/watchOS/visionOS.

## What the Swift stdlib already gives us (do NOT reimplement)

The Swift standard library's collection APIs are **ungated** — available on every Nebula platform since the Swift versions that shipped them:

- **SE-0165** (Swift 4.0) is the omnibus Dictionary modernization: `Dictionary(uniqueKeysWithValues:)`, `Dictionary(_:uniquingKeysWith:)`, `merge(_:uniquingKeysWith:)` / `merging(_:uniquingKeysWith:)`, `Dictionary(grouping:by:)`, `mapValues`, Dictionary-returning `filter`, and `subscript(key:default:)` ([SE-0165](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0165-dict.md)). The subscript-with-default is the primitive that makes a frequency counter trivial: `freq[c, default: 0] += 1`.
- **SE-0218** (Swift 5.0) adds `compactMapValues(_:)` ([SE-0218](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0218-introduce-compact-map-values.md)) — there is no reason for Nebula to re-wrap it.
- **SE-0372** (Swift 5.8) documents `sort()`/`sorted(by:)` as **guaranteed stable** ([SE-0372](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0372-document-sorting-as-stable.md), backed by a Timsort-style adaptive merge sort in [stdlib Sort.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/Sort.swift)). The guarantee is ungated across all Swift platforms (the stable algorithm predates ABI stability). **This eliminates the need for a Nebula `stableSort` API** — stdlib sort is already stable.
- Core `min()`, `max()`, `min(by:)`, `max(by:)`, `firstIndex(where:)`, `first(where:)`, `partition(by:)` are all stdlib (see [CollectionAlgorithms.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/CollectionAlgorithms.swift)). Note: `partition(by:)` on `MutableCollection` is explicitly **not stable** (half-stable for forward-only collections, unstable for bidirectional) — see [swift-algorithms Partition guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Partition.md).

## What Foundation adds on top (modern key-path APIs)

Verified against the installed `Foundation.swiftinterface` (arm64e-apple-macos, MacOSX27.0.sdk):

- `sorted(using:)` and `sort(using:)` on `Sequence` / `MutableCollection & RandomAccessCollection`, gated `@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)` (interface lines 13893-13907) — well below Nebula's `.v26` floor, so effectively always available. ([Apple SortComparator docs](https://developer.apple.com/documentation/foundation/sortcomparator))
- `KeyPathComparator<Compared>` (line 21160, iOS 15+) and `SortDescriptor<Compared>` (line 21204, iOS 15+, with key-path inits additionally `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)`) — these are the modern key-path sorting primitives. `KeyPathComparator(\Person.age)` replaces the closure form. **Note:** `KeyPathComparator`'s init requires `any KeyPath<Compared, Value> & Sendable` — the keypath must be Sendable (satisfied implicitly when Element is Sendable; otherwise it will not type-check). Both `KeyPath<Compared, Value>` and `KeyPath<Compared, Value?>` inits exist.
- `Sequence.filter(_ predicate: Foundation.Predicate)` — macro-based predicates, `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)` (line 11711), marked `throws` ([Apple Predicate docs](https://developer.apple.com/documentation/foundation/predicate)). Use when predicates must be serialized/constructed dynamically; for static filters prefer the plain closure `filter`.

These are all Foundation overlays on `Swift.Sequence`/`Swift.MutableCollection` — they are Apple's modern, key-path-first API direction and Nebula should layer on them rather than reinvent.

## What is NOT in stdlib or Foundation (Nebula must self-host)

The chunking/windowing/uniquing/stable-partitioning ergonomics Nebula needs live in **`apple/swift-algorithms`** ([repo](https://github.com/apple/swift-algorithms)), which is third-party and therefore **banned** by Nebula's no-runtime-dependency rule. `chunks(ofCount:)` was pitched for stdlib inclusion ([swift-evolution PR #935](https://github.com/apple/swift-evolution/pull/935)) but **not accepted**. grep of `Foundation.swiftinterface` for `chun|window|uniqued|stablePartition` returns only unrelated `windowsCP1250..1254` string-encoding constants and `windowsLocaleCode` — confirming Foundation carries none of the algorithms.

Reference signatures (to mirror for parity, with noted divergences):

- `chunks(ofCount:)` returns `ChunkedByCount<Self>` (lazy), `count > 0` required, last chunk may be shorter — [Chunked guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Chunked.md).
- `windows(ofCount:)` returns `WindowsOfCountCollection<Self>` (lazy), empty when `count > collection.count` — [Windows guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Windows.md).
- `uniqued()` (Element: Hashable) returns a **lazy** `UniquedSequence<Self, Element>`; `uniqued(on:)` on a regular Sequence returns eager `[Element]` — [Unique guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Unique.md). Eager `uniqued(on:)` is O(n) and preserves first-occurrence order. **Divergence:** Nebula's `nebulaUniqued()` (no-arg) returns eager `[Element]` by design (lazy available behind `nebulaLazy`).
- `stablePartition(by:)` (O(n log n), order preserved in both groups) and `partitioned(by:)` (non-mutating, returns `(falseElements: [Element], trueElements: [Element])`) — [Partition guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Partition.md). **Divergence:** Nebula's `nebulaPartitioned(by:)` labels its tuple `(first, second)` — a conscious rename, not a signature mirror.

## Recommended design for Nebula

Placement: `Sources/Nebula/Extensions/Collections/` inside the single `Nebula` target. To avoid polluting the Swift stdlib namespace for every consumer, Nebula uses a `nebula*` method-label prefix and, where the ergonomic win is concrete, targets `Array`/`Dictionary`/`Set` narrowly instead of the open `Collection`/`Sequence`. The contract style mirrors the Cosmos sibling ([[nebula-spm-architecture]]): Sendable struct + `@Sendable` closure + fluent builders, **without** SwiftUI `@Entry`/`@Observable` — Nebula is a foundation, not a UI layer.

| Symbol | Kind | Purpose |
|---|---|---|
| `Collection.nebulaSafe(_:)` | method | Optional-returning safe subscript (nil instead of trap on out-of-range index) |
| `subscript(nebulaSafe:)` on `MutableCollection & RandomAccessCollection` | subscript | Mutable safe access |
| `NebulaChunkedSequence<Base: Collection>` | struct | Lazy non-overlapping chunks / overlapping windows; `Sendable` when `Base: Sendable` |
| `Collection.nebulaChunked(byCount:)` | method | Non-overlapping chunks (last may be short, count > 0 precondition) |
| `Collection.nebulaWindows(ofCount:)` | method | Overlapping sliding windows (empty if count > collection.count) |
| `Sequence.nebulaUniqued(on:)` / `nebulaUniqued()` | method | First-occurrence-preserving dedup; eager `[Element]`; non-escaping `rethrows` |
| `MutableCollection.nebulaStablePartition(by:)` | mutating method | Stable partition, O(n log n); non-escaping `rethrows` |
| `Sequence.nebulaPartitioned(by:)` | method | Non-mutating stable partition -> `(first, second)` arrays; non-escaping `rethrows` |
| `Sequence.nebulaSorted(_:)` / `nebulaMin(_:)` / `nebulaMax(_:)` | method | Key-path overloads on Foundation `KeyPathComparator` (iOS 15+; keypath must be Sendable) |
| `Sequence.nebulaFiltered(by: Foundation.Predicate)` | throwing method | Macro-predicate filter (iOS 17+) |
| `NebulaFrequency<Element: Hashable & Sendable>` | struct | CountedSet-like frequency counter on `subscript(key:default:)`; `Sendable` |
| `Dictionary.nebulaMerging(_:_:uniquingKeysWith:)` / `nebulaMerging3(...)` | method | Merge up to 2/3 dictionaries in one pass via SE-0165 semantics; non-escaping `rethrows` |

> **Shipped status (0.1.0):** `nebulaFiltered(by: Foundation.Predicate)` and `NebulaFrequency` were **designed here but deferred** — they are NOT in 0.1.0. Shipped Collection ergonomics in 0.1.0: `nebulaSafe` subscript, `nebulaChunked`/`nebulaWindows`/`nebulaUniqued`/`nebulaStablePartition`/`nebulaPartitioned`/`nebulaSorted`/`nebulaMerging` (single `nebulaMerging(_:_:uniquingKeysWith:)`, no `nebulaMerging3`). Also NOT shipped: `NebulaChunkedSequence` lazy type (eager only in 0.1.0) and `nebulaMin`/`nebulaMax`. See ROADMAP "Later (post-0.1.0)".

Sendable & concurrency: all public value types get **derived** `Sendable` conformance conditioned on their generic parameters being `Sendable` (e.g. `NebulaChunkedSequence<Base: Collection>: Sendable where Base: Sendable`). `NebulaChunkedSequence` stores only `Base` + `Int`, so its struct-level `Sendable` is correct; cross-actor iteration of yielded `Base.SubSequence` additionally requires `SubSequence: Sendable`, which is NOT implied by `Base: Sendable` — document this. **Eager synchronous methods use non-escaping `rethrows` closures, NOT `@escaping @Sendable`** — the latter is reserved for genuinely lazy/escaping contexts (a stored projection in a future lazy `nebulaLazy` variant). `KeyPathComparator` requires `any KeyPath & Sendable`, so `nebulaSorted` key-path overloads implicitly require a Sendable keypath. No `@unchecked`. No `DispatchQueue`/`NSLock` — synchronous value transforms with no shared mutable state, so `Mutex<T>`/`Atomic<T>` from `Synchronization` are not needed in this layer. Versioning: public symbols use the canonical Foundation 26-floor form `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)` to encode "since Nebula 26"; anything above floor is flagged as Nebula 27.

## Apple patterns adopted

- Modern key-path sorting via `Foundation.SortComparator`/`KeyPathComparator`/`SortDescriptor` (`sorted(using:)`) over closure-only `sorted(by:)` — verified `@available(iOS 15, macOS 12, tvOS 15, watchOS 8)` in the `.swiftinterface` (lines 13893-13907).
- Macro-based `Foundation.Predicate` for `filter(_:)` where dynamic/serializable predicates are needed (iOS 17+/macOS 14+/tvOS 17+/watchOS 10+, `throws`, line 11711).
- Rely on stdlib's SE-0372 **stable** sort instead of shipping a `stableSort` wrapper.
- Use SE-0165 Dictionary APIs (`Dictionary(_:uniquingKeysWith:)`, `merging`, `Dictionary(grouping:by:)`, `mapValues`, `subscript(key:default:)`) as the primitives Nebula ergonomics layer on — Apple's blessed, ungated, all-platform modern Dictionary contract.
- Use SE-0218 `compactMapValues(_:)` directly (no Nebula reimplementation).
- Adopt `swift-algorithms` reference semantics (`uniqued(on:)`, `chunks(ofCount:)`, `windows(ofCount:)`, `stablePartition(by:)`) as the spec for Nebula's self-hosted copies, with two conscious divergences: `nebulaUniqued()` is eager `[Element]` (swift-algorithms' is lazy), and `nebulaPartitioned(by:)` labels its tuple `(first, second)` (swift-algorithms uses `(falseElements, trueElements)`).
- Mirror Cosmos sibling contract style (Sendable struct + `@Sendable` handler + `nebula*` prefix namespace), adapted for a non-SwiftUI foundation: no `@Entry`/`@Observable`.
- Gate OS-introduced features with `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)` == "since Nebula 26" (includes visionOS, matching the Foundation SDK convention at interface line 68); flag anything above `.v26` as Nebula 27.

## Risks & open questions

- **Namespace pollution**: even `nebula*`-prefixed methods on open `Collection`/`Sequence` appear in autocomplete for every importer. Mitigation: target `Array`/`Dictionary`/`Set` narrowly where the win is concrete; keep open-`Collection` extensions limited to the truly generic algorithms (chunked/windows/uniqued).
- **Self-implementing chunks/windows/uniqued/stablePartition** risks subtle divergence from `swift-algorithms` (empty-collection, `count == 0`, `count > collection.count`, half-stable vs full-stable edge cases; also the eager-vs-lazy and label divergences above). Mitigation: pin semantics to the guides and add parity tests.
- **stablePartition is O(n log n)** vs stdlib `partition` O(n); users may reach for it by default. Mitigation: document loudly, default recommendations to stdlib `partition(by:)` unless stability is required.
- **Foundation Predicate filter** is `throws` and iOS 17+; using it everywhere forces `try` and a higher floor. Mitigation: keep `nebulaFiltered(by:)` optional; default ergonomics stay on plain closure `filter` (no gating).
- **KeyPathComparator** requires the keypath to be `Sendable` (`any KeyPath & Sendable`); keypaths from non-Sendable Element roots will not type-check, and optional-key-path (`Element?`) variants need nil handling. Mitigation: provide both `T` and `T?` overloads, document the Sendable-keypath constraint, and add nil tests.
- **NebulaFrequency** requires `Element: Hashable & Sendable`; collections of non-Sendable elements can't use it — acceptable, document it.
- **Closure annotations**: eager synchronous methods must use non-escaping `rethrows`, NOT `@escaping @Sendable`; reserve the latter for genuinely lazy/escaping contexts only.
- **visionOS gate**: Nebula's own `@available` gates must include `visionOS 26` (Foundation SDK's canonical 26-floor form at interface line 68); the originally-proposed 4-platform gate omitted visionOS.
- Open: lazy vs eager default for chunked/windows (recommend eager by default, lazy behind a `nebulaLazy` property — and the lazy variants are where `@escaping @Sendable` projections actually belong); whether to accept varargs key-path + `SortOrder` like `sorted(using: comparators:)`; whether partition/uniqued belong on generic `Collection` or `Array`-only; from-scratch vs vendored subset of `swift-algorithms` (recommend from-scratch for the no-dependency constraint); whether to centralize the 5-platform `@available` in a helper.

## Sources

- [SE-0165: Dictionary & Set Enhancements](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0165-dict.md)
- [SE-0218: Introduce compactMapValues to Dictionary](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0218-introduce-compact-map-values.md)
- [SE-0372: Document Sorting as Stable](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0372-document-sorting-as-stable.md)
- [Apple Developer Docs — Dictionary init(_:uniquingKeysWith:)](https://developer.apple.com/documentation/swift/dictionary/init(_:uniquingkeyswith:))
- [Apple Developer Docs — Foundation SortComparator](https://developer.apple.com/documentation/foundation/sortcomparator)
- [Apple Developer Docs — Foundation Predicate](https://developer.apple.com/documentation/foundation/predicate)
- [apple/swift-algorithms — Chunked guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Chunked.md)
- [apple/swift-algorithms — Windows guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Windows.md)
- [apple/swift-algorithms — Unique guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Unique.md)
- [apple/swift-algorithms — Partition guide](https://github.com/apple/swift-algorithms/blob/main/Guides/Partition.md)
- [apple/swift-algorithms repo](https://github.com/apple/swift-algorithms)
- [swift-evolution PR #935 — chunks(ofCount:) stdlib pitch](https://github.com/apple/swift-evolution/pull/935)
- [swiftlang/swift stdlib Sort.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/Sort.swift)
- [swiftlang/swift stdlib CollectionAlgorithms.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/CollectionAlgorithms.swift)
- Ground truth: `Foundation.swiftinterface` at `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` (line 68 canonical 26-floor gate incl. visionOS; line 11711 filter(Predicate) `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)`; lines 13893-13907 sorted(using:)/sort(using:) `@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)`; line 21160 KeyPathComparator; line 21204 SortDescriptor with key-path inits additionally `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)`; zero relevant matches for `chun|window|uniqued|stablePartition` — only unrelated `windowsCP*` encoding constants and `windowsLocaleCode`)

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.