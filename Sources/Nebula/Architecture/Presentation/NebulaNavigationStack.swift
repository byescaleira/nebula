//
//  NebulaNavigationStack.swift
//  Nebula
//
//  Wave I — Presentation architecture (Foundation-only seams). The **navigation
//  model**: a typed `[Route]` stack as a value type. This is the Foundation-only
//  "real navigation model" (deep-link parsing, back-stack reduction, route
//  logging, state restoration) that collapses the "Foundation-only router is
//  hollow" critique (vault/08-riscos/presentation-architecture-risks.md #6) —
//  navigation-as-data, fully testable in pure Swift with no SwiftUI in the test
//  graph. The stack logic lives in `static func …(into: inout [Route])` helpers;
//  the `mutating` instance methods and the Meridian `@Observable Router` BOTH
//  delegate to them — single source of truth, no duplication. A `Sendable` struct
//  (`Route: Sendable` → `[Route]: Sendable` → derived), `Codable` (`Route:
//  Codable` → synthesized), `Equatable` (`Route: Equatable` via `Hashable` →
//  synthesized). Typed `[Route]` is preferred over type-erased `NavigationPath`
//  (compile-time exhaustive handling, inspectable/reorderable stack — defensive
//  against `NavigationStack`'s reported macOS bugs, risk #4). See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// A typed `[Route]` navigation stack as a value type — the Foundation-only
/// navigation model.
///
/// The navigation model is **data**, not a `@ViewBuilder`-returning router: a
/// `Sendable`/`Codable`/`Equatable` struct over `[Route]` with
/// `push`/`pop`/`popToRoot`/`replaceStack`. Deep links are "build `[Route]`,
/// `replaceStack`" — pure, testable without a simulator. State restoration is
/// `Codable` round-trip. Back-stack reduction and route logging operate on the
/// typed array directly.
///
/// The stack logic lives in `static` helpers taking `inout [Route]` so the
/// `mutating` instance API and the Meridian `@Observable Router` (which owns an
/// observation-tracked `var path: [Route]`) share one implementation:
///
/// ```swift
/// var stack = NebulaNavigationStack<AppRoute>()
/// stack.push(.detail(id: id))      // mutating instance API
/// stack.replaceStack(with: [.root, .detail(id: id)])  // deep link as data
/// #expect(stack.path == [.root, .detail(id: id)])
/// #expect(stack.top == .detail(id: id))
///
/// // Codable round-trip — state restoration.
/// let restored = try JSONDecoder().decode(NebulaNavigationStack<AppRoute>.self,
///                                          from: JSONEncoder().encode(stack))
/// #expect(restored == stack)
/// ```
///
/// Prefer a typed `[Route]` over type-erased `NavigationPath`: compile-time
/// exhaustive handling in `navigationDestination(for: Route.self)`, an
/// inspectable/reorderable stack (matters where `NavigationStack` is reported
/// broken on macOS — risk #4), and trivial `Codable` restoration. Reach for
/// type-erased `NavigationPath` only when pushing genuinely heterogeneous value
/// types.
public struct NebulaNavigationStack<Route: NebulaRoute>: Sendable, Codable, Equatable {

    /// The typed route stack, root-first. The bottom of the array is the root.
    public private(set) var path: [Route]

    /// Creates a stack from `path` (defaulting to empty — at root).
    public init(path: [Route] = []) {
        self.path = path
    }

    /// Pushes `route` onto the top of the stack.
    public mutating func push(_ route: Route) {
        Self.push(route, into: &path)
    }

    /// Pops `count` routes off the top (clamped to `count`, never underflows).
    public mutating func pop(_ count: Int = 1) {
        Self.pop(count, into: &path)
    }

    /// Pops every route — back to root.
    public mutating func popToRoot() {
        Self.popToRoot(&path)
    }

    /// Replaces the whole stack with `routes` — the deep-link primitive
    /// ("parse URL → build `[Route]` → `replaceStack`").
    public mutating func replaceStack(with routes: [Route]) {
        Self.replaceStack(routes, into: &path)
    }

    /// The number of routes above root.
    public var count: Int { path.count }

    /// `true` when at root (no routes above it).
    public var isEmpty: Bool { path.isEmpty }

    /// The top route, or `nil` at root.
    public var top: Route? { path.last }

    /// Pushes `route` onto `path`. Single source of truth for stack mutation —
    /// the instance API and the Meridian `@Observable Router` both delegate here.
    public static func push(_ route: Route, into path: inout [Route]) {
        path.append(route)
    }

    /// Pops `count` routes off `path`, clamped to `path.count` (never underflows).
    public static func pop(_ count: Int = 1, into path: inout [Route]) {
        let safe = max(0, min(count, path.count))
        path.removeLast(safe)
    }

    /// Removes every route from `path` — back to root.
    public static func popToRoot(_ path: inout [Route]) {
        path.removeAll()
    }

    /// Replaces `path` with `routes` — the deep-link primitive.
    public static func replaceStack(_ routes: [Route], into path: inout [Route]) {
        path = routes
    }
}