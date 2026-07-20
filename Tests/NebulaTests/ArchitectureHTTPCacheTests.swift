//
//  ArchitectureHTTPCacheTests.swift
//  NebulaTests
//
//  Wave N6 — Network. Tests for the ``NebulaURLCache`` façade: store → fresh
//  hit, TTL expiry → miss, stale-while-revalidate (stale within maxStale, nil
//  beyond), remove / removeAll, and that `.protocolDefault` / `.bypass` are not
//  Nebula-managed (return nil). Uses a dedicated in-memory `URLCache` per test —
//  no network, no `.shared` pollution. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Testing
import Foundation
import Nebula

// MARK: - A dedicated in-memory URLCache per test (no `.shared` pollution).

private func makeCache() -> URLCache {
    URLCache(memoryCapacity: 4_000_000, diskCapacity: 0)
}

private func makeRequest(_ path: String = "items") -> URLRequest {
    URLRequest(url: URL(string: "https://cache.test/\(path)")!)
}

private func cannedResponse(_ value: Int) -> NebulaHTTPResponse {
    .init(statusCode: 200, headers: ["Content-Type": "application/json"],
          body: Data("{\"value\":\(value)}".utf8))
}

@Suite(.serialized)
struct NebulaURLCacheTests {

    @Test func storeThenResponseIsFresh() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        await cache.store(cannedResponse(7), for: request, policy: .store(ttl: .seconds(60)))
        let hit = try #require(await cache.response(for: request, policy: .store(ttl: .seconds(60))))
        #expect(hit.isStale == false)
        #expect(hit.response == cannedResponse(7))
    }

    @Test func missWhenNothingStored() async {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        #expect(await cache.response(for: request, policy: .store(ttl: .seconds(60))) == nil)
    }

    @Test func expiredEntryReturnsNil() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        // 1 ms TTL — anything stored "now" is fresh; after a short sleep it's
        // past its TTL and must miss.
        await cache.store(cannedResponse(1), for: request, policy: .store(ttl: .milliseconds(1)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await cache.response(for: request, policy: .store(ttl: .milliseconds(1))) == nil)
    }

    @Test func staleWhileRevalidateReturnsStaleWithinMaxStale() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        // 1 ms TTL but a 60 s max-stale window: after the TTL the entry is stale
        // but still usable (isStale == true).
        await cache.store(cannedResponse(2), for: request,
                          policy: .staleWhileRevalidate(ttl: .milliseconds(1), maxStale: .seconds(60)))
        try await Task.sleep(for: .milliseconds(20))
        let hit = try #require(await cache.response(for: request,
            policy: .staleWhileRevalidate(ttl: .milliseconds(1), maxStale: .seconds(60))))
        #expect(hit.isStale == true)
        #expect(hit.response == cannedResponse(2))
    }

    @Test func staleBeyondMaxStaleReturnsNil() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        // 1 ms TTL and 1 ms max-stale: after a short sleep the entry is past
        // both windows and must miss.
        await cache.store(cannedResponse(3), for: request,
                          policy: .staleWhileRevalidate(ttl: .milliseconds(1), maxStale: .milliseconds(1)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await cache.response(for: request,
            policy: .staleWhileRevalidate(ttl: .milliseconds(1), maxStale: .milliseconds(1))) == nil)
    }

    @Test func removeDropsEntry() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        await cache.store(cannedResponse(4), for: request, policy: .store(ttl: .seconds(60)))
        await cache.remove(for: request)
        #expect(await cache.response(for: request, policy: .store(ttl: .seconds(60))) == nil)
    }

    @Test func removeAllDropsEverything() async throws {
        let cache = NebulaURLCache(makeCache())
        let a = makeRequest("a")
        let b = makeRequest("b")
        await cache.store(cannedResponse(5), for: a, policy: .store(ttl: .seconds(60)))
        await cache.store(cannedResponse(6), for: b, policy: .store(ttl: .seconds(60)))
        await cache.removeAll()
        #expect(await cache.response(for: a, policy: .store(ttl: .seconds(60))) == nil)
        #expect(await cache.response(for: b, policy: .store(ttl: .seconds(60))) == nil)
    }

    @Test func protocolDefaultIsNotNebulaManaged() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        // Stored under a `.store` policy, but consulted under `.protocolDefault`
        // → the Nebula cache declines (delegates to URLSession's native cache).
        await cache.store(cannedResponse(8), for: request, policy: .store(ttl: .seconds(60)))
        #expect(await cache.response(for: request, policy: .protocolDefault) == nil)
    }

    @Test func bypassIsNotNebulaManaged() async throws {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        await cache.store(cannedResponse(9), for: request, policy: .store(ttl: .seconds(60)))
        #expect(await cache.response(for: request, policy: .bypass) == nil)
    }

    @Test func storeDeclinesForNonNebulaManagedPolicy() async {
        let cache = NebulaURLCache(makeCache())
        let request = makeRequest()
        // Storing under `.protocolDefault` records no Nebula metadata, so a
        // later `.store` consult misses (the native URLCache may or may not
        // hold the bytes, but Nebula's freshness gate declines).
        await cache.store(cannedResponse(10), for: request, policy: .protocolDefault)
        #expect(await cache.response(for: request, policy: .store(ttl: .seconds(60))) == nil)
    }
}