//
//  NebulaInputPort.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Use Case **Input Port**: the seam a
//  controller/adapter calls to invoke an application rule. A bare `Sendable`
//  marker — Nebula owns the seam; the app's concrete use cases (conforming to
//  ``NebulaUseCase``) and their input DTOs conform. No presentation concerns
//  live here (MVVM/MVC/VIP/VIPER are explicitly out of scope). See
//  vault/03-padroes/nebula-usecase.md.
//

import Foundation

/// A marker for a Clean Architecture **Use Case Input Port**.
///
/// The input port is the seam an outer adapter (a controller, a CLI command,
/// a SwiftUI button action) calls to invoke an application rule. Nebula ships
/// only this seam plus the generic ``NebulaUseCase`` struct; the app's
/// concrete use cases conform.
///
/// A bare `Sendable` marker in v1 — no `Equatable` refinement, since input
/// payloads vary in shape and equality is the payload's own decision. Input
/// payloads should conform to ``NebulaDTO``.
public protocol NebulaInputPort: Sendable {}