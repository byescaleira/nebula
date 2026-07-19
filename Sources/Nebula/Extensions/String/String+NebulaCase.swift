//
//  String+NebulaCase.swift
//  Nebula
//
//  Identifier case conversion: `camelCased()`, `snakeCased()`, `kebabCased()`.
//  Splits on non-alphanumeric separators AND on camelCase / acronym
//  boundaries (e.g. "XMLParser" → ["XML", "Parser"]). Natural names per
//  CLAUDE.md — stdlib deliberately lacks identifier-case conversion. See
//  vault/01-fundamentos/nebula-string-extensions.md.
//
//  No `@available` gate: the implementation uses only `Character` property
//  checks (`isUppercase`/`isLowercase`/`isNumber`) and `String.split` — all
//  available well below the .v26 floor.
//

import Foundation

extension String {
    /// Returns the receiver converted to `camelCase`.
    ///
    /// The first word is lowercased; subsequent words are capitalized
    /// (first character uppercased, rest lowercased). Non-alphanumeric
    /// characters act as word separators, as do camelCase and acronym
    /// boundaries. An empty input returns an empty string.
    ///
    /// ```swift
    /// "snake_case_thing".camelCased()      // "snakeCaseThing"
    /// "kebab-case-thing".camelCased()      // "kebabCaseThing"
    /// "PascalCaseThing".camelCased()       // "pascalCaseThing"
    /// "XMLParser".camelCased()             // "xmlParser"
    /// ```
    public func camelCased() -> String {
        let words = nebulaIdentifierWords()
        guard !words.isEmpty else { return "" }
        let head = words[0].lowercased()
        let tail = words.dropFirst().map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return head + tail.joined()
    }

    /// Returns the receiver converted to `snake_case`.
    ///
    /// All words are lowercased and joined with `_`. Non-alphanumeric
    /// characters act as word separators, as do camelCase and acronym
    /// boundaries. An empty input returns an empty string.
    ///
    /// ```swift
    /// "camelCaseThing".snakeCased()        // "camel_case_thing"
    /// "kebab-case-thing".snakeCased()      // "kebab_case_thing"
    /// "XMLParser".snakeCased()             // "xml_parser"
    /// ```
    public func snakeCased() -> String {
        nebulaIdentifierWords().map { $0.lowercased() }.joined(separator: "_")
    }

    /// Returns the receiver converted to `kebab-case`.
    ///
    /// All words are lowercased and joined with `-`. Non-alphanumeric
    /// characters act as word separators, as do camelCase and acronym
    /// boundaries. An empty input returns an empty string.
    ///
    /// ```swift
    /// "camelCaseThing".kebabCased()        // "camel-case-thing"
    /// "snake_case_thing".kebabCased()      // "snake-case-thing"
    /// "XMLParser".kebabCased()             // "xml-parser"
    /// ```
    public func kebabCased() -> String {
        nebulaIdentifierWords().map { $0.lowercased() }.joined(separator: "-")
    }

    /// Splits the receiver into identifier words.
    ///
    /// Splits on any non-alphanumeric character (existing separators such as
    /// `_`, `-`, spaces) and additionally inserts boundaries:
    /// - between a lowercase/digit and an uppercase letter (`aB` → `a`|`B`),
    /// - before the last uppercase of an acronym run that is followed by a
    ///   lowercase letter (`XMLParser` → `XML`|`Parser`).
    private func nebulaIdentifierWords() -> [String] {
        guard !isEmpty else { return [] }
        let chars = Array(self)
        var withBoundaries = ""
        for (i, ch) in chars.enumerated() {
            if i == 0 { withBoundaries.append(ch); continue }
            let prev = chars[i - 1]
            let lowerOrDigitBoundary =
                (prev.isLowercase || prev.isNumber) && ch.isUppercase
            let acronymBoundary = prev.isUppercase && ch.isUppercase
                && i + 1 < chars.count && chars[i + 1].isLowercase
            if lowerOrDigitBoundary || acronymBoundary {
                withBoundaries.append(" ")
            }
            withBoundaries.append(ch)
        }
        return withBoundaries
            .split(omittingEmptySubsequences: true, whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }
}