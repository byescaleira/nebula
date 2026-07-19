//
//  NebulaGatewayConfiguration.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Gateway configuration: a `Sendable`
//  value (NOT `Equatable` — it stores a `@Sendable` closure) carrying the
//  cross-cutting gateway contract (endpoint, headers, codec, logger, timeout,
//  error handler). Fluent `.with*` builders mirror ``NebulaErrorConfiguration``.
//  Reuses ``NebulaJSONDecoder``/``NebulaJSONEncoder`` (does NOT duplicate the
//  Codable configure-once-and-freeze discipline). See
//  vault/03-padroes/nebula-repository.md.
//

import Foundation

/// The Nebula gateway configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` handler
/// closure, which cannot be compared, mirroring ``NebulaErrorConfiguration``)
/// describing how an app-provided ``NebulaGateway`` talks to its external
/// system:
///
/// - ``endpoint`` — the base URL (optional so a gateway can target multiple
///   endpoints resolved per-request);
/// - ``headers`` — default request headers;
/// - ``decoder`` / ``encoder`` — the ``NebulaJSONDecoder`` / ``NebulaJSONEncoder``
///   reused from the Codable extensions (NOT re-declared);
/// - ``logger`` — an optional ``NebulaLogger`` for gateway-level logging;
/// - ``timeout`` — an optional `Duration` request timeout;
/// - ``handler`` — invoked with a ``NebulaErrorEvent`` on a gateway error.
///
/// Like the other configurations, this is an immutable `Sendable` struct with
/// fluent `.with*` builders — constructed and passed explicitly (no SwiftUI
/// `@Environment`).
public struct NebulaGatewayConfiguration: Sendable {

    /// The base endpoint URL (`nil` so a gateway can target multiple endpoints).
    public let endpoint: URL?
    /// Default request headers.
    public let headers: [String: String]
    /// The JSON decoder used to decode responses.
    public let decoder: NebulaJSONDecoder
    /// The JSON encoder used to encode requests.
    public let encoder: NebulaJSONEncoder
    /// An optional logger for gateway-level logging.
    public let logger: NebulaLogger?
    /// An optional request timeout.
    public let timeout: Duration?
    /// Invoked with a ``NebulaErrorEvent`` on a gateway error. The default
    /// `{ _ in }` is capture-free and trivially `Sendable`.
    public let handler: @Sendable (NebulaErrorEvent) -> Void

    /// Creates a configuration.
    public init(
        endpoint: URL? = nil,
        headers: [String: String] = [:],
        decoder: NebulaJSONDecoder = NebulaJSONDecoder(),
        encoder: NebulaJSONEncoder = NebulaJSONEncoder(),
        logger: NebulaLogger? = nil,
        timeout: Duration? = nil,
        handler: @escaping @Sendable (NebulaErrorEvent) -> Void = { _ in }
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.decoder = decoder
        self.encoder = encoder
        self.logger = logger
        self.timeout = timeout
        self.handler = handler
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive).
    public static let `default` = NebulaGatewayConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the endpoint replaced.
    public func withEndpoint(_ endpoint: URL?) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the headers replaced.
    public func withHeaders(_ headers: [String: String]) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the decoder replaced.
    public func withDecoder(_ decoder: NebulaJSONDecoder) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the encoder replaced.
    public func withEncoder(_ encoder: NebulaJSONEncoder) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the logger replaced.
    public func withLogger(_ logger: NebulaLogger?) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the timeout replaced.
    public func withTimeout(_ timeout: Duration?) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaErrorEvent) -> Void) -> NebulaGatewayConfiguration {
        .init(endpoint: endpoint, headers: headers, decoder: decoder, encoder: encoder, logger: logger, timeout: timeout, handler: handler)
    }

    // MARK: - Reporting

    /// Reports `error` to ``handler`` as a ``NebulaErrorEvent`` (no `isEnabled`
    /// gate — gate at the concrete gateway by passing a disabled config).
    public func report(_ error: NebulaError) {
        handler(NebulaErrorEvent(category: "Nebula.Gateway", error: error))
    }
}