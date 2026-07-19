//
//  Collection+Nebula.swift
//  Nebula
//
//  Collection / Sequence / Dictionary ergonomics the Swift stdlib and Foundation
//  do not ship: a safe (trap-free) subscript, eager chunking/windowing, first-
//  occurrence-preserving uniquing, a stable partition, key-path sorting on
//  Foundation `KeyPathComparator`, and 3-way Dictionary merging.
//
//  Per CLAUDE.md, open `Collection`/`Sequence` ergonomics carry the `nebula*`
//  method-label prefix so they never collide with future stdlib additions.
//  Eager synchronous transforms use non-escaping `rethrows` closures (NOT
//  `@escaping @Sendable`); there is no shared mutable state, so no
//  `Mutex`/`Atomic` is needed. See
//  vault/01-fundamentos/nebula-collection-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK: `sorted(using:)` / `sort(using:)`
//  (Sequence / MutableCollection & RandomAccessCollection) and
//  `KeyPathComparator` are `@available(iOS 15.0, macOS 12.0, tvOS 15.0,
//  watchOS 8.0, *)` (Foundation.swiftmodule lines 13893-13907, 21160) — all
//  below Nebula's `.v26` floor, so no `@available` gate is required. grep for
//  `chunk|window|uniqued|stablePartition` returns zero relevant Foundation
//  matches (only unrelated `windowsCP*` encoding constants), confirming these
//  algorithms are Nebula's to self-host.
//

import Foundation

// MARK: - Safe subscript

extension Collection {
    /// Trap-free element access at `index`, returning `nil` when `index` is
    /// out of range instead of aborting.
    ///
    /// The stdlib `subscript(position:)` traps on an out-of-range index; this
    /// labeled subscript mirrors it but returns `nil`. The check uses
    /// `indices.contains(index)` (O(1) for `RandomAccessCollection`, O(n) for
    /// forward-only collections).
    ///
    /// ```swift
    /// let a = [10, 20, 30]
    /// a[nebulaSafe: 1]   // 20
    /// a[nebulaSafe: 5]   // nil
    /// ```
    public subscript(nebulaSafe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - Chunking / windowing

extension Collection {
    /// Non-overlapping subsequences of up to `count` elements, in order.
    ///
    /// The last chunk is shorter when the count does not divide evenly.
    /// `count` must be greater than zero (precondition). Eager: returns
    /// `[[Element]]` (each chunk materialized). Mirrors the
    /// `apple/swift-algorithms` `chunks(ofCount:)` spec with an eager result.
    ///
    /// ```swift
    /// [1, 2, 3, 4, 5].nebulaChunked(byCount: 2)
    /// // [[1, 2], [3, 4], [5]]
    /// ```
    public func nebulaChunked(byCount count: Int) -> [[Element]] {
        precondition(count > 0, "Nebula: nebulaChunked(byCount:) requires count > 0")
        var result: [[Element]] = []
        var i = startIndex
        while i < endIndex {
            let next = index(i, offsetBy: count, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[i..<next]))
            i = next
        }
        return result
    }

    /// Overlapping sliding windows of exactly `count` elements, in order.
    ///
    /// Returns an empty array when `count` is greater than the collection's
    /// count. `count` must be greater than zero (precondition). Eager: returns
    /// `[[Element]]`. Mirrors the `apple/swift-algorithms` `windows(ofCount:)`
    /// spec.
    ///
    /// ```swift
    /// [1, 2, 3, 4].nebulaWindows(ofCount: 2)
    /// // [[1, 2], [2, 3], [3, 4]]
    /// ```
    public func nebulaWindows(ofCount count: Int) -> [[Element]] {
        precondition(count > 0, "Nebula: nebulaWindows(ofCount:) requires count > 0")
        var result: [[Element]] = []
        let total = self.count
        guard count <= total else { return result }
        let windowCount = total - count + 1
        // Recompute each window's bounds from `startIndex` rather than advancing
        // a running end index: advancing `index(after:)` past `endIndex` is a
        // trap for opaque-index collections (e.g. `String`), so a running
        // `windowEnd` would trap after the final window. `offset` and
        // `offset + count` are both `<= total` (the distance to `endIndex`), so
        // every `index(_:offsetBy:)` here is in range.
        for offset in 0..<windowCount {
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: count)
            result.append(Array(self[start..<end]))
        }
        return result
    }
}

// MARK: - Uniquing

extension Sequence where Element: Hashable {
    /// First-occurrence-preserving dedup, eager `[Element]`.
    ///
    /// Keeps the first appearance of each element and drops later duplicates.
    /// O(n) time and space. Diverges from `apple/swift-algorithms` `uniqued()`
    /// (which returns a lazy sequence) by being eager — the lazy variant would
    /// belong behind a future `nebulaLazy` property.
    ///
    /// ```swift
    /// [1, 2, 1, 3, 2].nebulaUniqued()   // [1, 2, 3]
    /// ```
    public func nebulaUniqued() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for element in self {
            if seen.insert(element).inserted { result.append(element) }
        }
        return result
    }
}

