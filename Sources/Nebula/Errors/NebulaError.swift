//
//  NebulaError.swift
//  Nebula
//
//  The Nebula error envelope: a Sendable, throwable `Error` carrying structured
//  metadata with deterministic NSError bridging. Mirrors the Cosmos sibling's
//  CosmosErrorConfiguration pattern WITHOUT SwiftUI. See
//  vault/01-fundamentos/nebula-errors.md.
//
//  Verified against the Xcode 27 Beta 3 SDK: LocalizedError/CustomNSError/
//  RecoverableError/CocoaError/URLError are iOS 8+/macOS 10.10+ (all below the
//  .v26 floor); `Mutex` is macOS 15.0+ (below floor). No @available gating.
//

import Foundation

/// A standard, `Sendable`, throwable error envelope for the Nebula foundation.
///
/// `NebulaError` is a uniform error shape that:
/// - conforms to `Error`, `LocalizedError`, and `CustomNSError` for
///   deterministic `NSError` bridging;
/// - is `Sendable` (derived — no `@unchecked`) so it crosses actor boundaries
///   and rides inside `@Sendable` handlers;
/// - carries structured metadata (domain/code, kind, message, failure reason,
///   recovery suggestions, help anchor, metadata, coding-path context, date,
///   one nested underlying error) without retaining a non-`Sendable` `any Error`.
///
/// `any Error` is not `Sendable` (SE-0302); the lossy mapping initializers in
/// ``NebulaError`` consume the source error at construction time and keep only
/// `Sendable` fragments. Consumers needing the original error must catch it
/// before mapping.
///
/// Per SE-0413, public Nebula APIs use untyped `throws`; `NebulaError` is exposed
/// as an opt-in concrete `Failure` so consumers MAY declare `func f()
/// throws(NebulaError)` / `Result<T, NebulaError>`.
public struct NebulaError: Error, LocalizedError, CustomNSError, Sendable, Hashable {

    // MARK: - Nested types

    /// A `(domain, code)` pair identifying an error.
    public struct Code: Sendable, Hashable {
        /// The error domain (e.g. `NSURLErrorDomain`, `Swift.DecodingError`).
        public let domain: String
        /// The error code within the domain.
        public let code: Int
        /// Creates a code.
        public init(domain: String, code: Int) {
            self.domain = domain
            self.code = code
        }
    }

    /// A coarse classification of the error.
    ///
    /// A closed `enum` for v26; the deprecation path to an open `struct` is
    /// available if consumers need custom kinds without a library release.
    public enum Kind: String, Sendable, CaseIterable {
        /// Network/transport errors (`URLError`).
        case network
        /// `DecodingError`.
        case decoding
        /// `EncodingError`.
        case encoding
        /// `CocoaError` (Foundation).
        case cocoa
        /// File-system errors (a subset of `CocoaError`).
        case file
        /// Validation failures.
        case validation
        /// Serialization failures.
        case serialization
        /// Anything else.
        case unknown
    }

    /// Decoding/validation context, with the coding path stringified.
    public struct Context: Sendable, Hashable {
        /// The stringified `DecodingError.Context.codingPath`.
        public let codingPath: [String]
        /// The debug description from the source context, if any.
        public let debugDescription: String?
        /// A caller-site tag, if any.
        public let source: String?
        /// Creates a context.
        public init(codingPath: [String] = [], debugDescription: String? = nil, source: String? = nil) {
            self.codingPath = codingPath
            self.debugDescription = debugDescription
            self.source = source
        }
    }

    /// Breaks the value-type recursion: a Swift `struct` cannot contain itself,
    /// so `underlying` must be boxed. A `final class` with a `Sendable` `let`
    /// gets a *derived* `Sendable` conformance — no `@unchecked`.
    public final class Box: Sendable, Hashable {
        /// The boxed nested error.
        public let value: NebulaError
        /// Creates a box.
        public init(_ v: NebulaError) { self.value = v }
        public static func == (l: Box, r: Box) -> Bool { l.value == r.value }
        public func hash(into h: inout Hasher) { h.combine(value) }
    }

    // MARK: - Stored properties (var so consumers can build/tweak; Sendable is
    // derived because every field is Sendable — value-type mutation is local).

    /// The domain/code identifier.
    public var code: Code
    /// The coarse classification.
    public var kind: Kind
    /// The human-facing message (also `errorDescription`).
    public var message: String
    /// Why the error occurred (`LocalizedError.failureReason`).
    public var failureReason: String?
    /// Recovery suggestions (`LocalizedError.recoverySuggestion` joins these).
    public var recoverySuggestions: [String]
    /// A help anchor (`LocalizedError.helpAnchor`).
    public var helpAnchor: String?
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// Decoding/validation context.
    public var context: Context?
    /// When the error was constructed.
    public var date: Date
    /// One nested underlying error (boxed to break struct recursion). Deep
    /// `NSError` underlying-error chains are flattened to one level (the boxed
    /// error's own `underlying` is forced to `nil`).
    public var underlying: Box?

    /// Creates an error.
    public init(
        code: Code,
        kind: Kind,
        message: String,
        failureReason: String? = nil,
        recoverySuggestions: [String] = [],
        helpAnchor: String? = nil,
        metadata: [String: String] = [:],
        context: Context? = nil,
        date: Date = Date(),
        underlying: Box? = nil
    ) {
        self.code = code
        self.kind = kind
        self.message = message
        self.failureReason = failureReason
        self.recoverySuggestions = recoverySuggestions
        self.helpAnchor = helpAnchor
        self.metadata = metadata
        self.context = context
        self.date = date
        self.underlying = underlying
    }

    // MARK: - LocalizedError

    /// `LocalizedError.errorDescription` — the message.
    public var errorDescription: String? { message }

    /// `LocalizedError.recoverySuggestion` — the suggestions joined by a space.
    public var recoverySuggestion: String? {
        recoverySuggestions.isEmpty ? nil : recoverySuggestions.joined(separator: " ")
    }

    // MARK: - CustomNSError

    /// `CustomNSError.errorDomain` — a stable, deterministic domain.
    public static var errorDomain: String { "Nebula.NebulaError" }

    /// `CustomNSError.errorCode` — the code within the domain.
    public var errorCode: Int { code.code }

    /// `CustomNSError.errorUserInfo` — the localized keys plus Nebula metadata.
    ///
    /// The `NSLocalized*`/`NSUnderlyingErrorKey` constants are Clang-imported
    /// `String`s from `Foundation/Headers/NSError.h` (not the `.swiftinterface`
    /// `ErrorUserInfoKey` aliases).
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let f = failureReason { info[NSLocalizedFailureReasonErrorKey] = f }
        if let r = recoverySuggestion { info[NSLocalizedRecoverySuggestionErrorKey] = r }
        if let h = helpAnchor { info[NSHelpAnchorErrorKey] = h }
        info["NebulaKind"] = kind.rawValue
        info["NebulaDomain"] = code.domain
        for (k, v) in metadata { info["Nebula.\(k)"] = v }
        if let u = underlying { info[NSUnderlyingErrorKey] = u.value as NSError }
        return info
    }
}