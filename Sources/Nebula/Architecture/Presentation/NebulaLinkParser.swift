//
//  NebulaLinkParser.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. The
//  **link-parser port**: the seam the app conforms to translate a
//  ``NebulaLink`` into a ``NebulaLinkDestination``. A `Sendable` protocol with
//  a primary associated type `Route: NebulaRoute` (SE-0346), mirroring
//  ``NebulaRouter`` — so it can be used as `any NebulaLinkParser<AppRoute>` or
//  `some NebulaLinkParser<AppRoute>`, and composed in a
//  ``NebulaCompositeLinkParser``'s `[any NebulaLinkParser<Route>]`. `resolve`
//  is **synchronous and pure** for v1 — URL parsing is synchronous; an async
//  path (e.g. a parser needing a DB/API lookup) is added later as a **default
//  extension method**, never a new requirement (requirements break conformers +
//  `any` existentials). See vault/03-padroes/nebula-deep-links.md.
//

import Foundation

/// The link-parser port: translate a ``NebulaLink`` into the navigation intent
/// the router should enact.
///
/// The app conforms a parser (or several, composed via
/// ``NebulaCompositeLinkParser``) for its URL scheme / universal-link domain /
/// shortcut / notification shapes — `URLComponents` parses the URL, the parser
/// maps to a ``NebulaLinkDestination``. `Sendable` with a primary associated
/// type `Route: NebulaRoute` (SE-0346), so it composes as
/// `any NebulaLinkParser<Route>` and the ``NebulaLinkRouter`` can hold it
/// existentially.
///
/// `resolve(_:)` is **synchronous and pure** for v1 — URL parsing is
/// synchronous, and the value returned is plain data. If a future parser needs
/// an async lookup (e.g. resolving a slug → id via an API), add it as a
/// **default extension method** `resolveAsync(_:)` that calls `resolve(_:)` by
/// default — async-capable parsers override it. **Never** add an async
/// `resolve` as a new protocol requirement: that would break every conformer
/// and every `any NebulaLinkParser` existential. Sync concrete impls stay valid.
///
/// ```swift
/// struct AppLinkParser: NebulaLinkParser {
///     typealias Route = AppRoute
///     func resolve(_ link: NebulaLink) -> NebulaLinkDestination<AppRoute> {
///         guard let url = link.url,
///               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
///         else { return .unhandled }
///         let segments = comps.path.split(separator: "/").map(String.init)
///         switch segments.last {
///         case "settings":    return .pushStack([.root, .settings])
///         case let s where UUID(uuidString: s) != nil:
///             return .pushStack([.root, .detail(id: UUID(uuidString: s)!)])
///         default:            return .unhandled
///         }
///     }
/// }
/// ```
public protocol NebulaLinkParser<Route>: Sendable {
    /// The route type this parser resolves links into.
    associatedtype Route: NebulaRoute

    /// Resolves `link` to a navigation destination, or ``NebulaLinkDestination/unhandled``
    /// if the parser does not recognize it.
    func resolve(_ link: NebulaLink) -> NebulaLinkDestination<Route>
}