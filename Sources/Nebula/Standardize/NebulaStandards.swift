//
//  NebulaStandards.swift
//  Nebula
//
//  The STANDARDIZE half of Wave F: a single `Sendable` facade over Foundation's
//  modern `FormatStyle` family (Date, ISO8601, Decimal, Integer, FloatingPoint,
//  Measurement, Currency, Percent, ByteCount, List, PersonNameComponents, URL,
//  Duration), producing `String` or `AttributedString`, locale/timeZone/calendar
//  aware. This is the third of Nebula's four configuration structs — and the
//  only one WITHOUT a handler: formatting is stateless, so there is no
//  `@Sendable` closure and no fan-out path.
//
//  The facade is deliberately THIN: each accessor returns a fresh Apple
//  `FormatStyle` value, pre-configured with this struct's locale/timeZone/
//  calendar, so callers keep the FULL Apple API (`.attributed`, `.precision`,
//  `.grouping`, `.notation`, `.locale`, …). Nebula does NOT re-wrap formatting
//  behind an opaque `format(_:)` — that would throw away the fluent builder
//  surface. Compose with the existing `NebulaDateFormat` / `NebulaDurationFormat`
//  presets (see Sources/Nebula/Extensions/DateTime/) rather than duplicate them;
//  those presets are pinned to `en_US_POSIX` + GMT for locale-independent output
//  (logs/persistence), while `NebulaStandards` carries the caller's locale for
//  UI/presentation.
//
//  See vault/01-fundamentos/nebula-standardize-measure.md for the verified API
//  surface table + ground-truth availability (the FormatStyle accessor shapes
//  there are authoritative). Foundation-only; no UIKit.
//

import Foundation

/// The Nebula formatting-standards configuration.
///
/// A `Sendable` value struct holding `locale`/`timeZone`/`calendar` and exposing
/// typed accessors that return Apple's modern `FormatStyle` values,
/// **pre-configured** with those three components. It is the third of Nebula's
/// four cross-cutting configuration structs (alongside `NebulaLogConfiguration`,
/// `NebulaErrorConfiguration`, `NebulaMeasureConfiguration`) — and, unlike the
/// others, it carries **no `@Sendable` handler**: formatting is stateless, so
/// there is no fan-out path and no `Equatable`-breaking closure.
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct + fluent
/// `.with*` builders — but with no SwiftUI `@Entry`/`@Observable`: a foundation
/// does not own UI-thread affinity, so configurations are constructed and
/// passed explicitly (or read process-wide via `NebulaStandardsConfig`).
///
/// ## Thin facade, not a re-wrap
///
/// Each accessor returns a fresh `Sendable` `FormatStyle` configured with this
/// struct's `locale`/`timeZone`/`calendar`. Callers keep the full Apple API —
/// `.attributed`, `.precision`, `.grouping`, `.notation`, `.locale`, etc. —
/// because Nebula returns the real Apple type rather than hiding it behind an
/// opaque `format(_:)`. Use the convenience entry points
/// (`string(_:format:)` / `attributed(_:format:)` / `iso8601String(for:includingFractionalSeconds:)`)
/// only when you want a one-shot `String`.
///
/// ## Availability
///
/// Everything except the `DateComponents` accessors is below Nebula's `.v26`
/// floor (the `FormatStyle` family is macOS 12 / iOS 15 / watchOS 8; URL and
/// Duration styles are macOS 13 / iOS 16 / watchOS 9 — all below floor). The
/// `DateComponents.formatted(_:)` family is **at-floor** (OS 26 / Nebula 26)
/// and is gated explicitly with `@available(iOS 26, macOS 26, tvOS 26,
/// watchOS 26, visionOS 26, *)`.
public struct NebulaStandards: Sendable {
    /// The locale applied to every accessor's `FormatStyle`.
    public let locale: Locale
    /// The time zone applied to date / ISO8601 / verbatim / measurement styles.
    public let timeZone: TimeZone
    /// The calendar applied to date / verbatim styles.
    public let calendar: Calendar

