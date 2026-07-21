//
//  NebulaUserError.swift
//  Nebula
//
//  Wave N12 — User-error bridge. A Foundation-tier value an app/Cosmos renders
//  as a user-facing error: a message, a list of value-based recovery actions,
//  and an optional help anchor. This is the *opposite* direction from
//  ``NebulaFailure`` (which bridges a layer error *into* the closed
//  ``NebulaError/Kind`` envelope): ``NebulaUserError`` is the *output* of a
//  ``NebulaErrorConfiguration`` map (`NebulaError → NebulaUserError?`), so it
//  is a plain `Sendable` value — it does **not** conform to ``NebulaFailure``
//  and adds **no** case to the closed `Kind` enum. Apple's `RecoverableError`
//  is closure-based (`attemptRecovery` callbacks), not value-based — there is
//  no `RecoveryAction` enum in Apple, so Nebula authors one. `RecoveryURL` is
//  not public Apple API and is deliberately not modeled. See
//  vault/03-padroes/nebula-user-error.md.
//

import Foundation

/// A value-based recovery action a user-facing error can offer.
///
/// Apple's `RecoverableError` protocol is closure-based — its
/// `attemptRecovery(optionIndex:)` callbacks bake UI and timing into the error
/// value. Nebula ships a **value** enum instead, so a ``NebulaUserError``
/// carries the recoverable intent as data and the presentation layer (Cosmos /
/// the app) decides how to surface it. Conforms to `CustomStringConvertible`
/// so the default/English path has a ready verb button title (HIG: button
/// titles are verbs); the app localizes by switching on the case (not by
/// reading `description`), so `description` is the developer fallback only.
public enum RecoveryAction: Sendable, Equatable, Hashable, CustomStringConvertible {

    /// Retry the failed operation.
    case retry
    /// Cancel the operation (a destructive/no-op default for non-destructive
    /// errors, or the cancel side of a destructive confirmation).
    case cancel
    /// Dismiss the error (no further action; the non-destructive default).
    case dismiss
    /// An app-defined action, keyed by a label the presentation layer resolves.
    case custom(String)

    public var description: String {
        switch self {
        case .retry: "Retry"
        case .cancel: "Cancel"
        case .dismiss: "Dismiss"
        case .custom(let label): label
        }
    }
}

/// A Foundation-tier user-facing error value an app or Cosmos renders.
///
/// `NebulaError` already conforms to `LocalizedError` / `CustomNSError`, but
/// its ``NebulaError/message`` is developer-facing English. ``NebulaUserError``
/// is the value the presentation layer renders: a human-facing message, a
/// list of ``RecoveryAction``s, and an optional `helpAnchor` (aligned with
/// `LocalizedError.helpAnchor` / `NSHelpAnchorErrorKey`). It is **not** a
/// ``NebulaFailure`` — it is the *output* of a ``NebulaErrorConfiguration``
/// map (`NebulaError → NebulaUserError?`), not a layer error bridged into the
/// closed ``NebulaError/Kind`` envelope. Derives `Sendable`, `Equatable`, and
/// `Hashable` from its pure-value fields (no `@unchecked`).
public struct NebulaUserError: Sendable, Equatable, Hashable {

    /// The human-facing message (the "what happened" of an alert).
    public let message: String
    /// The value-based recovery actions offered (the "how to proceed").
    public let recoveryActions: [RecoveryAction]
    /// An optional help anchor (a documentation key / `NSHelpAnchorErrorKey`).
    public let helpAnchor: String?

    /// Creates a user-facing error value.
    public init(
        message: String,
        recoveryActions: [RecoveryAction] = [],
        helpAnchor: String? = nil
    ) {
        self.message = message
        self.recoveryActions = recoveryActions
        self.helpAnchor = helpAnchor
    }

    /// The shipped overridable English fallback for a ``NebulaError/Kind``.
    ///
    /// Returns an English ``NebulaUserError`` per `Kind` with HIG-neutral tone
    /// (non-accusatory, no "you/your/we") and sensible ``RecoveryAction``s.
    /// The app wires this default via
    /// ``NebulaErrorConfiguration/withUserMessageMap(_:)`` and overrides it for
    /// localization via `String(localized:)` **at the app layer** — Nebula
    /// emits developer-facing English only. `context` is accepted so a custom
    /// map (and this default's signature) can interpolate runtime metadata;
    /// this default uses fixed strings. Always returns a value (`.unknown`
    /// falls back to a generic message).
    public static func `default`(
        for kind: NebulaError.Kind,
        context: [String: String] = [:]
    ) -> NebulaUserError {
        switch kind {
        case .network:
            NebulaUserError(message: "Unable to reach the service.", recoveryActions: [.retry, .cancel])
        case .decoding, .serialization, .encoding:
            NebulaUserError(message: "Couldn't read the received data.", recoveryActions: [.dismiss])
        case .cocoa:
            NebulaUserError(message: "The operation couldn't be completed.", recoveryActions: [.retry, .cancel])
        case .file:
            NebulaUserError(message: "Couldn't access the file.", recoveryActions: [.retry, .cancel])
        case .validation:
            NebulaUserError(message: "Please review the highlighted fields.", recoveryActions: [.dismiss])
        case .unknown:
            NebulaUserError(message: "Something went wrong.", recoveryActions: [.dismiss])
        }
    }
}