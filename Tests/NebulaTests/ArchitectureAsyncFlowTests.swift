//
//  ArchitectureAsyncFlowTests.swift
//  NebulaTests
//
//  Wave H3 — Clean Architecture toolkit async-flow tests (Swift Testing):
//  NebulaResultPipeline (map/flatMap/recover, throw-bridging, short-circuit),
//  AsyncSequence.nebulaChunked(byCount:) / nebulaUniqued(on:) / nebulaUniqued(),
//  and Sendable derivation.
//

import Testing
import Foundation
import Nebula

// MARK: - NebulaResultPipeline

@Suite("NebulaResultPipeline")
struct NebulaResultPipelineTests {
    @Test func mapTransformsSuccess() async {
        let p = NebulaResultPipeline(value: 21)
        let r = await p.map { $0 * 2 }
        guard case .success(let v) = r else { Issue.record("expected success"); return }
        #expect(v == 42)
    }

    @Test func mapShortCircuitsOnFailure() async {
        let err = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "x")
        let p = NebulaResultPipeline<Int>(error: err)
        let r = await p.map { $0 * 2 }
        guard case .failure(let e) = r else { Issue.record("expected failure"); return }
        #expect(e == err)
    }

    @Test func mapBridgesThrownError() async {
        struct Boom: Error {}
        let p = NebulaResultPipeline(value: 1)
        let r = await p.map { (_: Int) -> Int in throw Boom() }
        guard case .failure = r else { Issue.record("expected failure"); return }
    }

    @Test func mapPreservesExistingNebulaError() async {
        let err = NebulaError(code: .init(domain: "D", code: 7), kind: .network, message: "net")
        let p = NebulaResultPipeline(value: 1)
        let r = await p.map { (_: Int) -> Int in throw err }
        guard case .failure(let e) = r else { Issue.record("expected failure"); return }
        #expect(e == err)
    }

    @Test func flatMapTransformsSuccess() async {
        let p = NebulaResultPipeline(value: 3)
        let r = await p.flatMap { Result<Int, NebulaError>.success($0 * 10) }
        guard case .success(let v) = r else { Issue.record("expected success"); return }
        #expect(v == 30)
    }

    @Test func flatMapShortCircuitsOnFailure() async {
        let err = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "x")
        let p = NebulaResultPipeline<Int>(error: err)
        let r = await p.flatMap { Result<Int, NebulaError>.success($0) }
        guard case .failure(let e) = r else { Issue.record("expected failure"); return }
        #expect(e == err)
    }

    @Test func recoverReturnsValueOnSuccess() async {
        let p = NebulaResultPipeline(value: 5)
        let v = await p.recover { _ in 0 }
        #expect(v == 5)
    }

    @Test func recoverFallsBackOnFailure() async {
        let err = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "x")
        let p = NebulaResultPipeline<Int>(error: err)
        let v = await p.recover { _ in 99 }
        #expect(v == 99)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaResultPipeline(value: 1))
    }
}

// MARK: - AsyncSequence ergonomics

private func asyncStream(_ values: [Int]) -> AsyncThrowingStream<Int, any Error> {
    AsyncThrowingStream { continuation in
        Task {
            for v in values { continuation.yield(v) }
            continuation.finish()
        }
    }
}

@Suite("AsyncSequence nebulaChunked / nebulaUniqued")
struct NebulaAsyncSequenceTests {
    @Test func chunkedGroupsByCount() async throws {
        let chunks = asyncStream([1, 2, 3, 4, 5]).nebulaChunked(byCount: 2)
        var collected: [[Int]] = []
        for try await chunk in chunks { collected.append(chunk) }
        #expect(collected == [[1, 2], [3, 4], [5]])
    }

    @Test func chunkedWithEvenCount() async throws {
        let chunks = asyncStream([1, 2, 3, 4]).nebulaChunked(byCount: 2)
        var collected: [[Int]] = []
        for try await chunk in chunks { collected.append(chunk) }
        #expect(collected == [[1, 2], [3, 4]])
    }

    @Test func chunkedEmptyStream() async throws {
        let chunks = asyncStream([]).nebulaChunked(byCount: 2)
        var collected: [[Int]] = []
        for try await chunk in chunks { collected.append(chunk) }
        #expect(collected.isEmpty)
    }

    @Test func uniquedOnKeyKeepsFirstOccurrence() async throws {
        struct Row: Sendable, Equatable { let id: String; let n: Int }
        func rows() -> AsyncThrowingStream<Row, any Error> {
            AsyncThrowingStream { continuation in
                Task {
                    for r in [Row(id: "a", n: 1), Row(id: "b", n: 2), Row(id: "a", n: 3)] {
                        continuation.yield(r)
                    }
                    continuation.finish()
                }
            }
        }
        let unique = rows().nebulaUniqued(on: \.id)
        var collected: [Row] = []
        for try await row in unique { collected.append(row) }
        #expect(collected == [Row(id: "a", n: 1), Row(id: "b", n: 2)])
    }

    @Test func uniquedHashableKeepsFirstOccurrence() async throws {
        let unique = asyncStream([1, 2, 1, 3, 2]).nebulaUniqued()
        var collected: [Int] = []
        for try await v in unique { collected.append(v) }
        #expect(collected == [1, 2, 3])
    }
}