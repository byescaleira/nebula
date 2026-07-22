//
//  MeridianTabView.swift
//  Meridian
//
//  Wave N20 — The SwiftUI tab-container adapter. `TabView` with the modern
//  `Tab(value:)` builder (iOS 18/macOS 15, below the `.v26` floor — no
//  `@available` gate) + one `Router` per tab (the documented "never share a
//  path across tabs" footgun). The owner supplies a `Tab: CaseIterable &
//  Hashable & Sendable` enum and a `@ViewBuilder content` closure keyed by it;
//  `content(tab)` returns each tab's root (typically a
//  ``MeridianNavigationStack`` with its own `Router`). `MeridianTabView`
//  iterates `Tab.allCases`, wrapping each in `Tab(value:)` so SwiftUI renders a
//  real tab bar and keeps each tab alive. The modern trio at `.v26` is
//  `NavigationStack` + `NavigationSplitView` + `TabView`. See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import SwiftUI
import Nebula

/// A `TabView` with a typed, `Sendable`, `CaseIterable` selection and a per-tab
/// content closure — one `Router` per tab.
///
/// The tab container for multi-section apps. The owner supplies a `Tab` enum
/// (`CaseIterable & Hashable & Sendable`) and a `@ViewBuilder content` closure
/// keyed by it; `content(tab)` returns each tab's root view — typically a
/// ``MeridianNavigationStack`` with its own ``Router`` (the "one Router per
/// tab" rule — never share a path across tabs). `MeridianTabView` iterates
/// `Tab.allCases`, wrapping each root in `Tab(value:)` so SwiftUI renders a
/// real tab bar and keeps every tab's state alive.
///
/// Uses the modern `Tab(value:)` builder (iOS 18/macOS 15, below `.v26`).
///
/// ```swift
//  enum AppTab: CaseIterable, Hashable, Sendable { case items, settings }
//
//  MeridianTabView(selection: .items) { tab in
//      switch tab {
//      case .items:    MeridianNavigationStack(router: itemsRouter) { ItemsRoot() } destination: { … }
//      case .settings: MeridianNavigationStack(router: settingsRouter) { SettingsRoot() } destination: { … }
//      }
//  }
//  ```
public struct MeridianTabView<Tab: CaseIterable & Hashable & Sendable, Content: View>: View {

    @State private var selection: Tab
    @ViewBuilder private let content: (Tab) -> Content

    /// Creates a tab view with `selection` (the initial selected tab) and a
    /// `content` closure returning each tab's root view keyed by `Tab`.
    public init(
        selection: Tab,
        @ViewBuilder content: @escaping (Tab) -> Content
    ) {
        self._selection = State(initialValue: selection)
        self.content = content
    }

    public var body: some View {
        TabView(selection: $selection) {
            // Iterate every tab so SwiftUI renders a real tab bar and keeps
            // each tab's state alive. The content closure returns each tab's
            // root (one Router per tab — never share a path across tabs).
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                SwiftUI.Tab(value: tab) {
                    content(tab)
                }
            }
        }
    }
}