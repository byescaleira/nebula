//
//  ArchitectureErrorsTests.swift
//  NebulaTests
//
//  Wave H1 — Clean Architecture toolkit error-layer tests (Swift Testing):
//  NebulaFailure protocol bridge, NebulaDomainError / NebulaValidationError /
//  NebulaRepositoryError (fields, derived Equatable/Hashable, coarseKind,
//  toNebulaError bridge, factory statics, Kind presets, Source enum), and the
//  NebulaError.init(error:) dispatch routing a NebulaFailure through its bridge.
//

import Testing
import Foundation
import Nebula

@Suite("NebulaFailure bridge")
struct NebulaFailureBridgeTests {
    @Test func domainErrorBridgesWithValidationKindAndCode() {
        let err = NebulaDomainError(code: "insufficient-funds", message: "not enough")
        let bridge = err.toNebulaError(kind: err.coarseKind)
        #expect(bridge.kind == .validation)        // coarseKind default
        #expect(bridge.message == "not enough")
        #expect(bridge.metadata["NebulaCode"] == "insufficient-funds")
        #expect(bridge.code.domain == "Nebula.NebulaDomainError")
    }

    @Test func validationErrorBridgesWithField() {
        let err = NebulaValidationError(code: "out-of-range", message: "age too high", field: "age")
        let bridge = err.toNebulaError(kind: .validation)
        #expect(bridge.kind == .validation)
        #expect(bridge.metadata["NebulaField"] == "age")
        #expect(bridge.metadata["NebulaCode"] == "out-of-range")
    }

    @Test func callerPicksADifferentKindAtBoundary() {
        // coarseKind defaults to .validation, but the boundary may override.
        let err = NebulaDomainError(code: "x", message: "m")
        let bridge = err.toNebulaError(kind: .unknown)
        #expect(bridge.kind == .unknown)
    }

    @Test func dispatchRoutesFailureThroughBridge() {
        // Throwing a NebulaFailure and catching via NebulaError.init(error:)
        // routes through the failure's coarseKind.
        let err = NebulaDomainError(code: "insufficient-funds", message: "not enough")
        let mapped = NebulaError(error: err)
        #expect(mapped.kind == .validation)
        #expect(mapped.metadata["NebulaCode"] == "insufficient-funds")
        #expect(mapped.message == "not enough")
    }

    @Test func dispatchRoutesRepositoryFailureThroughCoarseKind() {
        let err = NebulaRepositoryError.constraintViolation("dup", entityType: "Account", id: "abc")
        let mapped = NebulaError(error: err)
        #expect(mapped.kind == .validation) // constraintViolation → .validation
        #expect(mapped.metadata["NebulaEntityType"] == "Account")
        #expect(mapped.metadata["NebulaEntityId"] == "abc")
    }
}

@Suite("NebulaDomainError")
struct NebulaDomainErrorTests {
    @Test func fieldsRoundTrip() {
        let err = NebulaDomainError(code: "c", message: "m", metadata: ["k": "v"])
        #expect(err.code == "c")
        #expect(err.message == "m")
        #expect(err.metadata == ["k": "v"])
        #expect(err.underlying == nil)
        #expect(err.coarseKind == .validation)
    }

    @Test func equatableAndHashable() {
        let a = NebulaDomainError(code: "c", message: "m")
        let b = NebulaDomainError(code: "c", message: "m")
        let c = NebulaDomainError(code: "c", message: "m2")
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b]).count == 1)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaDomainError(code: "c", message: "m"))
    }

    @Test func throwsMatchingSpecificDomainError() {
        let target = NebulaDomainError(code: "insufficient-funds", message: "x")
        #expect(throws: target) {
            throw NebulaDomainError(code: "insufficient-funds", message: "x")
        }
    }
}

@Suite("NebulaValidationError")
struct NebulaValidationErrorTests {
    @Test func fieldsRoundTripIncludingField() {
        let err = NebulaValidationError(code: "c", message: "m", field: "email", metadata: ["k": "v"])
        #expect(err.code == "c")
        #expect(err.field == "email")
        #expect(err.metadata == ["k": "v"])
        #expect(err.coarseKind == .validation)
    }

    @Test func equatableAndHashable() {
        let a = NebulaValidationError(code: "c", message: "m", field: "f")
        let b = NebulaValidationError(code: "c", message: "m", field: "f")
        let c = NebulaValidationError(code: "c", message: "m", field: "g")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func throwsMatchingSpecificValidationError() {
        let target = NebulaValidationError(code: "bad", message: "x", field: "age")
        #expect(throws: target) {
            throw NebulaValidationError(code: "bad", message: "x", field: "age")
        }
    }
}

