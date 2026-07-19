//
//  NebulaRegex.swift
//  Nebula
//
//  A thin value wrapper over `Regex<Output>`. The stdlib regex algorithms
//  (`firstMatch(of:)` / `wholeMatch(of:)` / `matches(of:)` / `contains(_:)`)
//  are NOT redeclared — they are reused on the underlying `Regex`, which
//  `NebulaRegex` exposes. Regex / RegexBuilder are iOS 16+ / macOS 13+
//  (below the .v26 floor, no `@available` gate). See
//  vault/01-fundamentos/nebula-string-extensions.md.
//
//  IMPORTANT — NOT Sendable: verified against the Xcode 27 Beta 3 SDK
//  `_StringProcessing.swiftmodule` (arm64e-apple-ios): `Regex<Output>` has
//  NO `Sendable` conformance (the interface contains zero `Sendable`
//  mentions). `NebulaRegex` therefore CANNOT be `Sendable` either — the
//  `regex` field is non-Sendable, and CLAUDE.md forbids `@unchecked Sendable`
//  on Nebula-defined types. A regex instance must be constructed and
//  consumed on the same isolation domain; do not capture it in a
//  `@Sendable` closure or store it across actors. The vault note's claim
//  that "Regex<Output> is Sendable where Output: Sendable" is refuted by the
//  interface and corrected here.
//

import Foundation
import RegexBuilder

/// A value wrapper over a Swift `Regex<Output>`.
///
/// The stdlib match algorithms are forwarded unchanged (not redeclared):
/// - ``firstMatch(in:)`` → `StringProtocol.firstMatch(of:)`
/// - ``wholeMatch(_:)`` → `StringProtocol.wholeMatch(of:)`
/// - ``matches(in:)`` → `StringProtocol.matches(of:)`
/// - ``contains(_:)`` → `StringProtocol.contains(_:)`
///
/// - Note: This type is intentionally **NOT `Sendable`**: `Regex<Output>` is
///   not `Sendable` (verified against the Xcode 27 Beta 3 SDK), so neither is
///   this wrapper. Construct and use a `NebulaRegex` within a single
///   isolation domain.
public struct NebulaRegex<Output> {
    /// The underlying `Regex<Output>`.
    public let regex: Regex<Output>

    /// Creates a wrapper around an existing `Regex`.
    public init(_ regex: Regex<Output>) { self.regex = regex }

    /// Creates a wrapper by building a `Regex` with the
    /// `@RegexComponentBuilder` DSL. The builder closure is invoked once and
    /// is not retained.
    public init(@RegexComponentBuilder _ build: () -> Regex<Output>) {
        self.regex = build()
    }

    /// Returns the first match of ``regex`` in `input`, or `nil`.
    ///
    /// `input` is bridged to `String` so the stdlib match algorithm
    /// (`BidirectionalCollection where SubSequence == Substring`) applies; the
    /// algorithm is **reused**, not redeclared.
    public func firstMatch(in input: some StringProtocol) -> Regex<Output>.Match? {
        String(input).firstMatch(of: regex)
    }

    /// Returns a match only if ``regex`` matches `input` in its entirety,
    /// else `nil`.
    ///
    /// See ``firstMatch(in:)`` for the `String` bridge rationale.
    public func wholeMatch(_ input: some StringProtocol) -> Regex<Output>.Match? {
        String(input).wholeMatch(of: regex)
    }

    /// Returns every match of ``regex`` in `input`, in order.
    ///
    /// See ``firstMatch(in:)`` for the `String` bridge rationale.
    public func matches(in input: some StringProtocol) -> [Regex<Output>.Match] {
        Array(String(input).matches(of: regex))
    }

    /// `true` if ``regex`` matches anywhere in `input`.
    ///
    /// `String.contains(_:)` (the regex overload, iOS 16+) is **reused**, not
    /// redeclared. See ``firstMatch(in:)`` for the `String` bridge rationale.
    public func contains(_ input: some StringProtocol) -> Bool {
        String(input).contains(regex)
    }
}