    /// Creates a standards configuration.
    ///
    /// All three components default to `.autoupdatingCurrent` so a
    /// `NebulaStandards()` tracks the user's settings; pin them with the
    /// `.with*` builders (or the `init`) for deterministic, locale-independent
    /// output (e.g. logs, persistence, snapshots).
    public init(
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.locale = locale
        self.timeZone = timeZone
        self.calendar = calendar
    }

    /// The default configuration (all components `.autoupdatingCurrent`).
    /// Idempotent via the once-token `static let` initializer side-effect (no
    /// lock primitive). Override pieces with the `.with*` builders.
    public static let `default` = NebulaStandards()

    // MARK: - Fluent builders

    /// Returns a copy with the locale replaced (other components unchanged).
    public func withLocale(_ locale: Locale) -> NebulaStandards {
        NebulaStandards(locale: locale, timeZone: timeZone, calendar: calendar)
    }

    /// Returns a copy with the time zone replaced (other components unchanged).
    public func withTimeZone(_ timeZone: TimeZone) -> NebulaStandards {
        NebulaStandards(locale: locale, timeZone: timeZone, calendar: calendar)
    }

    /// Returns a copy with the calendar replaced (other components unchanged).
    public func withCalendar(_ calendar: Calendar) -> NebulaStandards {
        NebulaStandards(locale: locale, timeZone: timeZone, calendar: calendar)
    }

    // MARK: - Date

