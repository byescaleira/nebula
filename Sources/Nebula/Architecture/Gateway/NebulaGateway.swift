//
//  NebulaGateway.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Gateway seam (Martin Fowler): "An
//  object that encapsulates access to an external system or resource." A bare
//  `Sendable` marker — Nebula ships only the seam plus
//  ``NebulaGatewayConfiguration``/``NebulaGatewayConfig``; the app provides the
//  concrete gateway (URLSession, etc.). NebulaHTTPGateway is deferred to keep
//  v1 surface lean (decision #8-resolved). See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// A Clean Architecture **Gateway**: an object that encapsulates access to an
/// external system or resource (Fowler).
///
/// A bare `Sendable` marker. Nebula ships only this seam plus
/// ``NebulaGatewayConfiguration`` (the configure-once-and-freeze value) and
/// ``NebulaGatewayConfig`` (the process-wide accessor). The app provides the
/// concrete gateway — a `URLSession`-backed struct, a gRPC client, a Core
/// Location wrapper — conforming to this protocol. Nebula defines no
/// `URLSession` symbol and ships no `NebulaHTTPGateway` in v1 (deferred to keep
/// the toolkit surface lean; revisit if a HTTP helper earns a second use).
public protocol NebulaGateway: Sendable {}