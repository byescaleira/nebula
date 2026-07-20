//
//  ArchitectureHTTPServerTests.swift
//  NebulaTests
//
//  Wave N7 — Network. Tests for the local HTTP/1.1 server: the
//  ``NebulaHTTPRequestParser`` (complete / incomplete / malformed / query /
//  body), ``NebulaHTTPServer`` response serialization, the
//  ``NebulaHTTPServerError`` bridge, and a real localhost round-trip
//  (``NebulaHTTPServer`` + ``NebulaHTTPGateway`` over `URLSession` — no
//  `URLProtocol` stub). The integration suite is serialized and binds an
//  OS-assigned ephemeral port to avoid bind races. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Testing
import Foundation
import Network
@testable import Nebula

// MARK: - NebulaHTTPRequestParser

@Suite struct NebulaHTTPRequestParserTests {

    @Test func parsesCompleteGet() throws {
        let raw = Data("GET /items HTTP/1.1\r\nHost: x\r\nAccept: */*\r\n\r\n".utf8)
        let request = try #require(try NebulaHTTPRequestParser.parse(raw))
        #expect(request.method == .get)
        #expect(request.path == "/items")
        #expect(request.query.isEmpty)
        #expect(request.body == .none)
        #expect(request.headers["Host"] == "x")
        #expect(request.headers["Accept"] == "*/*")
    }

    @Test func parsesQueryItems() throws {
        let raw = Data("GET /items?q=x&page=2 HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        let request = try #require(try NebulaHTTPRequestParser.parse(raw))
        #expect(request.path == "/items")
        #expect(request.query.contains(URLQueryItem(name: "q", value: "x")))
        #expect(request.query.contains(URLQueryItem(name: "page", value: "2")))
    }

    @Test func parsesPostWithBody() throws {
        let body = Data("{\"value\":7}".utf8)
        var raw = Data("POST /items HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        raw.append(body)
        let request = try #require(try NebulaHTTPRequestParser.parse(raw))
        #expect(request.method == .post)
        guard case .data(let bytes, let contentType) = request.body else {
            Issue.record("expected .data body"); return
        }
        #expect(bytes == body)
        #expect(contentType == "application/json")
    }

    @Test func incompleteHeadersReturnNil() throws {
        // No \r\n\r\n terminator yet → need more bytes.
        let raw = Data("GET /items HTTP/1.1\r\nHost: x".utf8)
        #expect(try NebulaHTTPRequestParser.parse(raw) == nil)
    }

    @Test func incompleteBodyReturnNil() throws {
        // Headers complete but Content-Length announces more body than present.
        let raw = Data("POST /items HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nshort".utf8)
        #expect(try NebulaHTTPRequestParser.parse(raw) == nil)
    }

    @Test func malformedRequestLineThrows() {
        let raw = Data("GARBAGE\r\n\r\n".utf8)
        #expect(throws: NebulaHTTPServerError.self) {
            _ = try NebulaHTTPRequestParser.parse(raw)
        }
    }

    @Test func unsupportedMethodThrows() {
        let raw = Data("TRACE /items HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        #expect(throws: NebulaHTTPServerError.self) {
            _ = try NebulaHTTPRequestParser.parse(raw)
        }
    }

    @Test func negativeContentLengthThrows() {
        // A negative Content-Length must be rejected (not crash on a reversed
        // Range) — a crafted request must not trap the server process.
        let raw = Data("POST /items HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n".utf8)
        #expect(throws: NebulaHTTPServerError.self) {
            _ = try NebulaHTTPRequestParser.parse(raw)
        }
    }

    @Test func nonNumericContentLengthThrows() {
        let raw = Data("POST /items HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\n\r\n".utf8)
        #expect(throws: NebulaHTTPServerError.self) {
            _ = try NebulaHTTPRequestParser.parse(raw)
        }
    }

    @Test func oversizedContentLengthThrows() {
        let huge = NebulaHTTPRequestParser.maxBodyLength + 1
        let raw = Data("POST /items HTTP/1.1\r\nHost: x\r\nContent-Length: \(huge)\r\n\r\n".utf8)
        #expect(throws: NebulaHTTPServerError.self) {
            _ = try NebulaHTTPRequestParser.parse(raw)
        }
    }
}