    /// A `Date.FormatStyle` configured with this locale/timeZone/calendar.
    ///
    /// Constructed via the `init(date:time:locale:calendar:timeZone:)` rather
    /// than a `.dateTime.…` builder chain: `Date.FormatStyle` has `.locale(_:)`
    /// and `.timeZone(_:)` builders, but `.timeZone(_:)` takes a *display-format*
    /// enum (`Date.FormatStyle.Symbol.TimeZone`), not a `TimeZone` value, and
    /// there is no `.calendar(_:)` builder at all — so the init is the only way
    /// to bake in all three components. Mirrors `.dateTime` (`.abbreviated` date
    /// + `.standard` time).
    public var date: Date.FormatStyle {
        Date.FormatStyle(
            date: .abbreviated,
            time: .standard,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    /// An ISO 8601 date-time style configured with this timeZone/locale.
    ///
    /// Mirrors `NebulaDateFormat.iso8601(timeZone:)`'s verified logic: a `Z`
    /// suffix for GMT (`.omitted` separator) and a `±HH:MM` offset for any other
    /// zone (`.colon` separator) — the offset is the whole point of accepting a
    /// custom `timeZone`. `includingFractionalSeconds` is `false` here; use
    /// ``iso8601String(for:includingFractionalSeconds:)`` for sub-second
    /// precision. `.locale(locale)` is provided by the generic
    /// `extension FormatStyle { func locale(_:) -> Self }`.
    public var iso8601: Date.ISO8601FormatStyle {
        let separator: Date.ISO8601FormatStyle.TimeZoneSeparator =
            (timeZone == .gmt) ? .omitted : .colon
        return Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: separator,
            includingFractionalSeconds: false,
            timeZone: timeZone
        )
        .locale(locale)
    }

    /// A verbatim `Date.FormatStyle` from a symbol-interpolation `FormatString`,
    /// pinned to this locale/timeZone/calendar.
    ///
    /// `pattern` is a `Date.FormatString` built with **symbol interpolations**
    /// (e.g. `"\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)"`),
    /// NOT a printf/`strftime` pattern — `Date.VerbatimFormatStyle` does not
    /// parse `"yyyy-MM-dd"`. The `locale:` parameter is a `Locale?`; passing a
    /// non-optional `Locale` auto-promotes.
    public func date(verbatim pattern: Date.FormatString) -> Date.VerbatimFormatStyle {
        .verbatim(pattern, locale: locale, timeZone: timeZone, calendar: calendar)
    }

    // MARK: - Number

    /// A `Decimal.FormatStyle` configured with this locale.
    public var decimal: Decimal.FormatStyle {
        Decimal.FormatStyle().locale(locale)
    }

    /// An `IntegerFormatStyle<Value>` configured with this locale.
    public func integer<Value: BinaryInteger>() -> IntegerFormatStyle<Value> {
        IntegerFormatStyle<Value>().locale(locale)
    }

    /// A `FloatingPointFormatStyle<Value>` configured with this locale.
    public func double<Value: BinaryFloatingPoint>() -> FloatingPointFormatStyle<Value> {
        FloatingPointFormatStyle<Value>().locale(locale)
    }

    /// A percent style configured with this locale (direct init).
    public func percent<Value: BinaryFloatingPoint>() -> FloatingPointFormatStyle<Value>.Percent {
        FloatingPointFormatStyle<Value>.Percent(locale: locale)
    }

    /// A currency style for `code` configured with this locale (direct init).
    public func currency<Value: BinaryFloatingPoint>(code: String) -> FloatingPointFormatStyle<Value>.Currency {
        FloatingPointFormatStyle<Value>.Currency(code: code, locale: locale)
    }

    /// A `ByteCountFormatStyle` configured with this locale.
    public func byteCount(style: ByteCountFormatStyle.Style = .file) -> ByteCountFormatStyle {
        ByteCountFormatStyle(style: style).locale(locale)
    }

    // MARK: - List

    /// A `ListFormatStyle` configured with this locale.
    ///
    /// The Swift `.list(memberStyle:type:width:)` overload requires `type`
    /// (no default); this facade defaults it to `.and` (and `width` to
    /// `.standard`) so callers can write `list(memberStyle:)` for the common
    /// "1, 2 and 3" case. `.locale(locale)` is provided by the generic
    /// `FormatStyle` extension.
    public func list<MemberStyle: FormatStyle, Base: Sequence>(
        memberStyle: MemberStyle,
        type: ListFormatStyle<MemberStyle, Base>.ListType = .and,
        width: ListFormatStyle<MemberStyle, Base>.Width = .standard
    ) -> ListFormatStyle<MemberStyle, Base>
    where MemberStyle.FormatInput == Base.Element, MemberStyle.FormatOutput == String {
        .list(memberStyle: memberStyle, type: type, width: width).locale(locale)
    }

    // MARK: - Name

    /// A `PersonNameComponents.FormatStyle` configured with this locale
    /// (medium style, the default).
    public var name: PersonNameComponents.FormatStyle {
        PersonNameComponents.FormatStyle(locale: locale)
    }

    // MARK: - Measurement

    /// A `Measurement<U>.FormatStyle` configured with this locale.
    ///
    /// There is **no** `unit` parameter — the unit is implied by the
    /// `Measurement<U>` value being formatted. The init takes `width`, then
    /// `locale`, then `usage`, then `numberFormatStyle` (locale BEFORE usage);
    /// `locale` is supplied from this configuration.
    public func measurement<U: Dimension>(
        width: Measurement<U>.FormatStyle.UnitWidth = .abbreviated,
        usage: MeasurementFormatUnitUsage<U> = .general,
        numberFormatStyle: FloatingPointFormatStyle<Double>? = nil
    ) -> Measurement<U>.FormatStyle {
        Measurement<U>.FormatStyle(
            width: width,
            locale: locale,
            usage: usage,
            numberFormatStyle: numberFormatStyle
        )
    }

    // MARK: - Duration

    /// A `Duration.UnitsFormatStyle` over `allowed` units, configured with this
    /// locale.
    ///
    /// Uses the `.units(allowed:width:maximumUnitCount:)` shorthand (the unit
    /// type is `Duration.UnitsFormatStyle.Unit` — there is no top-level
    /// `Duration.Unit`). `.locale(locale)` is provided by the generic
    /// `FormatStyle` extension.
    public func durationUnits(
        allowed: Set<Duration.UnitsFormatStyle.Unit>,
        width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated,
        maximumUnitCount: Int? = nil
    ) -> Duration.UnitsFormatStyle {
        .units(allowed: allowed, width: width, maximumUnitCount: maximumUnitCount)
            .locale(locale)
    }

    /// A `Duration.TimeFormatStyle` for `pattern`, configured with this locale.
    public func durationTime(pattern: Duration.TimeFormatStyle.Pattern) -> Duration.TimeFormatStyle {
        .time(pattern: pattern).locale(locale)
    }

    // MARK: - URL

    /// A `URL.FormatStyle` configured with this locale.
    ///
    /// `URL.FormatStyle` has no locale in its `init` or component builders, but
    /// the generic `extension FormatStyle { func locale(_:) -> Self }` applies
    /// (URL.FormatStyle conforms to FormatStyle), so `.locale(locale)` is valid.
    public var url: URL.FormatStyle {
        URL.FormatStyle.url.locale(locale)
    }

    // MARK: - Convenience entry points

    /// Formats `value` with `format`, returning a `String`.
    ///
    /// Thin wrapper over `FormatStyle.format(_:)` (the protocol requirement);
    /// useful when you already hold a configured `FormatStyle` (e.g. from one of
    /// the typed accessors) and want a one-shot `String`. Uses
    /// `format.format(value)` rather than `value.formatted(format)` so it
    /// compiles for **any** `T` — there is no universal `formatted(_:)` on
    /// arbitrary values (only per-type extensions on `Date`/`Decimal`/`Int`/
    /// `BinaryFloatingPoint`/`Duration`/`URL`/`Measurement`/`DateComponents`/…),
    /// whereas `FormatStyle.format(_:)` is a protocol requirement available for
    /// every conformance.
    public func string<T>(_ value: T, format: some FormatStyle<T, String>) -> String {
        format.format(value)
    }

    /// Formats `value` with an `AttributedString`-producing `format`.
    ///
    /// See `string(_:format:)` for why this calls `format.format(value)`
    /// (the protocol requirement) rather than `value.formatted(format)`.
    public func attributed<T>(_ value: T, format: some FormatStyle<T, AttributedString>) -> AttributedString {
        format.format(value)
    }

    /// Formats `date` as an ISO 8601 string in this configuration's time zone.
    ///
    /// Mirrors ``iso8601`` but lets the caller opt into fractional seconds. For
    /// GMT the suffix is `Z`; for any other zone a `±HH:MM` offset is emitted.
    public func iso8601String(for date: Date, includingFractionalSeconds: Bool = false) -> String {
        let separator: Date.ISO8601FormatStyle.TimeZoneSeparator =
            (timeZone == .gmt) ? .omitted : .colon
        let style = Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: separator,
            includingFractionalSeconds: includingFractionalSeconds,
            timeZone: timeZone
        )
        .locale(locale)
        return date.formatted(style)
    }

    // MARK: - DateComponents (AT-FLOOR — OS 26 / Nebula 26)

    /// Formats `DateComponents` with `format`, returning a `String`.
    ///
    /// `DateComponents.formatted(_:)` is **at-floor** (OS 26 / Nebula 26,
    /// `Foundation.swiftinterface:2201`) — gated explicitly. Use any
    /// `FormatStyle<DateComponents, String>` (e.g.
    /// `DateComponents.ISO8601FormatStyle.iso8601`, also OS 26) as the format.
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public func string(_ components: DateComponents, format: some FormatStyle<DateComponents, String>) -> String {
        components.formatted(format)
    }

    /// Formats `DateComponents` with the canonical default style.
    ///
    /// `DateComponents` has **no** no-arg `formatted()` (unlike `Date`/`URL`);
    /// the only canonical default `FormatStyle` for the type at OS 26 is
    /// `DateComponents.ISO8601FormatStyle.iso8601` (also at-floor), so this
    /// accessor uses it. At-floor — gated explicitly.
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public func string(_ components: DateComponents) -> String {
        components.formatted(DateComponents.ISO8601FormatStyle.iso8601)
    }
}