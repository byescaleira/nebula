//
//  ArchitectureUserErrorTests.swift
//  NebulaTests
//
//  Wave N12 — user-error bridge tests (Swift Testing): RecoveryAction value
//  enum, NebulaUserError value, the default English table, and the
//  NebulaErrorConfiguration.withUserMessageMap builder + userError(for:) accessor
//  (not gated on isEnabled), plus the process-wide NebulaErrorConfig accessor.
//

import Testing
import Foundation
import Synchronization
import Nebula

@Suite("RecoveryAction")
struct RecoveryActionTests {
    @Test func equalityAndInequality() {
        #expect(RecoveryAction.retry == .retry)
        #expect(RecoveryAction.custom("a") == .custom("a"))
        #expect(RecoveryAction.retry != .cancel)
        #expect(RecoveryAction.custom("a") != .custom("b"))
        #expect(RecoveryAction.retry != .custom("Retry"))
    }

    @Test func descriptionIsVerbTitle() {
        #expect(RecoveryAction.retry.description == "Retry")
        #expect(RecoveryAction.cancel.description == "Cancel")
        #expect(RecoveryAction.dismiss.description == "Dismiss")
        #expect(RecoveryAction.custom("Erase").description == "Erase")
    }

    @Test func isHashable() {
        let set: Set<RecoveryAction> = [.retry, .retry, .cancel, .dismiss, .custom("x")]
        #expect(set.count == 4)
    }
}

@Suite("NebulaUserError value")
struct NebulaUserErrorTests {
    @Test func initStoresFields() {
        let err = NebulaUserError(message: "Nope", recoveryActions: [.retry, .cancel], helpAnchor: "anchor")
        #expect(err.message == "Nope")
        #expect(err.recoveryActions == [.retry, .cancel])
        #expect(err.helpAnchor == "anchor")
    }

    @Test func defaultRecoveryActionsAndHelpAnchor() {
        let err = NebulaUserError(message: "Nope")
        #expect(err.recoveryActions == [])
        #expect(err.helpAnchor == nil)
    }

    @Test func equalityIsFieldBased() {
        let a = NebulaUserError(message: "m", recoveryActions: [.retry], helpAnchor: "h")
        let b = NebulaUserError(message: "m", recoveryActions: [.retry], helpAnchor: "h")
        #expect(a == b)
        #expect(a != NebulaUserError(message: "m", recoveryActions: [.cancel]))
    }

    @Test func isHashable() {
        let set: Set<NebulaUserError> = [
            NebulaUserError(message: "a"),
            NebulaUserError(message: "a"),
            NebulaUserError(message: "b")
        ]
        #expect(set.count == 2)
    }
}

@Suite("NebulaUserError default table")
struct NebulaUserErrorDefaultTableTests {
    @Test func everyKindReturnsNonEmptyMessageAndActions() {
        for kind in NebulaError.Kind.allCases {
            let user = NebulaUserError.default(for: kind)
            #expect(!user.message.isEmpty, "message empty for \(kind)")
            #expect(!user.recoveryActions.isEmpty, "no actions for \(kind)")
        }
    }

    @Test func higNeutralToneNoAccusatoryPronouns() {
        // HIG: avoid "you/your/me/my/we" in alerts.
        for kind in NebulaError.Kind.allCases {
            let message = NebulaUserError.default(for: kind).message.lowercased()
            #expect(!message.contains("you"), "HIG violation for \(kind): \(message)")
            #expect(!message.contains("your"), "HIG violation for \(kind): \(message)")
            #expect(!message.contains(" we "), "HIG violation for \(kind): \(message)")
        }
    }

    @Test func unknownFallsBackToDismiss() {
        let user = NebulaUserError.default(for: .unknown)
        #expect(user.recoveryActions == [.dismiss])
    }

    @Test func networkOffersRetry() {
        let user = NebulaUserError.default(for: .network)
        #expect(user.recoveryActions.contains(.retry))
        #expect(user.recoveryActions.contains(.cancel))
    }

    @Test func decodingSerializationEncodingShareDismiss() {
        for kind in [NebulaError.Kind.decoding, .serialization, .encoding] {
            let user = NebulaUserError.default(for: kind)
            #expect(user.recoveryActions == [.dismiss], "wrong actions for \(kind)")
        }
    }

