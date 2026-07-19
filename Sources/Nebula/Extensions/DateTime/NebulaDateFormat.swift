//
//  NebulaDateFormat.swift
//  Nebula
//
//  Stateless `enum` namespace of pre-configured `Date` `FormatStyle` values —
//  the modern, `Sendable`, value-type replacement for `DateFormatter` /
//  `ISO8601DateFormatter` / `RelativeDateTimeFormatter` / `DateComponentsFormatter`.
//  Pinned ISO/stable presets to GMT + `en_US_POSIX` for locale-independent
//  output (logs/persistence); localized variants keep `autoupdatingCurrent`.
//  See vault/01-fundamentos/nebula-date-time-extensions.md.
//

import Foundation

/// Pre-configured `Date` `FormatStyle` constants and factories.
///
/// A stateless `enum` namespace — no instances. Each member returns a fresh
/// `Sendable` `FormatStyle` value; nothing is cached as mutable state. Feed
/// any preset to `Date.formatted(_:)`, or to `Date(_:strategy:)` for the
/// symmetric parse path (`ParseableFormatStyle`).
///
/// ISO/stable presets are pinned to `TimeZone.gmt` + `Locale(identifier:
/// "en_US_POSIX")` so output never drifts with user settings — use them for
/// logs and persistence. The `localized`-suffixed variants keep
/// `autoupdatingCurrent` for UI display.
public enum NebulaDateFormat {

    // MARK: - ISO 8601

    /// ISO 8601 date-time with time zone, GMT, `en_US_POSIX`, no fractional
    /// seconds. `ParseableFormatStyle` — also usable as a parse strategy via
    /// `Date(_:strategy:)`.
    public static var iso8601: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: .omitted,
            includingFractionalSeconds: false,
            timeZone: .gmt
        )
        .locale(Locale(identifier: "en_US_POSIX"))
    }

    /// ISO 8601 date-time with time zone AND fractional seconds, GMT,
    /// `en_US_POSIX`. Use when sub-second precision is required (e.g. log
    /// timestamps, monotonic event ordering).
    public static var iso8601WithFractionalSeconds: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: .omitted,
            includingFractionalSeconds: true,
            timeZone: .gmt
        )
        .locale(Locale(identifier: "en_US_POSIX"))
    }

    /// ISO 8601 date-time in `timeZone`, no fractional seconds, `en_US_POSIX`.
    ///
    /// Unlike the stdlib `Date.ISO8601FormatStyle.iso8601(timeZone:)` static
    /// (which uses `timeZoneSeparator: .omitted` and so silently drops the
    /// offset for any non-GMT zone), this preset emits a `Z` for GMT and a
    /// `±HH:MM` offset for any other zone — the offset is the whole point of
    /// accepting a custom `timeZone`. Verified against the Xcode 27 Beta 3
    /// `Foundation.swiftinterface` full init (line 8267): `.omitted` drops the
    /// offset, `.colon` emits it.
    public static func iso8601(timeZone: TimeZone = .gmt) -> Date.ISO8601FormatStyle {
        let separator: Date.ISO8601FormatStyle.TimeZoneSeparator = (timeZone == .gmt) ? .omitted : .colon
        return Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: separator,
            includingFractionalSeconds: false,
            timeZone: timeZone
        )
        .locale(Locale(identifier: "en_US_POSIX"))
    }

    /// ISO 8601 calendar date only (`yyyy-MM-dd`) in `timeZone`.
    public static func iso8601Date(timeZone: TimeZone = .gmt) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle.iso8601Date(timeZone: timeZone)
    }

    // MARK: - Localized date / time

    /// Short numeric date — day, month, year — in the current locale.
    public static var shortDate: Date.FormatStyle {
        .dateTime.day().month().year()
    }

    /// Medium date-time in the current locale (Foundation's default
    /// `.dateTime` preset).
    public static var mediumDateTime: Date.FormatStyle {
        .dateTime
    }

    /// Time only — hour and minute — in the current locale.
    public static var timeOnly: Date.FormatStyle {
        .dateTime.hour().minute()
    }

    // MARK: - Relative

    /// Relative style with named presentation and wide units
    /// ("yesterday", "2 days ago"). `RelativeFormatStyle` is NOT fluent — use
    /// this initializer-based preset, not a builder chain.
    public static var relativeNamed: Date.RelativeFormatStyle {
        Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
    }

    /// Relative style with numeric presentation and abbreviated units
    /// ("1d ago", "2h ago").
    public static var relativeNumeric: Date.RelativeFormatStyle {
        Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .abbreviated)
    }

    /// Anchor-relative style centered on `anchor` (iOS 18+ / macOS 15+ — below
    /// the Nebula `.v26` floor, no gate). Useful for "3 hours after launch"
    /// displays pinned to a known reference instant.
    public static func anchoredRelative(to anchor: Date) -> Date.AnchoredRelativeFormatStyle {
        Date.AnchoredRelativeFormatStyle(anchor: anchor)
    }

    // MARK: - Interval / components

    /// Interval format for a `Range<Date>` (Foundation default `.interval`).
    public static var interval: Date.IntervalFormatStyle {
        .interval
    }

    /// Components duration format for a `Range<Date>`
    /// (Foundation default `.timeDuration` — renders e.g. "1h 2m 3s").
    public static var timeDuration: Date.ComponentsFormatStyle {
        .timeDuration
    }

    /// Components format restricted to `fields`, abbreviated style.
    public static func components(
        fields: Set<Date.ComponentsFormatStyle.Field>
    ) -> Date.ComponentsFormatStyle {
        .components(style: .abbreviated, fields: fields)
    }

    // MARK: - Verbatim

    /// Verbatim format from a `Date.FormatString` symbol interpolation, pinned
    /// to `timeZone` (GMT) and a gregorian `calendar`.
    ///
    /// `format` is a `Date.FormatString` built with **symbol interpolations**
    /// (e.g. `"\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)"`),
    /// NOT a `DateFormatter`/`strftime` printf pattern — `Date.VerbatimFormatStyle`
    /// does not parse `"yyyy-MM-dd"` (passing that yields it back literally).
    /// `Calendar` has no `.gregorian` static — use `Calendar(identifier:
    /// .gregorian)`.
    public static func verbatim(
        _ format: Date.FormatString,
        timeZone: TimeZone = .gmt,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date.VerbatimFormatStyle {
        .verbatim(format, locale: nil, timeZone: timeZone, calendar: calendar)
    }
}