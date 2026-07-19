//
//  CollectionExtensionsTests.swift
//  NebulaTests
//
//  Tests for the Collection / Sequence / Dictionary `nebula*` ergonomics.
//  Synchronous only (no @Sendable handlers); preconditions are documented,
//  not exercised (a trap would abort the whole run).
//

import Testing
import Foundation
import Nebula

// MARK: - Safe subscript

@Suite("Collection safe subscript")
struct SafeSubscriptTests {
    @Test func arrayInBounds() {
        let a = [10, 20, 30]
        #expect(a[nebulaSafe: 0] == 10)
        #expect(a[nebulaSafe: 1] == 20)
        #expect(a[nebulaSafe: 2] == 30)
    }

    @Test func arrayOutOfBoundsIsNil() {
        let a = [10, 20, 30]
        #expect(a[nebulaSafe: -1] == nil)
        #expect(a[nebulaSafe: 3] == nil)
        #expect(a[nebulaSafe: 100] == nil)
    }

    @Test func emptyArray() {
        let a: [Int] = []
        #expect(a[nebulaSafe: 0] == nil)
    }

    @Test func dictionarySafeAccess() {
        let d = ["x": 1]
        // Dictionary is a Collection but not MutableCollection; the get-only
        // subscript on Collection still applies. An in-bounds Index returns the
        // (key, value) pair. (Constructing an out-of-bounds Dictionary Index
        // itself traps, so the nil path is covered by the array tests above,
        // not exercised here.)
        let idx = d.startIndex
        #expect(d[nebulaSafe: idx]?.key == "x")
        #expect(d[nebulaSafe: idx]?.value == 1)
    }
}

// MARK: - Chunking

@Suite("nebulaChunked")
struct ChunkedTests {
    @Test func evenSplit() {
        #expect([1, 2, 3, 4].nebulaChunked(byCount: 2) == [[1, 2], [3, 4]])
    }

    @Test func shortLastChunk() {
        #expect([1, 2, 3, 4, 5].nebulaChunked(byCount: 2) == [[1, 2], [3, 4], [5]])
    }

    @Test func countLargerThanCollection() {
        #expect([1, 2, 3].nebulaChunked(byCount: 10) == [[1, 2, 3]])
    }

    @Test func countEqualsLength() {
        #expect([1, 2, 3].nebulaChunked(byCount: 3) == [[1, 2, 3]])
    }

    @Test func empty() {
        let empty: [Int] = []
        #expect(empty.nebulaChunked(byCount: 2) == [])
    }

    @Test func singletons() {
        #expect([1, 2, 3].nebulaChunked(byCount: 1) == [[1], [2], [3]])
    }

    @Test func preservesOrder() {
        // String is a Collection<Character>, so chunking yields [[Character]];
        // map back to String for the assertion.
        #expect("abcdef".nebulaChunked(byCount: 2).map { String($0) } == ["ab", "cd", "ef"])
    }
}

// MARK: - Windows

@Suite("nebulaWindows")
struct WindowsTests {
    @Test func slidingPairs() {
        #expect([1, 2, 3, 4].nebulaWindows(ofCount: 2) == [[1, 2], [2, 3], [3, 4]])
    }

    @Test func triples() {
        #expect([1, 2, 3, 4, 5].nebulaWindows(ofCount: 3) == [[1, 2, 3], [2, 3, 4], [3, 4, 5]])
    }

    @Test func countEqualsLength() {
        #expect([1, 2, 3].nebulaWindows(ofCount: 3) == [[1, 2, 3]])
    }

    @Test func countLargerThanCollectionIsEmpty() {
        #expect([1, 2, 3].nebulaWindows(ofCount: 4) == [])
        #expect([Int]().nebulaWindows(ofCount: 1) == [])
    }

    @Test func windowsOfOne() {
        #expect([1, 2, 3].nebulaWindows(ofCount: 1) == [[1], [2], [3]])
    }

    @Test func preservesOrder() {
        // String is a Collection<Character>; map each window back to String.
        #expect("abcd".nebulaWindows(ofCount: 2).map { String($0) } == ["ab", "bc", "cd"])
    }
}

// MARK: - Uniquing

@Suite("nebulaUniqued")
struct UniquedTests {
    @Test func hashableDedupKeepsFirst() {
        #expect([1, 2, 1, 3, 2, 1].nebulaUniqued() == [1, 2, 3])
    }

