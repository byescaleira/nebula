//
//  NebulaRegexPatterns.swift
//  Nebula
//
//  Curated `Regex` literals for structured tokens: UUID, IPv4, hex color,
//  semantic version, ISO-8601 timestamp. Deliberately excludes email and
//  phone-number patterns — per Apple's `NSDataDetector` guidance
//  (`NSRegularExpression.h` line 545: "Don't use `NSDataDetector` to
//  validate data") and the regex pitfalls that come with them, Nebula ships
//  no email/phone validation regex. Consumers should validate such data
//  with the type's own initializer (e.g. parse a date via `Date.ISO8601`)
//  rather than a regex. See vault/01-fundamentos/nebula-string-extensions.md.
//
//  Regex literals are iOS 16+ / macOS 13+ (below the .v26 floor, no
//  `@available` gate).
//
//  CONCURRENCY: `Regex<Substring>` is NOT `Sendable` (verified against the
//  Xcode 27 Beta 3 SDK — `Regex` has no `Sendable` conformance). A `static
//  let` of a non-Sendable type is a `MutableGlobalVariable` error under Swift
//  6, and CLAUDE.md forbids `nonisolated(unsafe)` globals and `@unchecked
//  Sendable` on Nebula types. The patterns are therefore **computed
//  properties** — each access rebuilds a fresh `Regex` value. The regex
//  *program* is a literal constant (compiled once per site), so the per-call
//  cost is a lightweight value construction, and each caller gets an
//  isolation-local instance that never crosses actors.
//

import Foundation

/// A namespace of curated `Regex` literals for structured tokens.
///
/// These are intentionally narrow: they recognize the *shape* of a token
/// (useful for highlighting / extraction in natural language text), not the
/// full validity space. For strict validation, prefer the type's own
/// initializer (`UUID(uuidString:)`, `URL(string:)`, `Date.ISO8601`) — see
/// the "Don't validate data with regex" note above.
public enum NebulaRegexPatterns {
    /// A UUID in canonical 8-4-4-4-12 hex form (any case).
    public static var uuid: Regex<Substring> {
        /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/
    }

    /// An IPv4 dotted-quad (digits 0–9 only; does NOT bound octets to 0–255).
    public static var ipv4: Regex<Substring> {
        /(?:\d{1,3}\.){3}\d{1,3}/
    }

    /// A CSS-style hex color: `#rgb` or `#rrggbb`, any case.
    public static var hexColor: Regex<Substring> {
        /#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b/
    }

    /// A semantic version `MAJOR.MINOR.PATCH` (no pre-release / build suffix).
    public static var semver: Regex<Substring> {
        /\d+\.\d+\.\d+/
    }

    /// An ISO-8601 UTC-or-offset timestamp `YYYY-MM-DDTHH:MM:SS` with an
    /// optional fractional-seconds and optional `Z` / `±HH:MM` zone.
    public static var iso8601: Regex<Substring> {
        /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?/
    }
}