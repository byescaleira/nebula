//
//  NebulaDurationFormat.swift
//  Nebula
//
//  Stateless `enum` namespace of pre-configured `Swift.Duration` `FormatStyle`
//  values — the modern, `Sendable` replacement for `DateComponentsFormatter`'s
//  duration rendering. Two families: `Duration.TimeFormatStyle` (fixed
//  `HH:mm:ss`-style patterns) and `Duration.UnitsFormatStyle` (localized
//  unit strings).
//  See vault/01-fundamentos/nebula-date-time-extensions.md.
//

import Foundation

/// Pre-configured `Swift.Duration` `FormatStyle` constants and factories.
///
/// A stateless `enum` namespace. Use the `TimeFormatStyle` presets
/// (`clockTimer`, `minuteSecond`) for fixed-width timer displays (e.g.
/// `"3:02:03"`) and the `UnitsFormatStyle` presets (`humanUnits`, `units`)
/// for localized, human-readable unit strings (e.g. `"1h 2m 3s"`).
public enum NebulaDurationFormat {

    /// Clock-timer pattern `H:MM:SS` (e.g. `"3:02:03"`), pinned to
    /// `en_US_POSIX` for locale-independent, deterministic output — a
    /// stopwatch / countdown should look the same everywhere.
    ///
    /// - Note: `Duration.TimeFormatStyle` pads the trailing fields but NOT the
    ///   leading field, so `"3:02:03"` (not `"03:02:03"`). This is the stdlib's
    ///   behavior; there is no zero-pad option on the style.
    public static var clockTimer: Duration.TimeFormatStyle {
        .time(pattern: .hourMinuteSecond).locale(Locale(identifier: "en_US_POSIX"))
    }

    /// Minutes-seconds pattern `M:SS` (e.g. `"2:03"`), pinned to `en_US_POSIX`.
    /// See ``clockTimer`` for the leading-field padding note.
    public static var minuteSecond: Duration.TimeFormatStyle {
        .time(pattern: .minuteSecond).locale(Locale(identifier: "en_US_POSIX"))
    }

    /// Localized abbreviated units over hours, minutes, seconds (e.g.
    /// `"1h 2m 3s"`).
    public static var humanUnits: Duration.UnitsFormatStyle {
        .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)
    }

    /// Localized units over `allowed`, at `width`.
    public static func units(
        allowed: Set<Duration.UnitsFormatStyle.Unit>,
        width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated
    ) -> Duration.UnitsFormatStyle {
        .units(allowed: allowed, width: width)
    }
}