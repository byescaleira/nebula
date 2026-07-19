//
//  UUID+Nebula.swift
//  Nebula
//
//  `UUID` gap-fillers: `shortString` (first 8 hex chars) and `isValid(_:)`
//  (validate via the existing `init?(uuidString:)`). Never redeclares `UUID()`,
//  `init?(uuidString:)`, or `uuidString`. Natural names per CLAUDE.md.
//  See vault/01-fundamentos/nebula-primitive-extensions.md.
//

import Foundation

extension UUID {
    /// The first 8 hex characters of `uuidString` (e.g. `"12345678"`).
    ///
    /// Useful for short, human-scannable log identifiers that still trace to a
    /// full UUID.
    public var shortString: String {
        String(uuidString.prefix(8))
    }

    /// Returns `true` if `string` is a valid UUID string.
    ///
    /// Validates via the existing `init?(uuidString:)` initializer; never
    /// redeclares it.
    public static func isValid(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }
}