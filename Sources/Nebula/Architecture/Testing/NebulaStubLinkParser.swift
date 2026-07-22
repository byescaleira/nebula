//
//  NebulaStubLinkParser.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. A stub link
//  parser for tests: returns a fixed ``NebulaLinkDestination`` regardless of
//  the link — a canned answer for the system-under-test. A pure `Sendable` struct
//  (no mutable state; `NebulaLinkDestination<Route>` is `Sendable` since `Route`
//  is). Mirrors ``NebulaStubUseCase``'s shape. See
//  vault/07-metodologia/nebula-test-doubles.md.
//

import Foundation

/// A stub link parser: a `Sendable` struct that returns a fixed
/// ``NebulaLinkDestination`` regardless of the link it receives.
///
/// Unlike a ``NebulaSpyLinkParser``, a stub records nothing — it is a canned
/// answer for the system-under-test (typically driving a ``NebulaLinkRouter``
/// backed by a ``NebulaSpyRouter``). `public` in the product target, so it
/// imports into tests and previews.
///
/// ```swift
/// let parser = NebulaStubLinkParser<AppRoute>(.pushStack([.root, .settings]))
/// let spy = NebulaSpyRouter<AppRoute>()
/// let linkRouter = NebulaLinkRouter(router: spy, parser: parser)
/// await linkRouter.open(NebulaLink(url: URL(string: "myapp://x")!))
/// #expect(spy.intents() == [.dismiss, .replaceStack([.root, .settings])])
/// ```
public struct NebulaStubLinkParser<Route: NebulaRoute>: NebulaLinkParser<Route>, Sendable {

    /// The fixed destination returned for every `resolve(_:)` call.
    public let destination: NebulaLinkDestination<Route>

    /// Creates a stub that always returns `destination`.
    public init(_ destination: NebulaLinkDestination<Route>) {
        self.destination = destination
    }

    public func resolve(_ link: NebulaLink) -> NebulaLinkDestination<Route> {
        destination
    }
}