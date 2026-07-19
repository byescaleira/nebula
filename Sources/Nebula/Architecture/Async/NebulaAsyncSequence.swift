//
//  NebulaAsyncSequence.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. Async-sequence ergonomics mirroring the
//  Collection `nebula*` helpers: `nebulaChunked(byCount:)` and
//  `nebulaUniqued(on:)` / `nebulaUniqued()`. Constrained to `Self: Sendable,
//  Element: Sendable` and returning the concrete `AsyncThrowingStream` (the
//  build closure of `AsyncThrowingStream.init(_:)` is non-`@Sendable`, so the
//  async iteration runs in a `Task` that captures only `Sendable` state). The
//  `nebula*` prefix avoids stdlib namespace pollution. Decision #13. See
//  vault/03-padroes/nebula-async-flow.md.
//

import Foundation

extension AsyncSequence where Self: Sendable, Element: Sendable {

    /// Non-overlapping sub-sequences of up to `count` elements, in order.
    ///
    /// The async analog of `Collection.nebulaChunked(byCount:)`. The last chunk
    /// is shorter when the count does not divide evenly. `count` must be greater
    /// than zero (precondition). Returns a concrete `AsyncThrowingStream` whose
    /// iteration runs in a `Task` capturing only `Sendable` state.
    ///
    /// ```swift
    /// let chunks = stream.nebulaChunked(byCount: 2)
    /// for try await chunk in chunks { … }   // [1, 2], [3, 4], [5]
    /// ```
    public func nebulaChunked(byCount count: Int) -> AsyncThrowingStream<[Element], any Error> {
        precondition(count > 0, "Nebula: nebulaChunked(byCount:) requires count > 0")
        let sequence = self
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var chunk: [Element] = []
                    for try await element in sequence {
                        chunk.append(element)
                        if chunk.count == count {
                            continuation.yield(chunk)
                            chunk = []
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension AsyncSequence where Self: Sendable, Element: Sendable {

    /// First-occurrence-preserving dedup keyed by `key`, async.
    ///
    /// The async analog of `Sequence.nebulaUniqued(on:)`. Keeps the first element
    /// whose `key(element)` has not been seen and drops later duplicates. The
    /// `key` closure is `@Sendable`. Returns a concrete `AsyncThrowingStream`.
    ///
    /// ```swift
    /// let unique = stream.nebulaUniqued(on: \.id)
    /// ```
    public func nebulaUniqued<Key: Hashable & Sendable>(
        on key: @Sendable @escaping (Element) -> Key
    ) -> AsyncThrowingStream<Element, any Error> {
        let sequence = self
        return AsyncThrowingStream { continuation in
            Task {
                var seen = Set<Key>()
                do {
                    for try await element in sequence {
                        if seen.insert(key(element)).inserted {
                            continuation.yield(element)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension AsyncSequence where Self: Sendable, Element: Sendable, Element: Hashable {

    /// First-occurrence-preserving dedup, async (elements are `Hashable`).
    ///
    /// The async analog of `Sequence.nebulaUniqued()`. Keeps the first appearance
    /// of each element and drops later duplicates. Returns a concrete
    /// `AsyncThrowingStream`.
    ///
    /// ```swift
    /// let unique = stream.nebulaUniqued()
    /// ```
    public func nebulaUniqued() -> AsyncThrowingStream<Element, any Error> {
        nebulaUniqued(on: { $0 })
    }
}