extension Sequence {
    /// First-occurrence-preserving dedup keyed by `key`, eager `[Element]`.
    ///
    /// Keeps the first element whose `key(element)` has not been seen and
    /// drops later elements with a duplicate key. O(n) time and space. The
    /// `key` closure is non-escaping `rethrows`.
    ///
    /// ```swift
    /// [("a", 1), ("b", 2), ("a", 3)].nebulaUniqued(on: \.0)
    /// // [("a", 1), ("b", 2)]
    /// ```
    public func nebulaUniqued<Key: Hashable>(on key: (Element) throws -> Key) rethrows -> [Element] {
        var seen = Set<Key>()
        var result: [Element] = []
        for element in self {
            if try seen.insert(key(element)).inserted { result.append(element) }
        }
        return result
    }
}

// MARK: - Stable partition

extension MutableCollection {
    /// Reorders in place so elements for which `belongsInSecond` returns
    /// `false` precede those for which it returns `true`, preserving the
    /// relative order within each group (stable).
    ///
    /// O(n) time and O(n) auxiliary space. Prefer the stdlib `partition(by:)`
    /// (O(n), in place, half-stable) when stability is not required — this
    /// method exists for the cases where order must be preserved. The closure
    /// is non-escaping `rethrows`.
    ///
    /// - Note: `partition(by:)` on `MutableCollection` is explicitly **not**
    ///   stable (half-stable for forward-only, unstable for bidirectional);
    ///   this method is the stable alternative.
    public mutating func nebulaStablePartition(by belongsInSecond: (Element) throws -> Bool) rethrows {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if try belongsInSecond(element) {
                second.append(element)
            } else {
                first.append(element)
            }
        }
        var i = startIndex
        for element in first {
            self[i] = element
            i = index(after: i)
        }
        for element in second {
            self[i] = element
            i = index(after: i)
        }
    }
}

extension Sequence {
    /// Non-mutating stable partition into `(first, second)`.
    ///
    /// `first` holds elements for which `belongsInSecond` returns `false`;
    /// `second` holds those for which it returns `true`. Relative order is
    /// preserved within each group. The tuple labels `(first, second)` are a
    /// conscious divergence from `apple/swift-algorithms` `partitioned(by:)`
    /// (which uses `(falseElements, trueElements)`). The closure is
    /// non-escaping `rethrows`.
    ///
    /// ```swift
    /// let (evens, odds) = [1, 2, 3, 4].nebulaPartitioned(by: { $0.isMultiple(of: 2) })
    /// // evens: [2, 4]  (false group)  odds: [1, 3]  (true group)
    /// ```
    public func nebulaPartitioned(by belongsInSecond: (Element) throws -> Bool) rethrows -> (first: [Element], second: [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if try belongsInSecond(element) {
                second.append(element)
            } else {
                first.append(element)
            }
        }
        return (first, second)
    }
}

// MARK: - Key-path sorting

extension Sequence {
    /// Returns the elements sorted ascending (or per `order`) by `keyPath`,
    /// via Foundation `KeyPathComparator`.
    ///
    /// Layers on `sorted(using:)` (Foundation, iOS 15+ / macOS 12+ — below
    /// Nebula's `.v26` floor). The stdlib sort driven by a `SortComparator` is
    /// guaranteed stable (SE-0372). `KeyPathComparator` stores its keypath as
    /// `any KeyPath & Sendable` (verified against the Xcode 27 Beta 3
    /// `Foundation.swiftmodule`), so `keyPath` is accepted as
    /// `any KeyPath<Element, Value> & Sendable`; keypath literals are Sendable
    /// at the call site when their root and value are Sendable. Use this
    /// overload for non-optional keypaths.
    ///
    /// ```swift
    /// people.nebulaSorted(by: \.age)
    /// people.nebulaSorted(by: \.name, order: .reverse)
    /// ```
    public func nebulaSorted<Value>(
        by keyPath: any KeyPath<Element, Value> & Sendable,
        order: SortOrder = .forward
    ) -> [Element] where Value: Comparable {
        sorted(using: KeyPathComparator(keyPath, order: order))
    }

    /// Optional-keypath overload of ``nebulaSorted(by:order:)``.
    ///
    /// `nil` sorts before non-`nil` per `KeyPathComparator`'s optional
    /// handling. Same stability caveats as the non-optional overload.
    public func nebulaSorted<Value>(
        by keyPath: any KeyPath<Element, Value?> & Sendable,
        order: SortOrder = .forward
    ) -> [Element] where Value: Comparable {
        sorted(using: KeyPathComparator(keyPath, order: order))
    }
}

// MARK: - Dictionary merging

extension Dictionary {
    /// Merges `self` with two other dictionaries in one pass, combining
    /// duplicate values with `combine`.
    ///
    /// Layers on the SE-0165 `merging(_:uniquingKeysWith:)` primitive: the
    /// first merge combines `self` with `other`, the second folds in `other2`,
    /// so a key present in all three is reduced left-to-right as
    /// `combine(combine(self, other), other2)`. The closure is non-escaping
    /// `rethrows`.
    ///
    /// ```swift
    /// let a = ["x": 1], b = ["x": 2, "y": 3], c = ["y": 4, "z": 5]
    /// a.nebulaMerging(b, c, uniquingKeysWith: +)
    /// // ["x": 3, "y": 7, "z": 5]
    /// ```
    public func nebulaMerging(
        _ other: Dictionary,
        _ other2: Dictionary,
        uniquingKeysWith combine: (Value, Value) throws -> Value
    ) rethrows -> Dictionary {
        try merging(other, uniquingKeysWith: combine).merging(other2, uniquingKeysWith: combine)
    }
}