// MARK: - NebulaHTTPServer serialization

@Suite struct NebulaHTTPServerSerializeTests {

    @Test func serializeStatusLineHeadersAndBody() throws {
        let response = NebulaHTTPResponse(statusCode: 200,
                                           headers: ["Content-Type": "text/plain"],
                                           body: Data("hello".utf8))
        let bytes = NebulaHTTPServer.serialize(response)
        let text = String(data: bytes, encoding: .utf8) ?? ""
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: text/plain\r\n"))
        #expect(text.contains("Content-Length: 5\r\n"))
        #expect(text.contains("\r\n\r\nhello"))
    }

    @Test func reasonPhraseForKnownCodes() {
        #expect(NebulaHTTPServer.reasonPhrase(for: 200) == "OK")
        #expect(NebulaHTTPServer.reasonPhrase(for: 404) == "Not Found")
        #expect(NebulaHTTPServer.reasonPhrase(for: 500) == "Internal Server Error")
    }

    @Test func serializeOverwritesHandlerContentLengthCaseInsensitively() throws {
        // A handler that set a lowercase / stale Content-Length must not produce
        // a duplicate header — the actual body count wins.
        let response = NebulaHTTPResponse(statusCode: 200,
                                           headers: ["content-length": "999", "Content-Type": "text/plain"],
                                           body: Data("hi".utf8))
        let text = String(data: NebulaHTTPServer.serialize(response), encoding: .utf8) ?? ""
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(!text.contains("999"))
        // Exactly one Content-Length line.
        #expect(text.components(separatedBy: "Content-Length:").count == 2)
    }

    @Test func serializeStripsCRLFFromHandlerHeaders() throws {
        // A handler value containing CR/LF must not inject a separate header
        // line — the CRLF is stripped so "Evil:" never starts its own line.
        let response = NebulaHTTPResponse(statusCode: 200,
                                           headers: ["X-Injected": "a\r\nEvil: 1"],
                                           body: Data())
        let text = String(data: NebulaHTTPServer.serialize(response), encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines.allSatisfy { !$0.hasPrefix("Evil:") }, "no injected Evil: header line")
        // The value is flattened into the one X-Injected line (no CRLF split).
        #expect(lines.contains("X-Injected: aEvil: 1"))
    }
}

// MARK: - NebulaHTTPServerError

@Suite struct NebulaHTTPServerErrorTests {

    @Test func coarseKindMapping() {
        #expect(NebulaHTTPServerError.bindFailed().coarseKind == .network)
        #expect(NebulaHTTPServerError.sendFailed().coarseKind == .network)
        #expect(NebulaHTTPServerError.parseFailed().coarseKind == .decoding)
        #expect(NebulaHTTPServerError.cancelled().coarseKind == .unknown)
        #expect(NebulaHTTPServerError.unknown().coarseKind == .unknown)
    }

    @Test func toNebulaErrorPreservesKindAndCode() {
        let error = NebulaHTTPServerError.bindFailed("Bind failed: EADDRINUSE")
        let nebula = error.toNebulaError(kind: .network)
        #expect(nebula.kind == .network)
        #expect(nebula.code.domain == "Nebula.NebulaHTTPServerError")
        #expect(nebula.metadata["NebulaCode"] == "bind-failed")
        #expect(nebula.message == "Bind failed: EADDRINUSE")
    }

    @Test func bridgesViaNebulaErrorDispatch() {
        // `NebulaError(error:)` routes a `NebulaFailure` through `toNebulaError(kind: coarseKind)`.
        let nebula = NebulaError(error: NebulaHTTPServerError.parseFailed("bad"))
        #expect(nebula.kind == .decoding)
        #expect(nebula.message == "bad")
    }

