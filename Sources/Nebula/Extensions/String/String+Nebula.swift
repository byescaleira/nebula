//
//  String+Nebula.swift
//  Nebula
//
//  `String` validation/manipulation gap-fillers: `isBlank`, `nilIfEmpty`,
//  `nilIfBlank`, `trimmed`, and grapheme-cluster-safe `truncated(to:with:)`.
//  Natural names per CLAUDE.md — these are deliberate stdlib gap-fillers, NOT
//  redeclarations (stdlib `String.trimmingCharacters(in:)` is the building
//  block, reused — never wrapped under a nebula* prefix). See
//  vault/01-fundamentos/nebula-string-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK: `trimmingCharacters(in:)` is
//  `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` (interface
//  line 22672) — well below the .v26 floor, so no `@available` gate.
//

import Foundation

extension String {
    /// `true` if `self` is empty or contains only whitespace and newlines.
    ///
    /// Useful for input validation where a user-typed whitespace-only value
    /// should be treated as absent. This is distinct from `isEmpty`, which
    /// is `true` only for the zero-length string.
    public var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `self` unless it is empty, in which case `nil`.
    ///
    /// Coalesces empty strings to `nil` for DTOs / `Codable` round-trips
    /// where an empty value is indistinguishable from an absent one.
    public func nilIfEmpty() -> String? { isEmpty ? nil : self }

    /// `self` unless it is blank (see ``isBlank``), in which case `nil`.
    ///
    /// Like ``nilIfEmpty()`` but also coalesces whitespace-only strings.
    public func nilIfBlank() -> String? { isBlank ? nil : self }

    /// A copy with leading and trailing whitespace AND newlines removed.
    ///
    /// A convenience property over stdlib `trimmingCharacters(in:)` for the
    /// overwhelmingly common `.whitespacesAndNewlines` case. The stdlib
    /// initializer is reused, not redeclared.
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns `self` if it fits within `maxLength` grapheme clusters;
    /// otherwise returns a truncation capped at `maxLength` grapheme clusters
    /// with `ellipsis` appended.
    ///
    /// Truncation is **grapheme-cluster-safe**: it counts `Character`s
    /// (extended grapheme clusters), not `Unicode.Scalar`s or UTF-16 code
    /// units, so composed character sequences (e.g. é, 👨‍👩‍👧) are never split.
    ///
    /// - Parameters:
    ///   - maxLength: The maximum number of `Character`s in the result,
    ///     including the ellipsis when present. If `maxLength` is `0` an
    ///     empty string is returned.
    ///   - ellipsis: The suffix appended when truncation occurs. Pass `nil`
    ///     for a hard cut with no marker. Defaults to `"…"`.
    /// - Returns: The (possibly truncated) string, never longer than
    ///   `maxLength` grapheme clusters.
    public func truncated(to maxLength: Int, with ellipsis: String? = "…") -> String {
        guard maxLength > 0 else { return "" }
        if count <= maxLength { return self }
        guard let ellipsis else {
            return String(prefix(maxLength))
        }
        let ellipsisCount = ellipsis.count
        if maxLength <= ellipsisCount {
            return String(ellipsis.prefix(maxLength))
        }
        let keep = maxLength - ellipsisCount
        return String(prefix(keep)) + ellipsis
    }
}