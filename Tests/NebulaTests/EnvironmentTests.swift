//
//  EnvironmentTests.swift
//  NebulaTests
//
//  Wave N13 — environment value + reader tests (Swift Testing): the closed
//  NebulaEnvironment enum, the fromBundle(_:key:) reader (safe-fail-to-production),
//  the NebulaEnvironmentConfiguration value + .with* builders + resolvers, and
//  the process-wide NebulaEnvironmentConfig accessor.
//

import Testing
import Foundation
import Synchronization
import Nebula

@Suite("NebulaEnvironment value")
struct NebulaEnvironmentTests {
    @Test func rawValuesAreLowercased() {
        #expect(NebulaEnvironment.development.rawValue == "development")
        #expect(NebulaEnvironment.staging.rawValue == "staging")
        #expect(NebulaEnvironment.production.rawValue == "production")
    }

    @Test func caseIterableHasThreeCases() {
        #expect(NebulaEnvironment.allCases == [.development, .staging, .production])
        #expect(NebulaEnvironment.allCases.count == 3)
    }

    @Test func equalityAndInequality() {
        #expect(NebulaEnvironment.development == .development)
        #expect(NebulaEnvironment.staging != .production)
    }

    @Test func isHashable() {
        let set: Set<NebulaEnvironment> = [.development, .development, .staging, .production]
        #expect(set.count == 3)
    }

    @Test func descriptionIsRawValue() {
        #expect(NebulaEnvironment.development.description == "development")
        #expect(NebulaEnvironment.production.description == "production")
    }

    @Test func defaultIsProduction() {
        #expect(NebulaEnvironment.default == .production)
    }

    @Test func initFromRawValueRoundTrips() {
        #expect(NebulaEnvironment(rawValue: "development") == .development)
        #expect(NebulaEnvironment(rawValue: "staging") == .staging)
        #expect(NebulaEnvironment(rawValue: "production") == .production)
        #expect(NebulaEnvironment(rawValue: "qa") == nil)
    }
}

@Suite("NebulaEnvironment.fromBundle reader")
struct NebulaEnvironmentReaderTests {
    @Test func absentKeyFailsSafeToProduction() {
        // The test runner's Bundle.main has no "Configuration" key by default,
        // so the reader must resolve to the safe default (.production). This is
        // the absent-key path; no fixture bundle is required.
        #expect(NebulaEnvironment.fromBundle() == .production)
        #expect(NebulaEnvironment.fromBundle(Bundle.main) == .production)
    }

    @Test func unknownKeyFailsSafeToProduction() {
        // An unknown string ("qa") is not a valid raw value, so init(rawValue:)
        // returns nil; fromBundle then falls back to .default (.production).
        #expect(NebulaEnvironment(rawValue: "qa") == nil)
        #expect(NebulaEnvironment.default == .production)
    }

    @Test func validRawValueResolves() {
        // Direct raw-value resolution (the path fromBundle takes after the cast).
        #expect(NebulaEnvironment(rawValue: "development") == .development)
        #expect(NebulaEnvironment(rawValue: "staging") == .staging)
    }

    @Test func defaultKeyIsConfiguration() {
        // The default key mirrors the $(CONFIGURATION) Info.plist idiom.
        // Re-reading with the explicit default key matches the default-arg call.
        #expect(
            NebulaEnvironment.fromBundle(Bundle.main, key: "Configuration")
                == NebulaEnvironment.fromBundle(Bundle.main)
        )
    }
}

@Suite("NebulaEnvironmentConfiguration value")
struct NebulaEnvironmentConfigurationTests {
    @Test func initDefaults() {
        let config = NebulaEnvironmentConfiguration()
        #expect(config.environment == .default)
        #expect(config.baseURLs.isEmpty)
        #expect(config.overrides.isEmpty)
    }

    @Test func defaultStaticMatchesInitDefaults() {
        #expect(NebulaEnvironmentConfiguration.default.environment == .default)
        #expect(NebulaEnvironmentConfiguration.default.baseURLs.isEmpty)
        #expect(NebulaEnvironmentConfiguration.default.overrides.isEmpty)
    }

    @Test func withEnvironmentReplacesEnvironmentPreservingOthers() {
        let urls: [NebulaEnvironment: URL] = [.production: URL(string: "https://api.acme.com")!]
        let overrides = ["logLevel": "info"]
        let config = NebulaEnvironmentConfiguration(
            baseURLs: urls,
            overrides: overrides
        ).withEnvironment(.staging)
        #expect(config.environment == .staging)
        #expect(config.baseURLs == urls)
        #expect(config.overrides == overrides)
    }

