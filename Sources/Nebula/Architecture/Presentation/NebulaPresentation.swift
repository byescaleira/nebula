//
//  NebulaPresentation.swift
//  Nebula
//
//  Wave N20 — Presentation navigation styles. The **navigation-as-data model**
//  that owns the push path *and* the modal slot — the pure-Swift extension of
//  ``NebulaNavigationStack`` (which stays the push-only model, unchanged). A
//  `Sendable`/`Codable`/`Equatable` struct (all derived: `Route: NebulaRoute` →
//  `Route: Sendable` → `[Route]`/`Route?` Sendable; `Route: Codable` →
//  synthesized; `Route: Equatable` via `Hashable` → synthesized). The present/
//  dismiss logic lives in `static` helpers taking `inout` components, so the
//  `mutating` instance API and the Meridian `@Observable Router` (which owns
//  observable `path`/`presented`/`presentedStyle` props) share one
//  implementation — the same single-source-of-truth pattern as
//  ``NebulaNavigationStack``. Push-path ops (`push`/`pop`/`popToRoot`/
//  `replaceStack`) delegate verbatim to the ``NebulaNavigationStack`` statics,
//  so this model adds the modal layer without duplicating stack logic. See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// The navigation-as-data model owning a typed `[Route]` push path **and** a
/// single modal slot — the pure-Swift extension of ``NebulaNavigationStack``.
///
/// Where ``NebulaNavigationStack`` models only the push stack, this model adds
/// the **modal layer**: a single `Route?` slot (`modal`) plus the style that
/// presented it (`modalStyle` — `.sheet` or `.fullScreenCover`; `nil` ⟺ no
/// modal). One modal at a time matches SwiftUI's `.sheet`/`.fullScreenCover`
/// (only one may be active per binding). `present(_:)` dispatches by the
/// route's declared ``NebulaRoute/presentationStyle`` — a `.push` route
/// appends to `path` (delegating to ``NebulaNavigationStack``); a modal route
/// fills the slot. `present(_:as:)` overrides the declared style at the call
/// site. `dismiss()` clears an active modal, else pops one from the path.
///
/// The present/dismiss logic lives in `static` helpers taking `inout`
/// components (`path`/`modal`/`style`), so the `mutating` instance API and the
/// Meridian `@Observable Router` (observable `path`/`presented`/
/// `presentedStyle`) share one implementation — the same single-source-of-
/// truth pattern as ``NebulaNavigationStack``. Push-path ops delegate to the
/// ``NebulaNavigationStack`` statics (no duplicated stack logic).
///
/// ```swift
/// var p = NebulaPresentation<AppRoute>()
/// p.present(.detail(id: id))   // .push → appends to path
/// p.present(.share(id: id))    // .sheet → fills modal slot, modalStyle = .sheet
/// p.dismiss()                  // modal active → clears it, path untouched
/// p.dismiss()                  // no modal → pops one from path
/// // Codable round-trip restores path + modal + modalStyle.
/// ```
public struct NebulaPresentation<Route: NebulaRoute>: Sendable, Codable, Equatable {

    /// The typed push stack, root-first. The bottom of the array is the root.
    public private(set) var path: [Route]

    /// The active modal route, or `nil` when no sheet/full-screen cover is
    /// presented. A single slot — one modal at a time (matches SwiftUI).
    public private(set) var modal: Route?

    /// The style that presented ``modal`` — `.sheet` or `.fullScreenCover`,
    /// or `nil` when no modal is active. Invariant: `modal == nil ⟺
    /// modalStyle == nil`.
    public private(set) var modalStyle: NebulaPresentationStyle?

    /// Creates a presentation state from `path` (defaulting to empty), `modal`
    /// (defaulting to `nil`), and `modalStyle` (defaulting to `nil`).
    public init(
        path: [Route] = [],
        modal: Route? = nil,
        modalStyle: NebulaPresentationStyle? = nil
    ) {
        self.path = path
        self.modal = modal
        self.modalStyle = modalStyle
    }

    // MARK: Present / dismiss (instance API — delegates to the statics)

    /// Presents `route` by its declared ``NebulaRoute/presentationStyle`` — a
    /// `.push` route appends to ``path``; a `.sheet`/`.fullScreenCover` route
    /// fills the modal slot.
    public mutating func present(_ route: Route) {
        Self.present(route, as: route.presentationStyle, into: &path,
                     modal: &modal, style: &modalStyle)
    }

    /// Presents `route` with `style`, overriding the route's declared style at
    /// the call site.
    public mutating func present(_ route: Route, as style: NebulaPresentationStyle) {
        Self.present(route, as: style, into: &path,
                     modal: &modal, style: &modalStyle)
    }

    /// Dismisses the active modal if one is present; otherwise pops one route
    /// from the path. Never pops while a modal is active (no double-dismiss).
    public mutating func dismiss() {
        Self.dismiss(path: &path, modal: &modal, style: &modalStyle)
    }

    // MARK: Push-path ops — delegate to NebulaNavigationStack statics
    // (single source of truth; this model adds the modal layer, not a stack).

    /// Pushes `route` onto the path. Delegates to
    /// ``NebulaNavigationStack/push(_:into:)``.
    public mutating func push(_ route: Route) {
        NebulaNavigationStack.push(route, into: &path)
    }

    /// Pops `count` routes off the path (clamped; never underflows). Delegates
    /// to ``NebulaNavigationStack/pop(_:into:)``.
    public mutating func pop(_ count: Int = 1) {
        NebulaNavigationStack.pop(count, into: &path)
    }

    /// Pops every route — back to root. Delegates to
    /// ``NebulaNavigationStack/popToRoot(_:)``.
    public mutating func popToRoot() {
        NebulaNavigationStack.popToRoot(&path)
    }

    /// Replaces the path with `routes` — the deep-link primitive. Delegates to
    /// ``NebulaNavigationStack/replaceStack(_:into:)``.
    public mutating func replaceStack(with routes: [Route]) {
        NebulaNavigationStack.replaceStack(routes, into: &path)
    }

    // MARK: Read-only accessors (convenience)

    /// The number of routes above root in the push path.
    public var count: Int { path.count }

    /// `true` when at root and no modal is active.
    public var isEmpty: Bool { path.isEmpty && modal == nil }

    /// The top route of the push path, or `nil` at root.
    public var top: Route? { path.last }

    // MARK: Statics — single source of truth (the instance API and the Meridian
    // @Observable Router both delegate here).

    /// Presents `route` as `style` into the `path`/`modal`/`style` components.
    ///
    /// `.push` → `NebulaNavigationStack.push(route, into: &path)`.
    /// `.sheet`/`.fullScreenCover` → `modal = route; style = style`.
    public static func present(
        _ route: Route,
        as style: NebulaPresentationStyle,
        into path: inout [Route],
        modal: inout Route?,
        style out: inout NebulaPresentationStyle?
    ) {
        switch style {
        case .push:
            NebulaNavigationStack.push(route, into: &path)
        case .sheet, .fullScreenCover:
            modal = route
            out = style
        }
    }

    /// Dismisses the modal if active (`modal = nil; out = nil`); otherwise
    /// pops one route from `path`. Never both.
    public static func dismiss(
        path: inout [Route],
        modal: inout Route?,
        style out: inout NebulaPresentationStyle?
    ) {
        if modal != nil {
            modal = nil
            out = nil
        } else {
            NebulaNavigationStack.pop(1, into: &path)
        }
    }
}