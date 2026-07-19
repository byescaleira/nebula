//
//  NebulaRoute.swift
//  Nebula
//
//  Wave I — Presentation architecture (Foundation-only seams). The **Route**
//  contract: the value type an app pushes onto a navigation stack. A bare
//  `Hashable & Sendable & Codable` marker — Nebula owns the contract; the app's
//  concrete `Route` enums conform. A route is an **identifier value**
// (`case detail(id: UUID)`) not a full model — push identifiers, render models,
//  per the navigation footgun guidance (vault/08-riscos/presentation-architecture-risks.md
//  #10). `Hashable` for `NavigationStack`/typed `[Route]` membership + `Set`
//  dedup; `Sendable` to cross actor boundaries (the router is `@MainActor`);
//  `Codable` for state restoration / deep-link (de)serialization. Presentation
//  patterns (MVVM `@Observable`, the `@Observable Router`) live in the sibling
//  Meridian package — Nebula ships only the Foundation-only model + port + marker.
//  See vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// The contract for a **navigation route** — the value pushed onto a
/// navigation stack.
///
/// A route is an **identifier value**, not a full model: `case detail(id: UUID)`
/// carries the identity needed to render the destination, not the destination's
/// data. The destination view loads its own model from the route's identifier
/// (push identifiers, render models). This keeps the stack cheap, `Codable`,
/// and resilient to stale data on back-navigation.
///
/// Conform your app's `Route` enum to `NebulaRoute`:
///
/// ```swift
/// enum AppRoute: NebulaRoute {
///     case root
///     case detail(id: UUID)
///     case settings
///     case editItem(id: UUID)
/// }
/// ```
///
/// `Hashable` — for typed `[Route]` membership, `Set` dedup, and
/// `NavigationStack`/`navigationDestination(for:)`. `Sendable` — routes cross
/// actor boundaries (the router is `@MainActor`; deep-link parsing may run off
/// the main actor). `Codable` — for state restoration and deep-link
/// (de)serialization. The companion value-type model is ``NebulaNavigationStack``
/// and the navigation-intent port is ``NebulaRouter``; both live in Nebula.
/// The `@Observable` concrete `Router` lives in the sibling Meridian package
/// (SwiftUI-bearing); Nebula stays Foundation-only.
public protocol NebulaRoute: Hashable, Sendable, Codable {}