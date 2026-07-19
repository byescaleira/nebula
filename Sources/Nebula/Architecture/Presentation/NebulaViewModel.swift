//
//  NebulaViewModel.swift
//  Nebula
//
//  Wave I — Presentation architecture (Foundation-only seams). The **viewmodel
//  marker**: the bare contract an app's presentation model conforms. Nebula
//  ships ONLY the marker — NOT `@Observable`. `@Observable` is Observation-module
//  (SE-0395, not SwiftUI, doesn't pull Combine), so a `NebulaViewModel` *could*
//  conform to `Observable` in a Foundation-only target — but `@Observable`
//  outside SwiftUI has real Swift 6 friction (`withObservationTracking`'s
//  `@Sendable`/one-shot/`willSet` semantics, `@MainActor` isolation conflicts —
//  Donny Wals/Jared Sinclair; vault/08-riscos/presentation-architecture-risks.md
//  #3). Per Nebula's "no SwiftUI, app supplies its own `@Observable`/isolation"
//  stance, the consumer (the sibling Meridian package or the app) adds
//  `@MainActor @Observable final class`; Nebula ships the marker it conforms to.
//  A bare `Sendable` marker (a `@MainActor @Observable` class is `Sendable` by
//  isolation, so the conformance is free). See vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// The marker for a **viewmodel** — the presentation model an app's screen
/// conforms to.
///
/// A bare `Sendable` marker. Nebula ships **only the marker** — the consumer
/// adds `@Observable`:
///
/// ```swift
/// // In Meridian / the app — the consumer owns `@Observable` + isolation.
/// @MainActor @Observable
/// final class ProfileViewModel: NebulaViewModel {
///     var profile: Profile?
///     let useCase: NebulaUseCase<LoadProfileInput, Profile>
///     let router: any NebulaRouter<AppRoute>
///     init(useCase: NebulaUseCase<LoadProfileInput, Profile>,
///          router: any NebulaRouter<AppRoute>) {
///         self.useCase = useCase
///         self.router = router
///     }
///     func load(_ id: UUID) async {
///         profile = try? await useCase.execute(.init(id: id))
///     }
/// }
/// ```
///
/// Nebula does **not** ship `@Observable`: it is Observation-module (not
/// SwiftUI), but using it outside SwiftUI under Swift 6 has real friction
/// (`withObservationTracking`'s `@Sendable`/one-shot/`willSet` semantics,
/// `@MainActor` isolation conflicts). The consumer's `@MainActor @Observable
/// final class` is `Sendable` by isolation, so conforming to this marker is
/// free. Navigation state stays in the router (``NebulaRouter``), not the
/// viewmodel — keeping the viewmodel testable and deep-link-replayable.
public protocol NebulaViewModel: Sendable {}