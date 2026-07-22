//
//  NebulaCompositeLinkParser.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. A
//  **composite link parser**: holds an ordered `[any NebulaLinkParser<Route>]`
//  and returns the first non-``NebulaLinkDestination/unhandled`` result — so the
//  app registers scheme/domain/source-specific parsers (one for `myapp://`, one
//  for `https://myapp.com`, one for shortcuts, …) and composes them. A pure
//  `Sendable` struct (an array of `Sendable` existentials — `NebulaLinkParser`
//  is `: Sendable`, so `any NebulaLinkParser<Route>` is `Sendable`; no
//  `@unchecked`). See vault/03-padroes/nebula-deep-links.md.
//

import Foundation

/// A composite link parser: the first registered parser that recognizes the
/// link wins.
///
/// Holds an ordered `[any NebulaLinkParser<Route>]` and returns the first
/// non-``NebulaLinkDestination/unhandled`` result; if every parser returns
/// `.unhandled`, the composite returns `.unhandled`. Register parsers in
/// priority order — e.g. a `myapp://` scheme parser, then a
/// `https://myapp.com` universal-link parser, then a shortcut parser — and the
/// composite dispatches by the first match.
///
/// A pure `Sendable` struct: `NebulaLinkParser` is `: Sendable`, so the
/// `[any NebulaLinkParser<Route>]` is `Sendable` (no `@unchecked`).
///
/// ```swift
/// let parser = NebulaCompositeLinkParser<AppRoute>([
///     SchemeLinkParser(),      // myapp://
///     UniversalLinkParser(),   // https://myapp.com
///     ShortcutLinkParser(),    // .shortcut
/// ])
/// let router = NebulaLinkRouter(router: tabRouter, parser: parser)
/// ```
public struct NebulaCompositeLinkParser<Route: NebulaRoute>: NebulaLinkParser<Route>, Sendable {

    /// The registered parsers, consulted in order.
    public let parsers: [any NebulaLinkParser<Route>]

    /// Creates a composite from `parsers`, consulted in order.
    public init(_ parsers: [any NebulaLinkParser<Route>]) {
        self.parsers = parsers
    }

    public func resolve(_ link: NebulaLink) -> NebulaLinkDestination<Route> {
        for parser in parsers {
            let result = parser.resolve(link)
            if result != .unhandled {
                return result
            }
        }
        return .unhandled
    }
}