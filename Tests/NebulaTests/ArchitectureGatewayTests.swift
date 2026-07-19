//
//  ArchitectureGatewayTests.swift
//  NebulaTests
//
//  Wave H2 — Clean Architecture toolkit gateway tests (Swift Testing): the
//  NebulaGateway marker, NebulaGatewayConfiguration (default shape, fluent
//  builders, report handler fan-out), the process-wide NebulaGatewayConfig
//  accessor, and Sendable.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - Fixtures

private struct FakeGateway: NebulaGateway {
    let config: NebulaGatewayConfiguration
}

// `ErrorCapture` is reused from ErrorTests.swift (internal, same module).

@Suite("NebulaGateway")
struct NebulaGatewayTests {
    @Test func markerConformance() {
        func consume<T: NebulaGateway>(_ v: T) {}
        consume(FakeGateway(config: .default))
    }
}

@Suite("NebulaGatewayConfiguration")
struct NebulaGatewayConfigurationTests {
    @Test func defaultShape() {
        let d = NebulaGatewayConfiguration.default
        #expect(d.endpoint == nil)
        #expect(d.headers.isEmpty)
        #expect(d.logger == nil)
        #expect(d.timeout == nil)
    }

    @Test func fluentBuilders() {
        let url = URL(string: "https://api.example.com")!
        let logger = NebulaLogger(subsystem: "test", category: .networking)
        let cfg = NebulaGatewayConfiguration.default
            .withEndpoint(url)
            .withHeaders(["Authorization": "Bearer x"])
            .withLogger(logger)
            .withTimeout(.seconds(30))
        #expect(cfg.endpoint == url)
        #expect(cfg.headers == ["Authorization": "Bearer x"])
        #expect(cfg.logger?.subsystem == "test")
        #expect(cfg.timeout == .seconds(30))
        // Default untouched.
        #expect(NebulaGatewayConfiguration.default.endpoint == nil)
    }

    @Test func withDecoderReusesCodec() throws {
        // The .api preset maps snake_case keys to camelCase; verify the decoder
        // wired through the gateway config actually decodes that way.
        let apiDecoder = NebulaJSONDecoder(.api)
        let cfg = NebulaGatewayConfiguration.default.withDecoder(apiDecoder)
        struct Payload: Decodable, Equatable { let fullName: String }
        let json = "{\"full_name\":\"ada\"}".data(using: .utf8)!
        let payload = try cfg.decoder.decode(Payload.self, from: json)
        #expect(payload == Payload(fullName: "ada"))
    }

    @Test func reportInvokesHandler() {
        let capture = ErrorCapture()
        let cfg = NebulaGatewayConfiguration(handler: { event in capture.set(event.error) })
        let err = NebulaError(code: .init(domain: "GW", code: 1), kind: .network, message: "boom")
        cfg.report(err)
        #expect(capture.value == err)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaGatewayConfiguration.default)
        consume(FakeGateway(config: .default))
    }
}

@Suite("NebulaGatewayConfig (process-wide)")
struct NebulaGatewayConfigTests {
    @Test func getSetRoundTrips() {
        let saved = NebulaGatewayConfig.get()
        defer { NebulaGatewayConfig.set(saved) }
        let url = URL(string: "https://test-\(UUID().uuidString).example.com")!
        NebulaGatewayConfig.set(NebulaGatewayConfiguration.default.withEndpoint(url))
        #expect(NebulaGatewayConfig.get().endpoint == url)
    }
}