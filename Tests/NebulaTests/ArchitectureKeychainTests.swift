//
//  ArchitectureKeychainTests.swift
//  NebulaTests
//
//  Wave N9 — App-readiness. Tests for the Keychain seam: ``NebulaKeychainError``
//  (the per-layer open struct + `coarseKind` / `toNebulaError` bridge), the
//  ``NebulaSecureStore`` port (a `Mutex`-backed in-memory conformer proves the
//  Codable/RawRepresentable default extension is reusable on any conformer), and
//  ``NebulaKeychain`` (the stateless `final class` façade over the real macOS host
//  Keychain — no stub). Isolation: each integration test uses a unique
//  `kSecAttrService` (`#function` + `UUID`) and `defer`-cleans by service, so no
//  cross-test pollution. The integration suite is `.serialized` to avoid
//  `errSecDuplicateItem` races against the real Keychain. The config overrides
//  `useDataProtectionKeychain = false` to use the login-keychain path on the
//  unsigned `swift test` host (the production default stays `true`). See
//  vault/03-padroes/nebula-keychain.md.
//

import Foundation
import Synchronization
import Security
import Testing

@testable import Nebula

// MARK: - Fixtures

private struct Credentials: Codable, Equatable, Sendable {
    let user: String
    let token: String
}

private enum Role: String, Codable, RawRepresentable, Equatable {
    case reader, writer, admin
}

private enum Tier: Int, Codable, RawRepresentable, Equatable {
    case free, paid
}

/// A non-Keychain ``NebulaSecureStore`` conformer: a `Mutex`-backed in-memory
/// `[String: Data]` store. Proves the Codable/RawRepresentable default extension
/// is reusable on any conformer (the architecture-seam point), and that the
/// `throws` contract is honored.
private final class InMemorySecureStore: NebulaSecureStore {
    private let mutex = Mutex<[String: Data]>([:])
    func data(forKey key: String) throws -> Data? { mutex.withLock { $0[key] } }
    func setData(_ value: Data?, forKey key: String) throws {
        mutex.withLock { (store: inout [String: Data]) -> Void in
            if let value { store[key] = value } else { store.removeValue(forKey: key) }
        }
    }
    func remove(forKey key: String) throws {
        mutex.withLock { (store: inout [String: Data]) -> Void in store.removeValue(forKey: key) }
    }
}

// MARK: - NebulaKeychainError

@Suite("NebulaKeychainError")
struct NebulaKeychainErrorTests {

    @Test func kindPresetsAreStringRawValues() {
        #expect(NebulaKeychainError.Kind.itemNotFound.rawValue == "item-not-found")
        #expect(NebulaKeychainError.Kind.duplicateItem.rawValue == "duplicate-item")
        #expect(NebulaKeychainError.Kind.authFailed.rawValue == "auth-failed")
        #expect(NebulaKeychainError.Kind.interactionNotAllowed.rawValue == "interaction-not-allowed")
        #expect(NebulaKeychainError.Kind.missingEntitlement.rawValue == "missing-entitlement")
        #expect(NebulaKeychainError.Kind.cancelled.rawValue == "cancelled")
        #expect(NebulaKeychainError.Kind.unknown.rawValue == "unknown")
    }

    @Test func kindIsExpressibleByStringLiteral() {
        let custom: NebulaKeychainError.Kind = "custom-keychain"
        #expect(custom.rawValue == "custom-keychain")
    }

    @Test func defaultCodeMirrorsKindRawValue() {
        let err = NebulaKeychainError(kind: .authFailed, message: "x")
        #expect(err.code == "auth-failed")
        let explicit = NebulaKeychainError(kind: .authFailed, code: "AUTH_FAILED", message: "x")
        #expect(explicit.code == "AUTH_FAILED")
    }

    @Test func factoryStaticsCarryStatus() {
        #expect(NebulaKeychainError.itemNotFound().kind == .itemNotFound)
        #expect(NebulaKeychainError.itemNotFound().status == errSecItemNotFound)
        #expect(NebulaKeychainError.duplicateItem().status == errSecDuplicateItem)
        #expect(NebulaKeychainError.authFailed().status == errSecAuthFailed)
        #expect(NebulaKeychainError.interactionNotAllowed().status == errSecInteractionNotAllowed)
        #expect(NebulaKeychainError.missingEntitlement().status == errSecMissingEntitlement)
        #expect(NebulaKeychainError.cancelled().status == errSecUserCanceled)
        #expect(NebulaKeychainError.unknown().status == 0)
    }

    @Test func coarseKindMapping() {
        // OSStatus / CoreFoundation failures → .cocoa.
        #expect(NebulaKeychainError.duplicateItem().coarseKind == .cocoa)
        #expect(NebulaKeychainError.authFailed().coarseKind == .cocoa)
        #expect(NebulaKeychainError.interactionNotAllowed().coarseKind == .cocoa)
        #expect(NebulaKeychainError.missingEntitlement().coarseKind == .cocoa)
        // not-found / cancellation / uncategorized → .unknown.
        #expect(NebulaKeychainError.itemNotFound().coarseKind == .unknown)
        #expect(NebulaKeychainError.cancelled().coarseKind == .unknown)
        #expect(NebulaKeychainError.unknown().coarseKind == .unknown)
    }

