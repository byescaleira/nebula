//
//  NebulaOutputPort.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Use Case **Output Port**: the seam a
//  presenter implements so the use case can hand results back without knowing
//  the presentation layer (the Dependency Inversion Principle — "the use case
//  calls an interface in the inner circle, and the presenter in the outer
//  circle implements it"). A bare `Sendable` marker — Nebula owns the seam; the
//  app/Cosmos owns the conformance. Nebula defines NO presenter/view/viewmodel
//  (presentation patterns are explicitly out of scope). See
//  vault/03-padroes/nebula-clean-architecture-toolkit.md.
//

import Foundation

/// A marker for a Clean Architecture **Use Case Output Port**.
///
/// The output port is the Dependency-Inversion seam: the use case invokes an
/// output port method to hand a result (or a failure) to the outer layer, and
/// a presenter in the outer layer (the app, or Cosmos) implements it. This
/// keeps the dependency pointing **inward** — the use case knows nothing of
/// SwiftUI, UIKit, or any presentation shape.
///
/// Nebula ships only this bare `Sendable` marker. The concrete output-port
/// protocol (its success/failure methods taking ``NebulaDTO``/``NebulaEntity``
/// values and ``NebulaError`` for failures) is defined **per use case in the
/// app** — Nebula defines no presenter, view, or viewmodel, and no
/// presentation pattern (MVVM/MVC/VIP/VIPER) lives in the toolkit.
public protocol NebulaOutputPort: Sendable {}