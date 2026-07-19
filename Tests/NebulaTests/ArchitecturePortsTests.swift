//
//  ArchitecturePortsTests.swift
//  NebulaTests
//
//  Wave H1 — Clean Architecture toolkit port/DTO marker tests (Swift Testing):
//  NebulaInputPort, NebulaOutputPort, NebulaDTO are bare Sendable markers that
//  the app's concrete use cases, presenters, and DTOs conform to.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - Fixtures

private struct LoginInput: NebulaInputPort, NebulaDTO {
    let email: String
    let password: String
}

private struct LoginResult: NebulaDTO, Equatable {
    let token: String
}

// A per-use-case output port defined by the app (Nebula defines no presenter).
private protocol LoginOutput: NebulaOutputPort {
    func didLogin(_ result: LoginResult)
    func didFail(_ error: NebulaError)
}

// A concrete (app-side) presenter conforming to the output port. Because
// `NebulaOutputPort: Sendable`, a presenter that keeps mutable state guards it
// behind a `Mutex` (the documented `ErrorCapture`/`NebulaMemoryLogHandler`
// precedent: `final class @unchecked Sendable` + `let Mutex`).
private final class LoginPresenter: LoginOutput, @unchecked Sendable {
    private let mutex = Mutex<(LoginResult?, NebulaError?)>((nil, nil))
    func didLogin(_ result: LoginResult) { mutex.withLock { $0.0 = result } }
    func didFail(_ error: NebulaError) { mutex.withLock { $0.1 = error } }
    var lastResult: LoginResult? { mutex.withLock { $0.0 } }
    var lastError: NebulaError? { mutex.withLock { $0.1 } }
}

@Suite("Architecture ports & DTO")
struct ArchitecturePortsTests {
    @Test func inputPortAndDTOAreSendable() {
        func consume<T: NebulaInputPort>(_ v: T) {}
        func consumeDTO<T: NebulaDTO>(_ v: T) {}
        consume(LoginInput(email: "a@b.com", password: "secret"))
        consumeDTO(LoginInput(email: "a@b.com", password: "secret"))
        consumeDTO(LoginResult(token: "tok"))
    }

    @Test func outputPortIsImplementedByPresenter() {
        // Nebula ships the NebulaOutputPort seam; the app's presenter conforms.
        let presenter = LoginPresenter()
        let port: LoginOutput = presenter
        let result = LoginResult(token: "tok")
        port.didLogin(result)
        #expect(presenter.lastResult == result)
    }

    @Test func outputPortFailureCarriesNebulaError() {
        let presenter = LoginPresenter()
        let port: LoginOutput = presenter
        let err = NebulaError(code: .init(domain: "App", code: 1), kind: .validation, message: "bad")
        port.didFail(err)
        #expect(presenter.lastError == err)
    }

    @Test func markersAreSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(LoginInput(email: "a", password: "b"))
        consume(LoginResult(token: "t"))
        // The presenter is app-owned and not required to be Sendable by Nebula.
    }
}