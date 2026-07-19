//
//  NebulaStringLocalization.swift
//  Nebula
//
//  A `Sendable` localization contract mirroring the Cosmos sibling's
//  `CosmosLocalizationConfiguration` WITHOUT SwiftUI — Nebula is a foundation,
//  so localization is a constructed-and-passed value, not an environment
//  injection. Wraps `String(localized:)` (iOS 15 base, interface lines
//  21988–21989) and `AttributedString(localized:)` (iOS 15 FormattingOptions /
//  iOS 16 LocalizationOptions, interface lines 22058–22063) — all below the
//  .v26 floor, no `@available` gate. See
//  vault/01-fundamentos/nebula-string-extensions.md.
//
//  Sendable by derived conformance: `Bundle` is `@unchecked Sendable`
//  (iOS 15+/macOS 12+), `Locale` is `Sendable`, `String` is `Sendable` —
//  every stored field is Sendable on the .v26 floor. `String.LocalizationValue`
//  and `AttributedString.LocalizationOptions` are method parameters / return
//  types, not stored fields.
//

import Foundation

/// A `Sendable` localization contract for the Nebula foundation.
///
/// Carries the bundle, locale, and table used to resolve localized strings
/// and attributed strings via the String Catalog stack
/// (`String(localized:)` / `AttributedString(localized:)`). A foundation does
/// not own UI-thread affinity, so this is constructed and passed explicitly
/// — there is no SwiftUI `@Environment` injection in Nebula.
///
/// `Bundle`, `Locale`, and `String` are all `Sendable` on the .v26 floor, so
/// the struct's `Sendable` conformance is derived — no `@unchecked`.
public struct NebulaStringLocalization: Sendable {
    /// The bundle to resolve strings from. `nil` means the main bundle.
    public var bundle: Bundle?
    /// The locale to resolve into. `nil` means the system current locale.
    public var locale: Locale?
    /// The strings table (catalog) name. Defaults to `"Localizable"`.
    public var table: String

    /// Creates a localization contract.
    public init(
        bundle: Bundle? = nil,
        locale: Locale? = nil,
        table: String = "Localizable"
    ) {
        self.bundle = bundle
        self.locale = locale
        self.table = table
    }

    /// The default contract: main bundle, current locale, `"Localizable"`.
    public static let `default` = NebulaStringLocalization()

    /// Resolves a localized `String` for `key` from this contract.
    ///
    /// Forwards to `String(localized:table:bundle:locale:comment:)`. When no
    /// catalog entry exists, the key itself is returned (Apple's standard
    /// fallback).
    ///
    /// - Parameters:
    ///   - key: The localization key / value (a `String.LocalizationValue`,
    ///     which may interpolate).
    ///   - comment: A developer-facing comment for translators.
    public func string(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
        String(localized: key, table: table, bundle: bundle, locale: locale ?? .current, comment: comment)
    }

    /// Resolves a localized `AttributedString` for `key` from this contract.
    ///
    /// Forwards to `AttributedString(localized:options:table:bundle:locale:comment:)`
    /// (the `LocalizationOptions` form, iOS 16+ — below the .v26 floor). Use
    /// this when the catalog entry carries inline formatting / markdown
    /// attributes that should survive interpolation.
    ///
    /// - Note: `AttributedString.LocalizationOptions` is NOT an
    ///   `ExpressibleByArrayLiteral` `OptionSet` (unlike
    ///   `AttributedString.FormattingOptions`), so the default here is
    ///   `LocalizationOptions()` rather than `[]`.
    ///
    /// - Parameters:
    ///   - key: The localization key / value.
    ///   - options: `AttributedString.LocalizationOptions`.
    ///   - comment: A developer-facing comment for translators.
    public func attributed(
        _ key: String.LocalizationValue,
        options: AttributedString.LocalizationOptions = AttributedString.LocalizationOptions(),
        comment: StaticString? = nil
    ) -> AttributedString {
        AttributedString(localized: key, options: options, table: table, bundle: bundle, locale: locale, comment: comment)
    }
}