@Suite("NebulaRepositoryError")
struct NebulaRepositoryErrorTests {
    @Test func sourceEnumCoversAllCases() {
        #expect(NebulaRepositoryError.Source.allCases.count == 3)
    }

    @Test func kindPresetsAreStringRawValues() {
        #expect(NebulaRepositoryError.Kind.notFound.rawValue == "not-found")
        #expect(NebulaRepositoryError.Kind.alreadyExists.rawValue == "already-exists")
        #expect(NebulaRepositoryError.Kind.storeFailure.rawValue == "store-failure")
        #expect(NebulaRepositoryError.Kind.mapping.rawValue == "mapping")
        #expect(NebulaRepositoryError.Kind.constraintViolation.rawValue == "constraint-violation")
        #expect(NebulaRepositoryError.Kind.cancelled.rawValue == "cancelled")
        #expect(NebulaRepositoryError.Kind.unknown.rawValue == "unknown")
    }

    @Test func kindIsExpressibleByStringLiteral() {
        let custom: NebulaRepositoryError.Kind = "custom-store"
        #expect(custom.rawValue == "custom-store")
    }

    @Test func defaultCodeMirrorsKindRawValue() {
        let err = NebulaRepositoryError(kind: .notFound, message: "x")
        #expect(err.code == "not-found")
        // An explicit code overrides.
        let explicit = NebulaRepositoryError(kind: .notFound, code: "ACCOUNT_NOT_FOUND", message: "x")
        #expect(explicit.code == "ACCOUNT_NOT_FOUND")
    }

    @Test func factoryStatics() {
        let nf = NebulaRepositoryError.notFound(entityType: "Account", id: "abc")
        #expect(nf.kind == .notFound)
        #expect(nf.entityType == "Account")
        #expect(nf.id == "abc")
        #expect(nf.source == .local)

        let dup = NebulaRepositoryError.alreadyExists(entityType: "Account", id: "abc")
        #expect(dup.kind == .alreadyExists)

        let store = NebulaRepositoryError.storeFailure(source: .remote)
        #expect(store.kind == .storeFailure)
        #expect(store.source == .remote)

        let map = NebulaRepositoryError.mapping()
        #expect(map.kind == .mapping)

        let cv = NebulaRepositoryError.constraintViolation(entityType: "Account", id: "abc")
        #expect(cv.kind == .constraintViolation)

        let canc = NebulaRepositoryError.cancelled()
        #expect(canc.kind == .cancelled)

        let unk = NebulaRepositoryError.unknown(source: .remote)
        #expect(unk.kind == .unknown)
    }

    @Test func coarseKindMapping() {
        // constraintViolation → .validation
        #expect(NebulaRepositoryError.constraintViolation().coarseKind == .validation)
        // mapping → .decoding
        #expect(NebulaRepositoryError.mapping().coarseKind == .decoding)
        // remote source (non-constraint, non-mapping) → .network
        #expect(NebulaRepositoryError.storeFailure(source: .remote).coarseKind == .network)
        #expect(NebulaRepositoryError.unknown(source: .remote).coarseKind == .network)
        // local/unknown source → .unknown
        #expect(NebulaRepositoryError.storeFailure(source: .local).coarseKind == .unknown)
        #expect(NebulaRepositoryError.notFound().coarseKind == .unknown)
    }

    @Test func bridgePreservesSourceEntityTypeAndId() {
        let err = NebulaRepositoryError.notFound("missing", entityType: "Account", id: "abc")
        let bridge = err.toNebulaError(kind: err.coarseKind)
        #expect(bridge.metadata["NebulaSource"] == "local")
        #expect(bridge.metadata["NebulaEntityType"] == "Account")
        #expect(bridge.metadata["NebulaEntityId"] == "abc")
        #expect(bridge.metadata["NebulaCode"] == "not-found")
        #expect(bridge.code.domain == "Nebula.NebulaRepositoryError")
    }

    @Test func equatableAndHashable() {
        let a = NebulaRepositoryError.notFound(entityType: "Account", id: "abc")
        let b = NebulaRepositoryError.notFound(entityType: "Account", id: "abc")
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func throwsMatchingSpecificRepositoryError() {
        let target = NebulaRepositoryError.notFound(entityType: "Account", id: "abc")
        #expect(throws: target) {
            throw NebulaRepositoryError.notFound(entityType: "Account", id: "abc")
        }
    }
}