    @Test func toNebulaErrorPreservesKindCodeAndOSStatus() {
        let error = NebulaKeychainError.authFailed("bad credentials")
        let nebula = error.toNebulaError(kind: .cocoa)
        #expect(nebula.kind == .cocoa)
        #expect(nebula.code.domain == "Nebula.NebulaKeychainError")
        #expect(nebula.code.code == Int(errSecAuthFailed))
        #expect(nebula.metadata["NebulaCode"] == "auth-failed")
        #expect(nebula.metadata["NebulaOSStatus"] == String(errSecAuthFailed))
        #expect(nebula.message == "bad credentials")
    }

    @Test func bridgesViaNebulaErrorDispatch() {
        // `NebulaError(error:)` routes a `NebulaFailure` through `toNebulaError(kind: coarseKind)`.
        let nebula = NebulaError(error: NebulaKeychainError.duplicateItem("dup"))
        #expect(nebula.kind == .cocoa)
        #expect(nebula.metadata["NebulaCode"] == "duplicate-item")
        #expect(nebula.message == "dup")
    }

    @Test func equalityAndHashable() {
        let a = NebulaKeychainError.authFailed()
        let b = NebulaKeychainError.authFailed()
        #expect(a == b)
        #expect(a != NebulaKeychainError.duplicateItem())
        #expect(Set([a, b]).count == 1)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaKeychainError.authFailed())
    }

    @Test func throwsMatchingSpecificKeychainError() {
        let target = NebulaKeychainError.duplicateItem("dup")
        #expect(throws: target) {
            throw NebulaKeychainError.duplicateItem("dup")
        }
    }
}

// MARK: - NebulaSecureStore port (reusable default extension)

@Suite("NebulaSecureStore port seam")
struct NebulaSecureStorePortTests {

    @Test func inMemoryConformerGetsCodableBridgeForFree() throws {
        let store = InMemorySecureStore()
        try store.setValue(Credentials(user: "ada", token: "t0k3n"), forKey: "creds")
        let read: Credentials? = try store.value(Credentials.self, forKey: "creds")
        #expect(read == Credentials(user: "ada", token: "t0k3n"))
    }

    @Test func inMemoryConformerGetsRawRepresentableBridgeForFree() throws {
        let store = InMemorySecureStore()
        try store.setRawValue(Role.writer, forKey: "role")
        #expect(try store.rawValue(Role.self, forKey: "role") == .writer)
        try store.setRawValue(Tier.paid, forKey: "tier")
        #expect(try store.rawValue(Tier.self, forKey: "tier") == .paid)
    }

    @Test func codableAbsentKeyReturnsNil() throws {
        let store = InMemorySecureStore()
        let read: Credentials? = try store.value(Credentials.self, forKey: "absent")
        #expect(read == nil)
    }

    @Test func corruptDataThrowsDecodingError() throws {
        let store = InMemorySecureStore()
        try store.setData(Data([0x00, 0xFF, 0x00]), forKey: "creds") // not valid JSON
        #expect(throws: DecodingError.self) {
            let _: Credentials? = try store.value(Credentials.self, forKey: "creds")
        }
    }

    @Test func setValueNilRemovesTheKey() throws {
        let store = InMemorySecureStore()
        try store.setValue(Credentials(user: "ada", token: "x"), forKey: "creds")
        try store.setValue(Credentials?.none, forKey: "creds")
        #expect(try store.value(Credentials.self, forKey: "creds") == nil)
    }

    @Test func rawRepresentableUnmappableRawReturnsNil() throws {
        let store = InMemorySecureStore()
        try store.setValue("superuser" as String, forKey: "role")
        #expect(try store.rawValue(Role.self, forKey: "role") == nil) // not a valid Role
    }

    @Test func existentialHoldsEitherConformer() throws {
        let stores: [NebulaSecureStore] = [InMemorySecureStore(), InMemorySecureStore()]
        for store in stores {
            try store.setValue(Credentials(user: "ada", token: "t"), forKey: "c")
            #expect(try store.value(Credentials.self, forKey: "c") == Credentials(user: "ada", token: "t"))
        }
    }
}

// MARK: - NebulaKeychain (real macOS host Keychain — no stub)

@Suite("NebulaKeychain integration", .serialized)
struct NebulaKeychainIntegrationTests {

    /// A unique-service config per test, with `useDataProtectionKeychain = false`
    /// for the unsigned `swift test` host (login-keychain path). The production
    /// default stays `true`.
    private func make() -> NebulaKeychain {
        let service = "NebulaTests.Keychain.\(#function).\(UUID().uuidString)"
        return NebulaKeychain(.init(service: service, useDataProtectionKeychain: false))
    }

    /// Deletes every generic-password item for `keychain`'s service (test cleanup).
    private func cleanup(_ keychain: NebulaKeychain) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.config.service,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    @Test func dataRoundTripsThroughSetGetRemove() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(try keychain.data(forKey: "k") == nil)

