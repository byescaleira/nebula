//
//  ArchitectureNetworkTests.swift
//  NebulaTests
//
//  Wave N5 — Network. Tests for the Endpoint / Client / Request model:
//  ``NebulaHTTPRequest`` URL resolution + body, ``NebulaHTTPResponse`` decode,
//  ``NebulaHTTPBody`` eager JSON encoding, and the ``NebulaHTTPClient`` port
//  (a spy conformer + the inherited verb/decode extensions). No network — the
//  spy records the built URLRequest and returns a canned response. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - Fixtures

private struct DTO: Codable, Equatable, Sendable { let value: Int }

// MARK: - A spy NebulaHTTPClient that records the built URLRequest and returns
// a canned response. `final class` so the ~Copyable Mutex is absorbed behind a
// copyable, Sendable reference (mirrors NebulaSpyUseCase / SendableBox).

private final class SpyClient: NebulaHTTPClient {
    private let mutex: Mutex<URLRequest?>
    let baseURL: URL?
    let response: NebulaHTTPResponse
    var decoder: NebulaJSONDecoder { .init() }
    var encoder: NebulaJSONEncoder { .init() }

    init(baseURL: URL? = URL(string: "https://api.test"), response: NebulaHTTPResponse) {
        self.mutex = Mutex(nil)
        self.baseURL = baseURL
        self.response = response
    }

    func send(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPResponse {
        let request = try endpoint.urlRequest(against: baseURL)
        mutex.withLock { $0 = request }
        return response
    }

    var lastRequest: URLRequest? { mutex.withLock { $0 } }
}

// MARK: - NebulaHTTPRequest.urlRequest

@Suite struct NebulaHTTPRequestTests {

    @Test func buildsRelativeURL() throws {
        let request = NebulaHTTPRequest(method: .get, path: "items")
        let url = try request.urlRequest(against: URL(string: "https://api.test")!)
        #expect(url.url?.absoluteString == "https://api.test/items")
        #expect(url.httpMethod == "GET")
    }

    @Test func stripsLeadingSlashAgainstBase() throws {
        let request = NebulaHTTPRequest(method: .get, path: "/items")
        let url = try request.urlRequest(against: URL(string: "https://api.test/v1")!)
        #expect(url.url?.absoluteString == "https://api.test/v1/items")
    }

    @Test func absolutePathIgnoresBase() throws {
        let request = NebulaHTTPRequest(method: .get, path: "https://host.example/x")
        let url = try request.urlRequest(against: URL(string: "https://api.test")!)
        #expect(url.url?.absoluteString == "https://host.example/x")
    }

    @Test func appendsQueryItems() throws {
        let request = NebulaHTTPRequest(method: .get, path: "items",
                                        query: [URLQueryItem(name: "q", value: "x"), URLQueryItem(name: "page", value: "2")])
        let built = try request.urlRequest(against: URL(string: "https://api.test")!)
        let url = try #require(built.url)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.contains(URLQueryItem(name: "q", value: "x")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "page", value: "2")) == true)
    }

    @Test func setsMethodAndHeaders() throws {
        let request = NebulaHTTPRequest(method: .put, path: "items/1",
                                        headers: ["Authorization": "Bearer t", "X-Trace": "abc"])
        let url = try request.urlRequest(against: URL(string: "https://api.test")!)
        #expect(url.httpMethod == "PUT")
        #expect(url.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(url.value(forHTTPHeaderField: "X-Trace") == "abc")
    }

    @Test func bodySetsContentTypeAndBytes() throws {
        let payload = Data("hello".utf8)
        let request = NebulaHTTPRequest(method: .post, path: "items",
                                        body: .data(payload, contentType: "text/plain"))
        let url = try request.urlRequest(against: URL(string: "https://api.test")!)
        #expect(url.value(forHTTPHeaderField: "Content-Type") == "text/plain")
        #expect(url.httpBody == payload)
    }

    @Test func emptyPathWithNoEndpointThrows() {
        // `URL(string: "")` returns nil → the noEndpointOrAbsoluteURL config
        // error path (a relative path like "items" parses and is used as-is).
        #expect(throws: Error.self) {
            _ = try NebulaHTTPRequest(method: .get, path: "").urlRequest(against: nil)
        }
    }

    @Test func defaultCachePolicyIsProtocolDefault() {
        #expect(NebulaHTTPRequest(method: .get, path: "items").cachePolicy == .protocolDefault)
    }