    @Test func hashableEmpty() {
        #expect([Int]().nebulaUniqued() == [])
    }

    @Test func hashableNoDuplicates() {
        #expect([1, 2, 3].nebulaUniqued() == [1, 2, 3])
    }

    @Test func hashableAllDuplicates() {
        #expect([7, 7, 7].nebulaUniqued() == [7])
    }

    @Test func strings() {
        #expect(["a", "b", "a", "c"].nebulaUniqued() == ["a", "b", "c"])
    }

    struct Person: Hashable, Sendable {
        let id: Int
        let name: String
    }

    @Test func keyedDedupKeepsFirst() {
        let people = [
            Person(id: 1, name: "a"),
            Person(id: 2, name: "b"),
            Person(id: 1, name: "c"),
            Person(id: 3, name: "d")
        ]
        let uniq = people.nebulaUniqued(on: \.id)
        #expect(uniq.count == 3)
        #expect(uniq[0].name == "a")
        #expect(uniq[1].name == "b")
        #expect(uniq[2].name == "d")
    }

    @Test func keyedEmpty() {
        let empty: [Person] = []
        #expect(empty.nebulaUniqued(on: \.id) == [])
    }

    @Test func keyedRethrows() throws {
        enum Boom: Error { case it }
        let people = [Person(id: 1, name: "a")]
        #expect(throws: Boom.it) {
            _ = try people.nebulaUniqued(on: { _ -> Int in throw Boom.it })
        }
    }
}

// MARK: - Stable partition (mutating)

@Suite("nebulaStablePartition")
struct StablePartitionTests {
    @Test func preservesOrderInBothGroups() {
        var a = [1, 2, 3, 4, 5, 6]
        a.nebulaStablePartition(by: { $0.isMultiple(of: 2) })
        // false group (odds) first, preserving order; true group (evens) after.
        #expect(a == [1, 3, 5, 2, 4, 6])
    }

    @Test func allTrue() {
        var a = [1, 2, 3]
        a.nebulaStablePartition(by: { _ in true })
        #expect(a == [1, 2, 3])
    }

    @Test func allFalse() {
        var a = [1, 2, 3]
        a.nebulaStablePartition(by: { _ in false })
        #expect(a == [1, 2, 3])
    }

    @Test func empty() {
        var a: [Int] = []
        a.nebulaStablePartition(by: { _ in true })
        #expect(a == [])
    }

    @Test func singleElement() {
        var a = [1]
        a.nebulaStablePartition(by: { $0.isMultiple(of: 2) })
        #expect(a == [1])
    }

    @Test func rethrowsOnThrowingClosure() {
        enum Boom: Error { case it }
        var a = [1, 2]
        #expect(throws: Boom.it) {
            try a.nebulaStablePartition(by: { _ in throw Boom.it })
        }
    }

    @Test func stableVsStdlibPartitionOnBidirectional() {
        // Demonstrate stability: stdlib partition is half-stable and would
        // reorder the false group; nebulaStablePartition preserves it.
        var stable = [3, 1, 4, 1, 5, 9, 2, 6]
        stable.nebulaStablePartition(by: { $0.isMultiple(of: 2) })
        // Odds (in original order): 3, 1, 1, 5, 9 ; evens: 4, 2, 6
        #expect(stable == [3, 1, 1, 5, 9, 4, 2, 6])
    }
}

// MARK: - Partitioned (non-mutating)

@Suite("nebulaPartitioned")
struct PartitionedTests {
    @Test func splitsAndPreservesOrder() {
        let (odds, evens) = [1, 2, 3, 4, 5].nebulaPartitioned(by: { $0.isMultiple(of: 2) })
        #expect(odds == [1, 3, 5])
        #expect(evens == [2, 4])
    }

    @Test func empty() {
        let (first, second) = [Int]().nebulaPartitioned(by: { _ in true })
        #expect(first == [])
        #expect(second == [])
    }

    @Test func allTrue() {
        let (first, second) = [1, 2, 3].nebulaPartitioned(by: { _ in true })
        #expect(first == [])
        #expect(second == [1, 2, 3])
    }

    @Test func allFalse() {
        let (first, second) = [1, 2, 3].nebulaPartitioned(by: { _ in false })
        #expect(first == [1, 2, 3])
        #expect(second == [])
    }

