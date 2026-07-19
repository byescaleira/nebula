//
//  ArchitectureUseCaseTests.swift
//  NebulaTests
//
//  Wave H2 — Clean Architecture toolkit use-case tests (Swift Testing):
//  NebulaUseCaseRole, NebulaUseCase construction / execute (untyped throws) /
//  executeTyped (typed throws(NebulaError), success + bridged non-NebulaError),
//  decorators (.reported / .measured / .logged / .instrumented), and Sendable.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - Test fixtures

private struct EchoInput: Sendable { let value: Int }

private struct Boom: Error, Equatable {}

// `ErrorCapture` is reused from ErrorTests.swift (internal, same module).

@Suite("NebulaUseCaseRole")
struct NebulaUseCaseRoleTests {
    @Test func rawValues() {
        #expect(NebulaUseCaseRole.command.rawValue == "command")
        #expect(NebulaUseCaseRole.query.rawValue == "query")
    }
}

@Suite("NebulaUseCase execute")
struct NebulaUseCaseExecuteTests {
    @Test func roleDefaultsToCommand() {
        let uc = NebulaUseCase<EchoInput, Int>(name: "echo") { $0.value }
        #expect(uc.role == .command)
    }

    @Test func executeReturnsOutput() async throws {
        let uc = NebulaUseCase<EchoInput, Int>(name: "echo", role: .query) { $0.value * 2 }
        let out = try await uc.execute(EchoInput(value: 21))
        #expect(out == 42)
    }

    @Test func executeRethrows() async {
        let uc = NebulaUseCase<EchoInput, Int>(name: "boom") { _ in throw Boom() }
        await #expect(throws: Boom.self) {
            try await uc.execute(EchoInput(value: 1))
        }
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaUseCase<EchoInput, Int>(name: "x") { $0.value })
    }
}

@Suite("NebulaUseCase executeTyped (typed throws)")
struct NebulaUseCaseExecuteTypedTests {
    @Test func successNarrowsToNebulaErrorButReturnsValue() async throws {
        let uc = NebulaUseCase<EchoInput, Int>(name: "ok") { $0.value * 2 }
        let out = try await uc.executeTyped(EchoInput(value: 3))
        #expect(out == 6)
    }

    @Test func preservesThrownNebulaError() async {
        let original = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "x")
        let uc = NebulaUseCase<EchoInput, Int>(name: "n") { _ in throw original }
        let thrown = try? await uc.executeTyped(EchoInput(value: 1))
        // `try?` swallows; use #expect(throws:) to assert the type is narrowed.
        #expect(thrown == nil)
        await #expect(throws: NebulaError.self) {
            try await uc.executeTyped(EchoInput(value: 1))
        }
    }

    @Test func bridgesNonNebulaError() async {
        let uc = NebulaUseCase<EchoInput, Int>(name: "b") { _ in throw Boom() }
        await #expect(throws: NebulaError.self) {
            try await uc.executeTyped(EchoInput(value: 1))
        }
    }

    @Test func bridgesLayerFailure() async {
        // A NebulaFailure layer error bridges via NebulaError(error:) dispatch.
        let uc = NebulaUseCase<EchoInput, Int>(name: "lf") { _ in
            throw NebulaDomainError(code: "insufficient-funds", message: "m")
        }
        await #expect(throws: NebulaError.self) {
            try await uc.executeTyped(EchoInput(value: 1))
        }
    }
}

@Suite("NebulaUseCase decorators")
struct NebulaUseCaseDecoratorTests {
    @Test func reportedReportsAndRethrows() async {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: true, category: "UC") { event in
            capture.set(event.error)
        }
        let uc = NebulaUseCase<EchoInput, Int>(name: "r") { _ in
            throw NebulaDomainError(code: "x", message: "m")
        }.reported(using: cfg)
        await #expect(throws: NebulaDomainError.self) {
            try await uc.execute(EchoInput(value: 1))
        }
        #expect(capture.value != nil)
        #expect(capture.value?.metadata["NebulaCode"] == "x")
    }

    @Test func reportedPassesThroughOnSuccess() async throws {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: true, category: "UC") { event in
            capture.set(event.error)
        }
        let uc = NebulaUseCase<EchoInput, Int>(name: "rs") { $0.value }.reported(using: cfg)
        let out = try await uc.execute(EchoInput(value: 7))
        #expect(out == 7)
        #expect(capture.value == nil)
    }

    @Test func measuredReturnsValueAndDoesNotCrash() async throws {
        let uc = NebulaUseCase<EchoInput, Int>(name: "m") { $0.value }.measured(using: .default)
        let out = try await uc.execute(EchoInput(value: 9))
        #expect(out == 9)
    }

    @Test func measuredWithSignposterDoesNotCrash() async throws {
        let cfg = NebulaMeasureConfiguration(signposter: NebulaSignposter(subsystem: "test.nebula.uc"))
        let uc = NebulaUseCase<EchoInput, Int>(name: "ms") { $0.value }.measured(using: cfg)
        let out = try await uc.execute(EchoInput(value: 9))
        #expect(out == 9)
    }

    @Test func loggedReturnsValueAndDoesNotCrash() async throws {
        let logger = NebulaLogger(subsystem: "test.nebula.uc", category: .general)
        let uc = NebulaUseCase<EchoInput, Int>(name: "l") { $0.value }.logged(using: logger)
        let out = try await uc.execute(EchoInput(value: 9))
        #expect(out == 9)
    }

    @Test func loggedRethrows() async {
        let logger = NebulaLogger(subsystem: "test.nebula.uc", category: .general)
        let uc = NebulaUseCase<EchoInput, Int>(name: "le") { _ in throw Boom() }.logged(using: logger)
        await #expect(throws: Boom.self) {
            try await uc.execute(EchoInput(value: 1))
        }
    }

    @Test func instrumentedReportsOnFailure() async {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: true, category: "UC") { event in
            capture.set(event.error)
        }
        let uc = NebulaUseCase<EchoInput, Int>(name: "i") { _ in
            throw NebulaDomainError(code: "x", message: "m")
        }.instrumented(using: NebulaLogger(subsystem: "test.nebula.uc", category: .general), measure: .default, error: cfg)
        await #expect(throws: NebulaDomainError.self) {
            try await uc.execute(EchoInput(value: 1))
        }
        #expect(capture.value != nil)
    }

    @Test func instrumentedPassesThroughOnSuccess() async throws {
        let capture = ErrorCapture()
        let cfg = NebulaErrorConfiguration(isEnabled: true, category: "UC") { event in
            capture.set(event.error)
        }
        let uc = NebulaUseCase<EchoInput, Int>(name: "is") { $0.value }
            .instrumented(using: NebulaLogger(subsystem: "test.nebula.uc", category: .general), measure: .default, error: cfg)
        let out = try await uc.execute(EchoInput(value: 5))
        #expect(out == 5)
        #expect(capture.value == nil)
    }

    @Test func instrumentedDefaultsToProcessWideConfigs() async throws {
        // All nil → defaults; must still run and return the value.
        let uc = NebulaUseCase<EchoInput, Int>(name: "id") { $0.value }.instrumented()
        let out = try await uc.execute(EchoInput(value: 11))
        #expect(out == 11)
    }

    @Test func decoratorsProduceSendableUseCases() {
        func consume<T: Sendable>(_ v: T) {}
        let uc = NebulaUseCase<EchoInput, Int>(name: "s") { $0.value }
        consume(uc.reported(using: .default))
        consume(uc.measured(using: .default))
        consume(uc.logged(using: NebulaLogger(subsystem: "test", category: .general)))
        consume(uc.instrumented())
    }
}