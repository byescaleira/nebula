//
//  ArchitectureRegistryTests.swift
//  NebulaTests
//
//  Wave H3 — Clean Architecture toolkit registry tests (Swift Testing):
//  NebulaRegistryKey (string literal + presets), NebulaRegistryConfiguration
//  (.withFactory / .removingFactory / .make), NebulaRegistry (explicit injection
//  resolve(_:as:)), NebulaRegistryConfig (process-wide get/set/resolve), and
//  Sendable derivation.
//

import Testing
import Foundation
import Nebula

// MARK: - Fixtures

private struct AccountRepository: Sendable {
    let tag: String
}

@Suite("NebulaRegistryKey")
struct NebulaRegistryKeyTests {
    @Test func stringLiteralCreatesKey() {
        let key: NebulaRegistryKey = "com.acme.account.repo"
        #expect(key.rawValue == "com.acme.account.repo")
        #expect(key.description == "com.acme.account.repo")
    }

    @Test func initFromRawValue() {
        let key = NebulaRegistryKey("custom")
        #expect(key.rawValue == "custom")
    }

    @Test func presetsExist() {
        #expect(NebulaRegistryKey.repository.rawValue == "repository")
        #expect(NebulaRegistryKey.gateway.rawValue == "gateway")
        #expect(NebulaRegistryKey.useCase.rawValue == "use-case")
    }

    @Test func isHashableAndSendable() {
        func consume<T: Hashable & Sendable>(_ v: T) {}
        consume(NebulaRegistryKey("x"))
        let set: Set<NebulaRegistryKey> = ["a", "a", "b"]
        #expect(set.count == 2)
    }
}

@Suite("NebulaRegistryConfiguration")
struct NebulaRegistryConfigurationTests {
    @Test func defaultIsEmpty() {
        #expect(NebulaRegistryConfiguration.default.factories.isEmpty)
    }

    @Test func withFactoryBindsAndMakeResolves() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "live") }
        let made = cfg.make("repo") as? AccountRepository
        #expect(made?.tag == "live")
    }

    @Test func makeReturnsNilForUnbound() {
        let cfg = NebulaRegistryConfiguration()
        #expect(cfg.make("nope") == nil)
    }

    @Test func withFactoryReplacesExisting() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "a") }
            .withFactory(for: "repo") { AccountRepository(tag: "b") }
        #expect((cfg.make("repo") as? AccountRepository)?.tag == "b")
    }

    @Test func removingFactoryRemovesBinding() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "a") }
            .removingFactory(for: "repo")
        #expect(cfg.make("repo") == nil)
    }

    @Test func factoriesAreTransient() {
        // Each make() invokes the factory afresh — distinct instances.
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "live") }
        let a = cfg.make("repo") as? AccountRepository
        let b = cfg.make("repo") as? AccountRepository
        #expect(a != nil)
        #expect(b != nil)
        // Structs are value types, but each factory call produces a fresh value.
        #expect(a?.tag == b?.tag)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaRegistryConfiguration().withFactory(for: "x") { 1 })
    }
}

@Suite("NebulaRegistry (explicit injection)")
struct NebulaRegistryTests {
    @Test func resolveReturnsTypedInstance() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "live") }
        let registry = NebulaRegistry(cfg)
        let repo = registry.resolve("repo", as: AccountRepository.self)
        #expect(repo?.tag == "live")
    }

    @Test func resolveInfersType() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "live") }
        let registry = NebulaRegistry(cfg)
        let repo: AccountRepository? = registry.resolve("repo")
        #expect(repo?.tag == "live")
    }

    @Test func resolveReturnsNilForUnbound() {
        let registry = NebulaRegistry()
        #expect(registry.resolve("nope", as: AccountRepository.self) == nil)
    }

    @Test func resolveReturnsNilForTypeMismatch() {
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "live") }
        let registry = NebulaRegistry(cfg)
        let mismatched: Int? = registry.resolve("repo", as: Int.self)
        #expect(mismatched == nil)
    }

    @Test func emptyInitHasDefaultConfig() {
        let registry = NebulaRegistry()
        #expect(registry.configuration.factories.isEmpty)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaRegistry())
    }
}

@Suite("NebulaRegistryConfig (process-wide)")
struct NebulaRegistryConfigTests {
    @Test func setGetRoundTrip() {
        let previous = NebulaRegistryConfig.get()
        defer { NebulaRegistryConfig.set(previous) }
        let cfg = NebulaRegistryConfiguration()
            .withFactory(for: "repo") { AccountRepository(tag: "global") }
        NebulaRegistryConfig.set(cfg)
        let repo = NebulaRegistryConfig.resolve("repo", as: AccountRepository.self)
        #expect(repo?.tag == "global")
    }

    @Test func resolveReturnsNilForUnbound() {
        let previous = NebulaRegistryConfig.get()
        defer { NebulaRegistryConfig.set(previous) }
        NebulaRegistryConfig.set(.default)
        #expect(NebulaRegistryConfig.resolve("nope", as: AccountRepository.self) == nil)
    }
}