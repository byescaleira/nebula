//
//  ArchitecturePagedSequenceTests.swift
//  NebulaTests
//
//  Wave N17c — Bodies & downloads. Unit tests for the generic
//  ``NebulaPagedSequence`` (pure — canned `@Sendable` closures, no URLSession):
//  - A. the loop (multi-page chain + stop),
//  - B. error propagation,
//  - C. cancellation (graceful, N17b semantics),
//  - D. value semantics + Sendable.
//
//  See vault/03-padroes/nebula-bodies-downloads.md.
//

import Testing
import Foundation
import Synchronization
@testable import Nebula

// MARK: - A Sendable box so a ~Copyable Mutex can be captured in @Sendable
// closures (mirrors ArchitectureSSETests).

private final class SendableBox<T: Sendable>: Sendable {
    private let mutex: Mutex<T>
    init(_ initial: T) { mutex = Mutex<T>(initial) }
    func mutate(_ body: (inout T) -> Void) { mutex.withLock { body(&$0) } }
    var value: T { mutex.withLock { $0 } }
}

/// A test page carrying a cursor.
private struct TestPage: Sendable, Equatable {
    let index: Int
    let hasMore: Bool
}

@Suite struct ArchitecturePagedSequenceTests {

    // MARK: - A. Pure loop

    @Test func yieldsPagesUntilNextReturnsNil() async throws {
        let pages = NebulaPagedSequence(
            first: { TestPage(index: 0, hasMore: true) },
            next: { page in
                guard page.hasMore else { return nil }
                return TestPage(index: page.index + 1, hasMore: page.index + 1 < 3)
            })
        var collected: [TestPage] = []
        for try await page in pages.stream() { collected.append(page) }
        #expect(collected.map(\.index) == [0, 1, 2, 3])
    }

    @Test func yieldsSinglePageWhenNextAlwaysNil() async throws {
        let pages = NebulaPagedSequence(
            first: { TestPage(index: 7, hasMore: false) },
            next: { _ in nil })
        var collected: [TestPage] = []
        for try await page in pages.stream() { collected.append(page) }
        #expect(collected.map(\.index) == [7])
    }

    // MARK: - B. Error propagation

    @Test func firstThrowingFinishesStreamWithError() async throws {
        struct Boom: Error, Equatable {}
        let pages = NebulaPagedSequence<TestPage>(
            first: { throw Boom() },
            next: { _ in nil })
        await #expect(throws: Boom.self) {
            for try await _ in pages.stream() {}
        }
    }

    @Test func nextThrowingFinishesStreamWithError() async throws {
        struct Boom: Error, Equatable {}
        let pages = NebulaPagedSequence(
            first: { TestPage(index: 0, hasMore: true) },
            next: { _ in throw Boom() })
        await #expect(throws: Boom.self) {
            for try await _ in pages.stream() {}
        }
    }

    // MARK: - C. Cancellation (graceful — N17b semantics)

    @Test func cancellationEndsIterationGracefully() async throws {
        // A hanging `next` closure (blocks on a Mutex gate) keeps the loop
        // mid-fetch. Cancelling the consumer's Task must end the iteration
        // promptly (no hang): the consumer's `for try await` ends normally
        // (Iterator.next() returns nil on cancellation — it does NOT throw
        // CancellationError), and onTermination cancels the internal loop.
        let gate = SendableBox<Bool>(false)
        let pages = NebulaPagedSequence(
            first: { TestPage(index: 0, hasMore: true) },
            next: { _ in
                // Spin-wait for the gate (cheap; the test cancels promptly).
                while !gate.value { try await Task.sleep(nanoseconds: 5_000_000) }
                return nil
            })
        let task = Task { () -> [TestPage] in
            var collected: [TestPage] = []
            for try await page in pages.stream() { collected.append(page) }
            return collected
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        // Returns promptly — the consumer's loop ends normally on cancel.
        let collected = try await task.value
        #expect(collected.map(\.index) == [0])   // first page yielded before the hang
    }

    // MARK: - D. Value semantics + Sendable

    @Test func twoSequencesAreIndependent() async throws {
        let a = NebulaPagedSequence(
            first: { TestPage(index: 100, hasMore: false) },
            next: { _ in nil })
        let b = NebulaPagedSequence(
            first: { TestPage(index: 200, hasMore: false) },
            next: { _ in nil })
        let pa = try await collect(a.stream())
        let pb = try await collect(b.stream())
        #expect(pa.map(\.index) == [100])
        #expect(pb.map(\.index) == [200])
    }

    @Test func sequenceIsSendableAcrossTask() async throws {
        let pages = NebulaPagedSequence(
            first: { TestPage(index: 5, hasMore: false) },
            next: { _ in nil })
        // Sendable transfer across an actor boundary.
        let collected = try await Task { try await collect(pages.stream()) }.value
        #expect(collected.map(\.index) == [5])
    }

    private func collect(_ stream: AsyncThrowingStream<TestPage, any Error>) async throws -> [TestPage] {
        var out: [TestPage] = []
        for try await page in stream { out.append(page) }
        return out
    }
}