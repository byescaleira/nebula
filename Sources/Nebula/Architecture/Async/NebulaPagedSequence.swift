//
//  NebulaPagedSequence.swift
//  Nebula
//
//  Wave N17c — Bodies & downloads. A generic pagination helper: a
//  `Sendable` struct that yields pages through an `AsyncThrowingStream` (the
//  CLAUDE.md-mandated concrete return type — `some AsyncSequence` is illegal
//  in a protocol requirement and this stream is returned from a `func`).
//
//  The app supplies two `@Sendable` closures — `first` (fetch the first page)
//  and `next(_:)` (fetch the next page given the current one, or `nil` to
//  stop). This decouples **cursor transport** (the app's concern — a URL query
//  item, a header, a body token) from the **loop** (Nebula's concern): the app
//  extracts the cursor from the page and either fetches the next page or
//  returns `nil`. Nebula is generic over `Page` (the app decodes its own page
//  shape); it carries no HTTP-specific cursor knowledge.
//
//  The loop is **custom** (NOT ``NebulaRetry/withPolicy``): the request/cursor
//  mutates per page (the SSE `Last-Event-ID` shape), and `withPolicy`'s
//  `operation` is nullary — it cannot carry the mutating cursor. Pagination
//  does not retry a failed page — it surfaces the error; the app composes
//  ``NebulaRetry/withPolicy`` around the `first`/`next` closures if it wants
//  per-page retry.
//
//  Cancellation mirrors ``NebulaSSEEventStream``: the consumer's `for try
//  await` ends **normally** on cancellation (an `AsyncThrowingStream` does not
//  throw `CancellationError` to its consumer; `Iterator.next()` returns `nil`).
//  The internal `finish(throwing: CancellationError())` tears the internal loop
//  down cleanly via `onTermination → loop.cancel()`. `Task.checkCancellation()`
//  is honored before each fetch.
//
//  `Sendable` is **derived** — `Page: Sendable` is constrained at the
//  declaration (the ``NebulaResultPipeline`` precedent), the two `@Sendable`
//  closures are `Sendable`, and `AsyncThrowingStream<Page, any Error>` is
//  `Sendable` when `Page: Sendable`. **No `@unchecked`.** Below the `.v26`
//  floor (`AsyncThrowingStream` is macOS 10.15 / iOS 13 / watchOS 6 / tvOS 13)
//  — **no `@available` gate**. `import Foundation` only. See
//  vault/03-padroes/nebula-bodies-downloads.md.
//

import Foundation

/// A generic pagination helper that yields `Page`s through an
/// `AsyncThrowingStream`.
///
/// The app supplies `first` (fetch the first page) and `next(_:)` (fetch the
/// next page given the current one, or `nil` to stop). Cursor transport is the
/// app's concern — Nebula is generic over `Page` and carries no HTTP-specific
/// cursor knowledge. Pagination does not retry a failed page (surfaces the
/// error); compose ``NebulaRetry/withPolicy`` around the closures for per-page
/// retry.
///
/// ```swift
/// let pages = NebulaPagedSequence(
///     first: { try await fetch(page: 0) },
///     next: { current in current.hasMore ? try await fetch(page: current.next) : nil })
/// for try await page in pages.stream() { /* … */ }
/// ```
public struct NebulaPagedSequence<Page: Sendable>: Sendable {

    /// Fetches the first page.
    public let first: @Sendable () async throws -> Page

    /// Fetches the next page given the current one, or `nil` to stop.
    public let next: @Sendable (Page) async throws -> Page?

    /// Creates the sequence.
    /// - Parameters:
    ///   - first: fetches the first page.
    ///   - next: fetches the next page given the current one, or `nil` to stop
    ///     (the app extracts the cursor from the page).
    public init(
        first: @escaping @Sendable () async throws -> Page,
        next: @escaping @Sendable (Page) async throws -> Page?
    ) {
        self.first = first
        self.next = next
    }

    /// Yields pages through an `AsyncThrowingStream<Page, any Error>` — the
    /// CLAUDE.md-mandated concrete return type. The internal loop fetches the
    /// first page, then repeatedly fetches the next page until `next` returns
    /// `nil`. Cancellation is honored before each fetch; the consumer's
    /// iteration ends normally on cancellation (`onTermination` cancels the
    /// loop). A thrown error from `first`/`next` finishes the stream with the
    /// error (the error is rethrown to the consumer — pagination surfaces
    /// errors, it does not retry them).
    public func stream() -> AsyncThrowingStream<Page, any Error> {
        AsyncThrowingStream { continuation in
            let first = self.first
            let nextClosure = self.next
            let loop = Task {
                do {
                    try Task.checkCancellation()
                    var page = try await first()
                    continuation.yield(page)
                    while true {
                        try Task.checkCancellation()
                        guard let next = try await nextClosure(page) else {
                            continuation.finish()
                            return
                        }
                        page = next
                        continuation.yield(page)
                    }
                } catch is CancellationError {
                    // The consumer's iteration ends normally on cancellation
                    // (Iterator.next() returns nil); the internal finish tears
                    // the loop down cleanly.
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in loop.cancel() }
        }
    }
}