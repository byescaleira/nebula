//
//  NebulaSpyLinkParser.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. A spy link
//  parser for tests: records every ``NebulaLink`` it receives, then returns a
//  configurable ``NebulaLinkDestination`` (`.unhandled` by default). A `final
//  class` with a `let Mutex<[NebulaLink]>` buffer; `Sendable` is **derived** (a
//  `final class` whose stored properties are all immutable `let` of `Sendable`
//  types synthesizes `Sendable` — no `@unchecked`), so a spy can be shared
//  across tasks. Mirrors ``NebulaSpyRouter``/``NebulaSpyUseCase``. See
//  vault/07-metodologia/nebula-test-doubles.md.
//

import Foundation
import Synchronization

/// A spy link parser: records every ``NebulaLink`` it receives, then returns a
/// configurable ``NebulaLinkDestination`` (``NebulaLinkDestination/unhandled``
/// by default).
///
/// A `final class` with a `let Mutex<[NebulaLink]>` buffer. `Sendable` is
/// **derived** — a `final class` whose stored properties are all immutable `let`
/// of `Sendable` types synthesizes `Sendable` (no `@unchecked`), so a spy can be
/// shared across tasks (mirrors ``NebulaSpyRouter``/``NebulaSpyUseCase``). Use
/// ``callCount``/``links()`` to assert on which links the system-under-test
/// forwarded. `public` in the product target, so it imports into tests and
/// previews.
///
/// ```swift
/// let spy = NebulaSpyLinkParser<AppRoute>()
/// _ = spy.resolve(NebulaLink(url: URL(string: "myapp://x")!))
/// #expect(spy.callCount == 1)
/// #expect(spy.links().first?.url?.absoluteString == "myapp://x")
/// ```
public final class NebulaSpyLinkParser<Route: NebulaRoute>: NebulaLinkParser<Route>, Sendable {

    private let invocations = Mutex<[NebulaLink]>([])

    /// The destination returned for every `resolve(_:)` call (`.unhandled` by
    /// default — a pure recorder).
    public let destination: NebulaLinkDestination<Route>

    /// Creates a spy that records links and returns `destination` (defaults to
    /// `.unhandled`).
    public init(destination: NebulaLinkDestination<Route> = .unhandled) {
        self.destination = destination
    }

    /// The number of links recorded so far.
    public var callCount: Int {
        invocations.withLock { $0.count }
    }

    /// A snapshot of the recorded links, in call order.
    public func links() -> [NebulaLink] {
        invocations.withLock { $0 }
    }

    public func resolve(_ link: NebulaLink) -> NebulaLinkDestination<Route> {
        invocations.withLock { $0.append(link) }
        return destination
    }
}