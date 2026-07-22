//
//  NebulaPresentationStyle.swift
//  Nebula
//
//  Wave N20 — Presentation navigation styles. The **per-route presentation style**:
//  how a given route should appear when presented — pushed onto the stack, a
//  sheet, or a full-screen cover. A bare `Sendable`/`Equatable`/`Hashable`/
//  `Codable` enum (a value type with no stored state — all four conformances are
//  trivially derived, no `@unchecked`). Declared on the route via
//  ``NebulaRoute/presentationStyle`` (which defaults to `.push`, so existing
//  conformers auto-conform — additive); the router dispatches by the declared
//  style, and `present(_:as:)` overrides it at the call site. Nebula ships only
//  the style + the navigation-as-data model (``NebulaPresentation``) + the intent
//  port (``NebulaPresentationRouter``); the SwiftUI adapters (`.sheet`/
//  `.fullScreenCover`, `NavigationSplitView`, `TabView`) live in the sibling
//  Meridian package. See vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// How a route is presented — pushed onto the stack, a sheet, or a full-screen
/// cover.
///
/// Declared **per route** via ``NebulaRoute/presentationStyle``: an app's `Route`
/// enum overrides the default (`.push`) to declare, e.g., that `.share(id:)` is
/// a sheet and `.login` is a full-screen cover. The router then dispatches by
/// the route's declared style — `present(_:)` pushes a `.push` route and
/// modally presents a `.sheet`/`.fullScreenCover` route — while `present(_:as:)`
/// overrides the declared style at the call site (the "present this `.push`
/// route as a sheet *here*" escape hatch).
///
/// A bare value enum with no stored state — `Sendable` (crosses actor
/// boundaries; the router is `@MainActor`), `Equatable`/`Hashable` (asserts
/// with `==`, usable as a dictionary key), `Codable` (state restoration of the
/// modal slot alongside the typed `[Route]` path).
///
/// ```swift
/// enum AppRoute: NebulaRoute {
///     case root, detail(id: UUID)
///     case share(id: UUID)   // sheet
///     case login             // full-screen cover
///     var presentationStyle: NebulaPresentationStyle {
///         switch self {
///         case .share: return .sheet
///         case .login: return .fullScreenCover
///         default:   return .push
///         }
///     }
/// }
/// ```
public enum NebulaPresentationStyle: Sendable, Equatable, Hashable, Codable {

    /// Push the route onto the typed `[Route]` stack (the default).
    case push

    /// Present the route as a modal sheet.
    case sheet

    /// Present the route as a full-screen cover.
    case fullScreenCover

    /// `true` for the modal styles (`.sheet`/`.fullScreenCover`); `false` for
    /// `.push`. The Meridian adapter uses this to pick `.sheet(isPresented:)`
    /// vs `.fullScreenCover(isPresented:)`.
    public var isModal: Bool { self != .push }
}