    @Test func withBaseURLsReplacesURLsPreservingOthers() {
        let config = NebulaEnvironmentConfiguration(
            environment: .staging,
            overrides: ["k": "v"]
        )
        let urls: [NebulaEnvironment: URL] = [
            .development: URL(string: "https://dev.acme.com")!,
            .staging: URL(string: "https://stg.acme.com")!
        ]
        let replaced = config.withBaseURLs(urls)
        #expect(replaced.baseURLs == urls)
        #expect(replaced.environment == .staging)
        #expect(replaced.overrides == ["k": "v"])
    }

    @Test func withOverridesReplacesOverridesPreservingOthers() {
        let urls: [NebulaEnvironment: URL] = [.production: URL(string: "https://api.acme.com")!]
        let config = NebulaEnvironmentConfiguration(
            environment: .production,
            baseURLs: urls
        ).withOverrides(["logLevel": "debug", "featureX": "on"])
        #expect(config.overrides == ["logLevel": "debug", "featureX": "on"])
        #expect(config.environment == .production)
        #expect(config.baseURLs == urls)
    }

    @Test func baseURLResolvesRegisteredEnvironment() {
        let prod = URL(string: "https://api.acme.com")!
        let config = NebulaEnvironmentConfiguration(
            baseURLs: [.production: prod, .development: URL(string: "https://dev.acme.com")!]
        )
        #expect(config.baseURL(for: .production) == prod)
        #expect(config.baseURL(for: .development) == URL(string: "https://dev.acme.com")!)
    }

    @Test func baseURLReturnsNilForUnregisteredEnvironment() {
        let config = NebulaEnvironmentConfiguration(
            baseURLs: [.production: URL(string: "https://api.acme.com")!]
        )
        #expect(config.baseURL(for: .staging) == nil)
    }

    @Test func valueResolvesOverrideKey() {
        let config = NebulaEnvironmentConfiguration(overrides: ["logLevel": "debug"])
        #expect(config.value(for: "logLevel") == "debug")
        #expect(config.value(for: "missing") == nil)
    }

    @Test func isSendableValue() {
        // Sendable conformance is derived; this assignment across a @Sendable
        // closure captures the value by copy, proving it is Sendable.
        let config = NebulaEnvironmentConfiguration(environment: .staging)
        let captured = Mutex<NebulaEnvironmentConfiguration?>(nil)
        let send: @Sendable () -> Void = { captured.withLock { $0 = config } }
        send()
        #expect(captured.withLock { $0 }?.environment == .staging)
    }
}

@Suite("NebulaEnvironmentConfig accessor", .serialized)
struct NebulaEnvironmentConfigTests {
    @Test func getReturnsDefaultInitially() {
        NebulaEnvironmentConfig.set(.default)
        defer { NebulaEnvironmentConfig.set(.default) }
        #expect(NebulaEnvironmentConfig.get().environment == .default)
        #expect(NebulaEnvironmentConfig.get().baseURLs.isEmpty)
    }

    @Test func setReplacesConfigProcessWide() {
        let urls: [NebulaEnvironment: URL] = [.production: URL(string: "https://api.acme.com")!]
        let config = NebulaEnvironmentConfiguration(
            environment: .staging,
            baseURLs: urls,
            overrides: ["logLevel": "debug"]
        )
        NebulaEnvironmentConfig.set(config)
        defer { NebulaEnvironmentConfig.set(.default) }
        let current = NebulaEnvironmentConfig.get()
        #expect(current.environment == .staging)
        #expect(current.baseURL(for: .production) == URL(string: "https://api.acme.com")!)
        #expect(current.value(for: "logLevel") == "debug")
    }

    @Test func setRestoresDefault() {
        // NebulaEnvironmentConfiguration is Sendable but NOT Equatable (family
        // posture), so a restored .default is verified by its fields, not ==.
        NebulaEnvironmentConfig.set(
            .init(environment: .development, baseURLs: [:], overrides: [:])
        )
        NebulaEnvironmentConfig.set(.default)
        let current = NebulaEnvironmentConfig.get()
        #expect(current.environment == .default)
        #expect(current.baseURLs.isEmpty)
        #expect(current.overrides.isEmpty)
    }
}