    @Test func contextParameterIsAccepted() {
        // The default table uses fixed strings; context is accepted for signature
        // parity with custom maps but does not change the default output.
        let without = NebulaUserError.default(for: .network)
        let with = NebulaUserError.default(for: .network, context: ["host": "api.acme.com"])
        #expect(without == with)
    }
}

private func makeError(kind: NebulaError.Kind, metadata: [String: String] = [:]) -> NebulaError {
    NebulaError(code: .init(domain: "Test", code: 0), kind: kind, message: "dev", metadata: metadata)
}

@Suite("NebulaErrorConfiguration user-error bridge")
struct NebulaUserErrorConfigTests {
    @Test func defaultConfigMapReturnsNil() {
        let config = NebulaErrorConfiguration.default
        #expect(config.userError(for: makeError(kind: .network)) == nil)
    }

    @Test func withUserMessageMapResolvesAndPassesKindAndMetadata() {
        let captured = Mutex<(NebulaError.Kind, [String: String])?>(nil)
        let config = NebulaErrorConfiguration.default.withUserMessageMap { kind, context in
            captured.withLock { $0 = (kind, context) }
            return NebulaUserError(message: "user-\(kind.rawValue)")
        }
        let error = makeError(kind: .validation, metadata: ["field": "email"])
        let user = config.userError(for: error)
        let snapshot = captured.withLock { $0 }
        #expect(snapshot?.0 == .validation)
        #expect(snapshot?.1 == ["field": "email"])
        #expect(user?.message == "user-validation")
    }

    @Test func withUserMessageMapPreservesOtherFields() {
        let handlerCalls = Mutex(0)
        let config = NebulaErrorConfiguration(
            isEnabled: true,
            category: "App",
            handler: { _ in handlerCalls.withLock { $0 += 1 } }
        ).withUserMessageMap { kind, _ in
            NebulaUserError(message: "user-\(kind.rawValue)")
        }
        #expect(config.isEnabled == true)
        #expect(config.category == "App")
        config.report(makeError(kind: .unknown))
        #expect(handlerCalls.withLock { $0 } == 1)
        #expect(config.userError(for: makeError(kind: .unknown))?.message == "user-unknown")
    }

    @Test func userErrorNotGatedOnIsEnabled() {
        let config = NebulaErrorConfiguration(isEnabled: false).withUserMessageMap { kind, _ in
            NebulaUserError(message: "user-\(kind.rawValue)")
        }
        // Reporting is disabled...
        config.report(makeError(kind: .network))
        // ...but user-message mapping still resolves.
        #expect(config.userError(for: makeError(kind: .network))?.message == "user-network")
    }

    @Test func defaultTableWiredViaBuilder() {
        let config = NebulaErrorConfiguration.default
            .withUserMessageMap { NebulaUserError.default(for: $0, context: $1) }
        let user = config.userError(for: makeError(kind: .network))
        #expect(user == NebulaUserError.default(for: .network))
    }

    @Test func mapCanDeclineAKind() {
        let config = NebulaErrorConfiguration.default.withUserMessageMap { kind, _ in
            kind == .unknown ? nil : NebulaUserError(message: "mapped")
        }
        #expect(config.userError(for: makeError(kind: .validation)) != nil)
        #expect(config.userError(for: makeError(kind: .unknown)) == nil)
    }
}

@Suite("NebulaErrorConfig accessor", .serialized)
struct NebulaErrorConfigUserErrorTests {
    @Test func processWideAccessorResolvesUserError() {
        NebulaErrorConfig.set(
            .default.withUserMessageMap { kind, _ in
                NebulaUserError(message: "global-\(kind.rawValue)")
            }
        )
        defer { NebulaErrorConfig.set(.default) }
        let user = NebulaErrorConfig.userError(for: makeError(kind: .file))
        #expect(user?.message == "global-file")
    }

    @Test func defaultAccessorReturnsNil() {
        NebulaErrorConfig.set(.default)
        defer { NebulaErrorConfig.set(.default) }
        #expect(NebulaErrorConfig.userError(for: makeError(kind: .network)) == nil)
    }
}