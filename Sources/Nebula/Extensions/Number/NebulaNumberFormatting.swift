//
//  NebulaNumberFormatting.swift
//  Nebula
//
//  A caseless `enum` facade over Foundation's modern `FormatStyle` family:
//  percent, currency, byte-count, list, and measurement formatting. Pure
//  functions, no stored state → implicitly `Sendable`. Every style is
//  constructed PER CALL (never cached) — the legacy `Formatter` subclasses
//  (`NumberFormatter`/`MeasurementFormatter`/`ByteCountFormatter`) are NOT used.
//  The single legacy exception is `ListFormatter` (no `FormatStyle` replacement,
//  not `Sendable`), wrapped per call. See
//  vault/01-fundamentos/nebula-number-measurement-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 `Foundation.swiftinterface`:
//  `IntegerFormatStyle` (line 19881), `FloatingPointFormatStyle` (19637),
//  `ByteCountFormatStyle` (20433), `Decimal.FormatStyle` (19388),
//  `Measurement.FormatStyle` (16521), `MeasurementFormatUnitUsage` (17296) all
//  carry `@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)` — strictly below
//  Nebula's `.v26` floor, so NO `@available` gating is needed. visionOS is
//  available from 1.0 (omitted platform → first version).
//

import Foundation

/// Locale-aware number and measurement formatting, built on the modern
/// `FormatStyle` family.
///
/// `NebulaNumberFormatting` is a caseless `enum` (no instances, no stored
/// state): every entry point is a pure `static` function that constructs a
/// `FormatStyle` for the call, applies it, and discards it. There is no
/// shared mutable state and no `Mutex`/`Atomic` in this layer.
///
/// - Note: `ListFormatter` is the single legacy `Formatter` subclass in the
///   surface (it has no `FormatStyle` replacement and is not `Sendable`); it is
///   instantiated per call and never cached.
public enum NebulaNumberFormatting {

    // MARK: - Percent

    /// Formats `value` as a locale-aware percentage.
    ///
    /// Uses `FloatingPointFormatStyle<Double>.Percent`. When
    /// ``NebulaFormattingOptions/percentPrecision`` is set, the style's
    /// `precision(.fractionLength(_))` is applied.
    public static func percent(
        _ value: Double,
        options: NebulaFormattingOptions = .default
    ) -> String {
        var style: FloatingPointFormatStyle<Double>.Percent = .percent
        style = style.locale(options.locale)
        if let p = options.percentPrecision {
            style = style.precision(.fractionLength(p))
        }
        return value.formatted(style)
    }

    /// Formats `value` as a locale-aware percentage using `Decimal.FormatStyle.Percent`.
    ///
    /// Prefer this overload when the source value is already `Decimal`: it
    /// avoids a base-2 `Double` round-trip and keeps base-10 precision.
    public static func percent(
        _ value: Decimal,
        options: NebulaFormattingOptions = .default
    ) -> String {
        var style: Decimal.FormatStyle.Percent = .percent
        style = style.locale(options.locale)
        if let p = options.percentPrecision {
            style = style.precision(.fractionLength(p))
        }
        return value.formatted(style)
    }

    // MARK: - Currency

    /// Formats `value` as a locale-aware currency amount.
    ///
    /// The ISO 4217 code is resolved as
    /// `options.currencyCode ?? Locale.current.currency?.identifier ?? "USD"`.
    /// For money, prefer the `currency(_:options:)` (`Decimal`) overload
    /// to avoid binary floating-point loss.
    public static func currency(
        _ value: Double,
        options: NebulaFormattingOptions = .default
    ) -> String {
        let code = resolvedCurrencyCode(options)
        var style: FloatingPointFormatStyle<Double>.Currency = .currency(code: code)
        style = style.locale(options.locale)
        return value.formatted(style)
    }

    /// Formats `value` as a locale-aware currency amount using `Decimal.FormatStyle.Currency`.
    ///
    /// The preferred path for money: `Decimal` is base-10 exact, so there is no
    /// binary-floating-point representation loss.
    public static func currency(
        _ value: Decimal,
        options: NebulaFormattingOptions = .default
    ) -> String {
        let code = resolvedCurrencyCode(options)
        var style: Decimal.FormatStyle.Currency = .currency(code: code)
        style = style.locale(options.locale)
        return value.formatted(style)
    }

    // MARK: - Byte count

    /// Formats `count` bytes using `ByteCountFormatStyle`.
    ///
    /// `ByteCountFormatStyle.format(_:)` takes `Int64` (`.swiftinterface` line
    /// 20456), so the value is passed through unchanged. The legacy
    /// `ByteCountFormatter` is NOT used.
    public static func bytes(
        _ count: Int64,
        options: NebulaFormattingOptions = .default
    ) -> String {
        count.formatted(.byteCount(style: options.byteStyle).locale(options.locale))
    }

    // MARK: - List

    /// Joins `items` into a locale-aware list string.
    ///
    /// `ListFormatter` is the single legacy `Formatter` subclass in the surface
    /// (no `FormatStyle` replacement, not `Sendable`). When the configured
    /// locale is `Locale.autoupdatingCurrent`, the stateless class method
    /// `ListFormatter.localizedString(byJoining:)` is used (no instance). For an
    /// explicit locale, a `ListFormatter` is constructed PER CALL, its `locale`
    /// set, `string(from:)` invoked, and the instance discarded — it is NEVER
    /// cached in `Sendable` state.
    public static func list(
        _ items: [String],
        options: NebulaFormattingOptions = .default
    ) -> String {
        if options.locale == .autoupdatingCurrent {
            return ListFormatter.localizedString(byJoining: items)
        }
        let formatter = ListFormatter()
        formatter.locale = options.locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    // MARK: - Measurement

    /// Formats a `Measurement<Unit>` using `Measurement<Unit>.FormatStyle`.
    ///
    /// Generic over `Unit: Dimension` (the `FormatStyle` is constrained to
    /// `Dimension`; `.swiftinterface` line 16521). `width` is passed explicitly
    /// because `Measurement<Unit>.FormatStyle.UnitWidth` is generic over `Unit`
    /// and cannot be stored in the non-generic ``NebulaFormattingOptions``.
    public static func measurement<Unit: Dimension>(
        _ measurement: Measurement<Unit>,
        width: Measurement<Unit>.FormatStyle.UnitWidth = .abbreviated,
        options: NebulaFormattingOptions = .default,
        usage: MeasurementFormatUnitUsage<Unit> = .general
    ) -> String {
        let style = Measurement<Unit>.FormatStyle(
            width: width,
            locale: options.locale,
            usage: usage,
            numberFormatStyle: nil
        )
        return measurement.formatted(style)
    }

    // MARK: - Internal

    /// Resolves the ISO 4217 currency code for the facade's currency paths.
    ///
    /// `Locale.current.currency?.identifier` is iOS 16+/macOS 13+ (verified
    /// `.swiftinterface` line 8767) — below the `.v26` floor, so no gate.
    private static func resolvedCurrencyCode(_ options: NebulaFormattingOptions) -> String {
        if let code = options.currencyCode { return code }
        if let identifier = Locale.current.currency?.identifier { return identifier }
        return "USD"
    }
}