    @Test func rethrowsOnThrowingClosure() {
        enum Boom: Error { case it }
        #expect(throws: Boom.it) {
            _ = try [1, 2].nebulaPartitioned(by: { _ in throw Boom.it })
        }
    }
}

// MARK: - Key-path sorting

@Suite("nebulaSorted")
struct SortedKeyPathTests {
    struct Item: Sendable, Equatable {
        let id: Int
        let name: String
        let score: Double?
    }

    let items: [Item] = [
        Item(id: 1, name: "b", score: 2.0),
        Item(id: 2, name: "a", score: nil),
        Item(id: 3, name: "c", score: 1.0)
    ]

    @Test func sortByComparableKey() {
        let byName = items.nebulaSorted(by: \.name)
        #expect(byName.map(\.id) == [2, 1, 3])
    }

    @Test func sortByReverseOrder() {
        let byNameDesc = items.nebulaSorted(by: \.name, order: .reverse)
        #expect(byNameDesc.map(\.id) == [3, 1, 2])
    }

    @Test func sortByIntKey() {
        let byId = items.nebulaSorted(by: \.id, order: .reverse)
        #expect(byId.map(\.id) == [3, 2, 1])
    }

    @Test func sortByOptionalKeyPutsNilFirst() {
        let byScore = items.nebulaSorted(by: \.score)
        // nil sorts before non-nil: id 2 (nil), then 1.0 (id 3), then 2.0 (id 1)
        #expect(byScore.map(\.id) == [2, 3, 1])
    }

    @Test func sortByOptionalKeyReverse() {
        let byScoreDesc = items.nebulaSorted(by: \.score, order: .reverse)
        #expect(byScoreDesc.map(\.id) == [1, 3, 2])
    }

    @Test func stableOnEqualKeys() {
        struct P: Sendable, Equatable { let g: Int; let tag: String }
        let data = [
            P(g: 1, tag: "a"), P(g: 1, tag: "b"), P(g: 1, tag: "c"),
            P(g: 0, tag: "z"), P(g: 1, tag: "d")
        ]
        let sorted = data.nebulaSorted(by: \.g)
        // Stable: equal-key order preserved within group 1.
        #expect(sorted.map(\.tag) == ["z", "a", "b", "c", "d"])
    }

    @Test func emptyAndSingle() {
        let empty: [Item] = []
        #expect(empty.nebulaSorted(by: \.id) == [])
        let one = [Item(id: 5, name: "x", score: nil)]
        #expect(one.nebulaSorted(by: \.id).map(\.id) == [5])
    }
}

// MARK: - Dictionary merging

@Suite("nebulaMerging")
struct MergingTests {
    @Test func mergeThreeNoCollisions() {
        let a = ["x": 1, "y": 2]
        let b = ["z": 3]
        let c = ["w": 4]
        let merged = a.nebulaMerging(b, c, uniquingKeysWith: { _, new in new })
        #expect(merged == ["x": 1, "y": 2, "z": 3, "w": 4])
    }

    @Test func mergeCombinesLeftToRight() {
        let a = ["x": 1]
        let b = ["x": 2, "y": 10]
        let c = ["x": 3, "y": 20, "z": 30]
        let merged = a.nebulaMerging(b, c, uniquingKeysWith: +)
        // x: ((1 + 2) + 3) = 6 ; y: (10 + 20) = 30 ; z: 30
        #expect(merged == ["x": 6, "y": 30, "z": 30])
    }

    @Test func mergeKeepExisting() {
        let a = ["x": 1]
        let b = ["x": 2]
        let c = ["x": 3]
        let merged = a.nebulaMerging(b, c, uniquingKeysWith: { existing, _ in existing })
        #expect(merged == ["x": 1])
    }

    @Test func mergeEmpty() {
        let a = ["x": 1]
        let empty: [String: Int] = [:]
        #expect(a.nebulaMerging(empty, empty, uniquingKeysWith: +) == ["x": 1])
        #expect(empty.nebulaMerging(empty, empty, uniquingKeysWith: +) == [:])
    }

    @Test func mergeRethrows() throws {
        enum Boom: Error { case it }
        // Overlapping keys so `combine` is actually invoked and throws.
        let a = ["x": 1]
        let b = ["x": 2]
        let c = ["x": 3]
        #expect(throws: Boom.it) {
            _ = try a.nebulaMerging(b, c, uniquingKeysWith: { _, _ in throw Boom.it })
        }
    }
}