    @Test func customCachePolicyRetained() {
        let request = NebulaHTTPRequest(method: .get, path: "items", cachePolicy: .store(ttl: .seconds(60)))
        #expect(request.cachePolicy == .store(ttl: .seconds(60)))
    }
}

// MARK: - NebulaHTTPBody

@Suite struct NebulaHTTPBodyTests {

    @Test func jsonEncodesEagerly() throws {
        let body = try NebulaHTTPBody.json(DTO(value: 7))
        guard case .data(let data, let contentType) = body else {
            Issue.record("expected .data"); return
        }
        #expect(contentType == "application/json")
        #expect(try NebulaJSONDecoder().decode(DTO.self, from: data) == DTO(value: 7))
    }

    @Test func noneAndDataEquality() {
        #expect(NebulaHTTPBody.none == .none)
        #expect(NebulaHTTPBody.data(Data("x".utf8), contentType: "text/plain")
               == .data(Data("x".utf8), contentType: "text/plain"))
    }
}

// MARK: - NebulaHTTPResponse

@Suite struct NebulaHTTPResponseTests {

    @Test func decodeSucceeds() throws {
        let response = NebulaHTTPResponse(statusCode: 200, body: Data(#"{"value":42}"#.utf8))
        #expect(try response.decode(DTO.self) == DTO(value: 42))
    }

    @Test func decodeFailsOnCorruptBody() {
        let response = NebulaHTTPResponse(statusCode: 200, body: Data("not-json".utf8))
        #expect(throws: Error.self) { _ = try response.decode(DTO.self) }
    }
}

// MARK: - NebulaHTTPClient port (spy + inherited extensions)

@Suite struct NebulaHTTPClientTests {

    @Test func sendReturnsResponse() async throws {
        let canned = NebulaHTTPResponse(statusCode: 200, body: Data(#"{"value":99}"#.utf8))
        let client = SpyClient(response: canned)
        let response = try await client.send(NebulaHTTPRequest(method: .get, path: "items"))
        #expect(response == canned)
    }

    @Test func sendDecodesViaExtension() async throws {
        let canned = NebulaHTTPResponse(statusCode: 200, body: Data(#"{"value":99}"#.utf8))
        let client = SpyClient(response: canned)
        let dto = try await client.send(NebulaHTTPRequest(method: .get, path: "items"), as: DTO.self)
        #expect(dto == DTO(value: 99))
    }

    @Test func verbGetBuildsGetRequest() async throws {
        let client = SpyClient(response: .init(statusCode: 200, body: Data(#"{"value":0}"#.utf8)))
        _ = try await client.get("items")
        let req = try #require(client.lastRequest)
        #expect(req.httpMethod == "GET")
        #expect(req.url?.absoluteString == "https://api.test/items")
    }

    @Test func verbGetDecodes() async throws {
        let client = SpyClient(response: .init(statusCode: 200, body: Data(#"{"value":5}"#.utf8)))
        let dto = try await client.get(DTO.self, "items")
        #expect(dto == DTO(value: 5))
    }

    @Test func verbPostEncodesBodyAndSetsContentType() async throws {
        let client = SpyClient(response: .init(statusCode: 200, body: Data(#"{"value":1}"#.utf8)))
        _ = try await client.post(DTO.self, "items", body: DTO(value: 7))
        let req = try #require(client.lastRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func verbPutBuildsPutRequest() async throws {
        let client = SpyClient(response: .init(statusCode: 200, body: Data(#"{"value":1}"#.utf8)))
        _ = try await client.put(DTO.self, "items/1", body: DTO(value: 5))
        #expect(try #require(client.lastRequest).httpMethod == "PUT")
    }

    @Test func verbDeleteBuildsDeleteRequest() async throws {
        let client = SpyClient(response: .init(statusCode: 204, body: Data()))
        try await client.delete("items/1")
        #expect(try #require(client.lastRequest).httpMethod == "DELETE")
    }

    @Test func existentialClientCanSend() async throws {
        // The non-generic port is existential-friendly: `any NebulaHTTPClient`
        // can call `send(_:)` (returns a concrete response, not an associatedtype).
        let client: any NebulaHTTPClient = SpyClient(response: .init(statusCode: 200, body: Data(#"{"value":3}"#.utf8)))
        let response = try await client.send(NebulaHTTPRequest(method: .get, path: "items"))
        #expect(response.statusCode == 200)
        let dto = try await client.send(NebulaHTTPRequest(method: .get, path: "items"), as: DTO.self)
        #expect(dto == DTO(value: 3))
    }
}