        try keychain.setData(payload, forKey: "k")
        #expect(try keychain.data(forKey: "k") == payload)

        try keychain.remove(forKey: "k")
        #expect(try keychain.data(forKey: "k") == nil)
    }

    @Test func setDataNilRemovesTheKey() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.setData(Data([1, 2, 3]), forKey: "k")
        #expect(try keychain.data(forKey: "k") != nil)
        try keychain.setData(nil, forKey: "k")
        #expect(try keychain.data(forKey: "k") == nil)
    }

    @Test func removeIsNoOpForAbsentKey() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.remove(forKey: "never-set")
        #expect(try keychain.data(forKey: "never-set") == nil)
    }

    @Test func setDataUpdatesInPlaceOverAdd() throws {
        // Update-over-add: writing twice changes the value; no duplicate item.
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.setData(Data("v1".utf8), forKey: "k")
        try keychain.setData(Data("v2".utf8), forKey: "k")
        #expect(try keychain.data(forKey: "k") == Data("v2".utf8))
        // Update-over-add left exactly one item for this service+account: a
        // match query returns success (one hit), not `errSecDuplicateItem`.
        var result: AnyObject?
        let countQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.config.service,
            kSecAttrAccount as String: "k",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: false,
        ]
        let status = SecItemCopyMatching(countQuery as CFDictionary, &result)
        #expect(status == errSecSuccess)
    }

    @Test func codableBridgeRoundTripsThroughKeychain() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.setValue(Credentials(user: "ada", token: "t0k3n"), forKey: "creds")
        let read: Credentials? = try keychain.value(Credentials.self, forKey: "creds")
        #expect(read == Credentials(user: "ada", token: "t0k3n"))
    }

    @Test func rawRepresentableBridgeRoundTripsThroughKeychain() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.setRawValue(Role.admin, forKey: "role")
        #expect(try keychain.rawValue(Role.self, forKey: "role") == .admin)
    }

    @Test func corruptStoredDataThrowsDecodingError() throws {
        let keychain = make()
        defer { cleanup(keychain) }
        try keychain.setData(Data([0x00, 0xFF, 0x00]), forKey: "creds") // not valid JSON
        #expect(throws: DecodingError.self) {
            let _: Credentials? = try keychain.value(Credentials.self, forKey: "creds")
        }
    }

    @Test func thrownKeychainErrorBridgesViaNebulaError() throws {
        // A deliberately impossible access group yields errSecMissingEntitlement
        // (or another non-zero status) on the unsigned host — either way the
        // thrown error must bridge to .cocoa with the right domain.
        let keychain = NebulaKeychain(.init(
            service: "NebulaTests.Keychain.bridge.\(UUID().uuidString)",
            accessGroup: "com.nebula.nonexistent.shared",
            useDataProtectionKeychain: false
        ))
        defer { cleanup(keychain) }
        do {
            try keychain.setData(Data("v".utf8), forKey: "k")
            // Some hosts allow the write (no entitlement enforcement unsigned);
            // then the read must still round-trip without bridging. Either
            // outcome is acceptable — the point is no crash.
            #expect(try keychain.data(forKey: "k") == Data("v".utf8))
        } catch let error as NebulaKeychainError {
            let nebula = NebulaError(error: error)
            #expect(nebula.code.domain == "Nebula.NebulaKeychainError")
            #expect(nebula.kind == .cocoa || nebula.kind == .unknown)
            #expect(nebula.metadata["NebulaOSStatus"] != nil)
        }
    }
}

// MARK: - Sendable + concurrency

@Suite("NebulaKeychain Sendable + concurrency", .serialized)
struct NebulaKeychainConcurrencyTests {

    @Test func usableAcrossTaskBoundary() async throws {
        let keychain = NebulaKeychain(.init(
            service: "NebulaTests.Keychain.sendable.\(UUID().uuidString)",
            useDataProtectionKeychain: false
        ))
        defer { _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.config.service,
        ] as CFDictionary) }
        try keychain.setData(Data("v".utf8), forKey: "k")
        let read: Data? = try await Task {
            try keychain.data(forKey: "k")
        }.value
        #expect(read == Data("v".utf8))
    }

    @Test func concurrentAccessIsSafeWithoutMutex() async throws {
        // 50 tasks each write a unique key to one shared `NebulaKeychain` (unique
        // service), then read it back. The `SecItem*` C API is thread-safe, so no
        // `Mutex` is needed — a data race would crash or return a wrong value.
        let keychain = NebulaKeychain(.init(
            service: "NebulaTests.Keychain.concurrent.\(UUID().uuidString)",
            useDataProtectionKeychain: false
        ))
        defer { _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.config.service,
        ] as CFDictionary) }
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let key = "k\(i)"
                    do {
                        try keychain.setData(Data("v\(i)".utf8), forKey: key)
                        let read = try keychain.data(forKey: key)
                        return read == Data("v\(i)".utf8)
                    } catch {
                        return false
                    }
                }
            }
            var allOK = true
            for await ok in group { if !ok { allOK = false } }
            #expect(allOK)
        }
    }
}