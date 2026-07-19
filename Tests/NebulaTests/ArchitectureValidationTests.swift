//
//  ArchitectureValidationTests.swift
//  NebulaTests
//
//  Wave H3 — Clean Architecture toolkit validation tests (Swift Testing):
//  NebulaValidator (sync, short-circuit, +), NebulaAsyncValidator (async,
//  thrown-vs-failure distinction, +), and Sendable derivation.
//

import Testing
import Foundation
import Nebula

// MARK: - Fixtures

private struct Account: Sendable, Equatable {
    let email: String
    let age: Int
}

@Suite("NebulaValidator (sync)")
struct NebulaValidatorTests {
    @Test func passesWhenAllRulesPass() {
        let v = NebulaValidator<Account>(
            .init { $0.email.isEmpty ? NebulaValidationError(code: "empty", message: "bad", field: "email") : nil },
            .init { $0.age < 0 ? NebulaValidationError(code: "negative", message: "bad", field: "age") : nil }
        )
        let result = v.validate(Account(email: "a@b.c", age: 30))
        guard case .success(let value) = result else {
            Issue.record("expected success"); return
        }
        #expect(value == Account(email: "a@b.c", age: 30))
    }

    @Test func shortCircuitsOnFirstFailure() {
        let v = NebulaValidator<Account>(
            .init { $0.email.isEmpty ? NebulaValidationError(code: "empty", message: "bad", field: "email") : nil },
            .init { $0.age < 0 ? NebulaValidationError(code: "negative", message: "bad", field: "age") : nil }
        )
        let result = v.validate(Account(email: "", age: -1))
        // First failing rule wins — "empty" not "negative".
        guard case .failure(let err) = result else {
            Issue.record("expected failure"); return
        }
        #expect(err.code == "empty")
        #expect(err.field == "email")
    }

    @Test func matchesSpecificErrorViaEquatable() {
        let expected = NebulaValidationError(code: "negative", message: "m", field: "age")
        let v = NebulaValidator<Int>.Rule { $0 < 0 ? expected : nil }
        let validator = NebulaValidator(v)
        let result = validator.validate(-5)
        guard case .failure(let err) = result else {
            Issue.record("expected failure"); return
        }
        #expect(err == expected)
    }

    @Test func plusComposesRulesLeftThenRight() {
        let left = NebulaValidator<Int>(.init { $0 < 0 ? NebulaValidationError(code: "neg", message: "bad", field: "n") : nil })
        let right = NebulaValidator<Int>(.init { $0 > 100 ? NebulaValidationError(code: "huge", message: "bad", field: "n") : nil })
        let combined = left + right
        #expect(combined.rules.count == 2)
        let ok = combined.validate(50)
        switch ok {
        case .success: break
        case .failure: Issue.record("expected success")
        }
        let huge = combined.validate(200)
        guard case .failure(let err) = huge else { Issue.record("expected failure"); return }
        #expect(err.code == "huge")
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaValidator<Int>(.init { _ in nil }))
    }
}

@Suite("NebulaAsyncValidator (async)")
struct NebulaAsyncValidatorTests {
    @Test func passesWhenAllRulesPass() async throws {
        let v = NebulaAsyncValidator<Account>(
            .init { account in
                // An async rule that could await a repo; here, pure.
                account.email.contains("@") ? nil : NebulaValidationError(code: "no-at", message: "bad", field: "email")
            }
        )
        let result = try await v.validate(Account(email: "a@b.c", age: 1))
        switch result {
        case .success: break
        case .failure: Issue.record("expected success")
        }
    }

    @Test func shortCircuitsOnFirstFailure() async throws {
        let v = NebulaAsyncValidator<Account>(
            .init { _ in NebulaValidationError(code: "first", message: "bad", field: "email") },
            .init { _ in NebulaValidationError(code: "second", message: "bad", field: "age") }
        )
        let result = try await v.validate(Account(email: "a@b.c", age: 1))
        guard case .failure(let err) = result else { Issue.record("expected failure"); return }
        #expect(err.code == "first")
    }

    @Test func thrownErrorIsNotAFailure() async {
        struct IO: Error, Equatable {}
        let v = NebulaAsyncValidator<Account>(
            .init { _ in throw IO() }
        )
        // A thrown I/O error propagates out — it is NOT a .failure.
        await #expect(throws: IO.self) {
            _ = try await v.validate(Account(email: "a@b.c", age: 1))
        }
    }

    @Test func plusComposesRules() async throws {
        let left = NebulaAsyncValidator<Int>(.init { $0 < 0 ? NebulaValidationError(code: "neg", message: "bad", field: "n") : nil })
        let right = NebulaAsyncValidator<Int>(.init { $0 > 100 ? NebulaValidationError(code: "huge", message: "bad", field: "n") : nil })
        let combined = left + right
        #expect(combined.rules.count == 2)
        let result = try await combined.validate(200)
        guard case .failure(let err) = result else { Issue.record("expected failure"); return }
        #expect(err.code == "huge")
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaAsyncValidator<Int>(.init { _ in nil }))
    }
}