    @Test func equality() {
        #expect(NebulaHTTPServerError.bindFailed() == NebulaHTTPServerError.bindFailed())
        #expect(NebulaHTTPServerError.bindFailed() != NebulaHTTPServerError.parseFailed())
    }
}

// MARK: - Real localhost round-trip (NebulaHTTPServer + NebulaHTTPGateway).

private struct DTO: Codable, Equatable, Sendable { let value: Int }

private func noRetry() -> NebulaRetryPolicy { .init(maxAttempts: 1, baseDelay: .milliseconds(1), jitter: .none) }

/// A handler that routes a few paths for the integration round-trip.
private func handler(_ request: NebulaHTTPRequest) -> NebulaHTTPResponse {
    switch (request.method, request.path) {
    case (.get, "/hello"):
        return .init(statusCode: 200, headers: ["Content-Type": "text/plain"], body: Data("world".utf8))
    case (.post, "/echo"):
        // Echo the request body back verbatim.
        let bytes: Data = {
            if case .data(let data, _) = request.body { return data }
            return Data()
        }()
        return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: bytes)
    case (.get, "/missing"):
        return .init(statusCode: 404, body: Data())
    default:
        return .init(statusCode: 404, body: Data())
    }
}

@Suite(.serialized)
struct NebulaHTTPServerIntegrationTests {

    @Test func getRoundTrip() async throws {
        let server = try NebulaHTTPServer(port: NWEndpoint.Port(rawValue: 0)!, handler: handler)
        try await server.start()
        defer { server.stop() }
        let port = try #require(server.port)
        let gateway = NebulaHTTPGateway(
            configuration: .init(endpoint: URL(string: "http://127.0.0.1:\(port.rawValue)")!),
            session: URLSession(configuration: .default),
            retryPolicy: noRetry()
        )
        let data = try await gateway.get("hello")
        #expect(data == Data("world".utf8))
    }

    @Test func postRoundTripEchoesBody() async throws {
        let server = try NebulaHTTPServer(port: NWEndpoint.Port(rawValue: 0)!, handler: handler)
        try await server.start()
        defer { server.stop() }
        let port = try #require(server.port)
        let gateway = NebulaHTTPGateway(
            configuration: .init(endpoint: URL(string: "http://127.0.0.1:\(port.rawValue)")!),
            session: URLSession(configuration: .default),
            retryPolicy: noRetry()
        )
        let dto = try await gateway.post(DTO.self, "echo", body: DTO(value: 5))
        #expect(dto == DTO(value: 5))
    }

    @Test func notFoundBridgesToNebulaError() async throws {
        let server = try NebulaHTTPServer(port: NWEndpoint.Port(rawValue: 0)!, handler: handler)
        try await server.start()
        defer { server.stop() }
        let port = try #require(server.port)
        let gateway = NebulaHTTPGateway(
            configuration: .init(endpoint: URL(string: "http://127.0.0.1:\(port.rawValue)")!),
            session: URLSession(configuration: .default),
            retryPolicy: noRetry()
        )
        do {
            _ = try await gateway.get(DTO.self, "missing")
            Issue.record("expected a 404 throw")
        } catch let e as NebulaError {
            #expect(e.kind == .network)
            #expect(e.code.code == 404)
        } catch {
            Issue.record("expected NebulaError, got \(error)")
        }
    }

    @Test func queryItemsReachHandler() async throws {
        // The handler echoes 404 for unknown paths; verify a query-bearing GET
        // resolves to /hello (query stripped) and succeeds.
        let server = try NebulaHTTPServer(port: NWEndpoint.Port(rawValue: 0)!, handler: handler)
        try await server.start()
        defer { server.stop() }
        let port = try #require(server.port)
        let gateway = NebulaHTTPGateway(
            configuration: .init(endpoint: URL(string: "http://127.0.0.1:\(port.rawValue)")!),
            session: URLSession(configuration: .default),
            retryPolicy: noRetry()
        )
        let data = try await gateway.get("hello", query: [URLQueryItem(name: "q", value: "x")])
        #expect(data == Data("world".utf8))
    }
}