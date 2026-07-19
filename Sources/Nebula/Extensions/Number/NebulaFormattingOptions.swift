//
//  NebulaFormattingOptions.swift
//  Nebula
//
//  A `Sendable` value carrying the formatting contract (locale, percent
//  precision, ISO 4217 currency code, byte-count style) with fluent `.with*`
//  builders. Mirrors the Cosmos sibling's configuration pattern WITHOUT
//  SwiftUI `@Entry`/`@Observable` — Nebula is a foundation. All stored fields
//  are `Sendable`, so `Sendable` is DERIVED (no `@unchecked`). No shared mutable
//  state lives here; formatters are constructed per call by
//  ``NebulaNumberFormatting``. See
//  vault/01-fundamentos/nebula-number-measurement-extensions.md.
//
//  `ByteCountFormatStyle.Style` is `Sendable` (verified `.swiftinterface` line
//  20458). `Measurement<Unit>.FormatStyle.UnitWidth` is generic over
//  `Unit: Dimension` and cannot live in a non-generic struct without type
//  erasure, so it is NOT a field — pass `width` explicitly to
//  ``NebulaNumberFormatting/measurement(_:width:options:usage:)``.
//

import Foundation

/// Formatting options shared by the ``NebulaNumberFormatting`` facade.
///
/// A `Sendable` value (derived — every stored field is `Sendable`) describing
/// locale, percent fraction precision, ISO 4217 currency code, and byte-count
/// style. Per the Nebula contract, options flow through explicit construction
/// (no SwiftUI `@Entry`); per-instance overrides use the fluent `.with*`
/// builders, which return a mutated copy.
public struct NebulaFormattingOptions: Sendable {

    /// The locale used by every format style built from these options.
    public let locale: Locale
    /// The fraction-length precision applied to percent styles, or `nil` for
    /// the locale default. Passed to `Precision.fractionLength(_:)`.
    public let percentPrecision: Int?
    /// An ISO 4217 currency code (e.g. `"USD"`). When `nil`, the facade falls
    /// back to `Locale.current.currency?.identifier` then `"USD"`.
    public let currencyCode: String?
    /// The byte-count presentation used by ``NebulaNumberFormatting/bytes(_:options:)``.
    public let byteStyle: ByteCountFormatStyle.Style

    /// Creates formatting options.
    public init(
        locale: Locale = .autoupdatingCurrent,
        percentPrecision: Int? = nil,
        currencyCode: String? = nil,
        byteStyle: ByteCountFormatStyle.Style = .file
    ) {
        self.locale = locale
        self.percentPrecision = percentPrecision
        self.currencyCode = currencyCode
        self.byteStyle = byteStyle
    }

    /// The default options. Override pieces with the `.with*` builders.
    public static let `default` = NebulaFormattingOptions()

    // MARK: - Fluent builders

    /// Returns a copy with the locale replaced.
    public func with(locale: Locale) -> NebulaFormattingOptions {
        .init(locale: locale, percentPrecision: percentPrecision, currencyCode: currencyCode, byteStyle: byteStyle)
    }

    /// Returns a copy with the percent precision replaced.
    public func with(percentPrecision: Int?) -> NebulaFormattingOptions {
        .init(locale: locale, percentPrecision: percentPrecision, currencyCode: currencyCode, byteStyle: byteStyle)
    }

    /// Returns a copy with the currency code replaced.
    public func with(currencyCode: String?) -> NebulaFormattingOptions {
        .init(locale: locale, percentPrecision: percentPrecision, currencyCode: currencyCode, byteStyle: byteStyle)
    }

    /// Returns a copy with the byte-count style replaced.
    public func with(byteStyle: ByteCountFormatStyle.Style) -> NebulaFormattingOptions {
        .init(locale: locale, percentPrecision: percentPrecision, currencyCode: currencyCode, byteStyle: byteStyle)
    }
}