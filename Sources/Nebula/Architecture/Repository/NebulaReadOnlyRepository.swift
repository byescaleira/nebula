//
//  NebulaReadOnlyRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The read-side repository capability:
//  `stream()` / `count()`. `Element` is unconstrained so read models (projections
//  that are not full entities) are valid. Streaming returns the concrete
//  `AsyncThrowingStream` (a `some AsyncSequence` return is illegal in a protocol
//  requirement — verified against _Concurrency.swiftmodule:1402/1453/1460).
//  See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// A read-side repository capability: `stream()` / `count()`.
///
/// Refines ``NebulaRepository``. `Element` is unconstrained so a read model
/// (a projection that is not a full ``NebulaEntity``) is a valid element.
/// Streaming returns the concrete `AsyncThrowingStream<Element, any Error>`
/// — a `some AsyncSequence` return type is illegal in a protocol requirement
/// (opaque return in a protocol method needs a primary associated type on
/// `AsyncSequence`, which `AsyncThrowingStream`'s `Failure` is `any Error`).
public protocol NebulaReadOnlyRepository<Element>: NebulaRepository {

    /// Streams all elements, throwing on a read failure (surfaced as a
    /// ``NebulaRepositoryError`` by the app's concrete repository).
    func stream() -> AsyncThrowingStream<Element, any Error>

    /// The number of elements, throwing on a read failure.
    func count() async throws -> Int
}