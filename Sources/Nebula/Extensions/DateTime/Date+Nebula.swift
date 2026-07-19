//
//  Date+Nebula.swift
//  Nebula
//
//  Calendar-threaded `Date` arithmetic and predicate helpers + thin ISO 8601
//  conveniences over Foundation's modern `FormatStyle` family (no
//  `DateFormatter`/`ISO8601DateFormatter`). Every helper threads a `Calendar`
//  for locale/`firstWeekday`/DST correctness — Foundation's own pattern.
//  Stateles; `Date` derives `Sendable` automatically.
//  See vault/01-fundamentos/nebula-date-time-extensions.md.
//

import Foundation

extension Date {
    // MARK: - Boundaries

    /// The first instant of the day containing `self`, in `calendar`.
    ///
    /// DST-correct via `calendar.dateInterval(of:for:)` (never `start + 86_400`):
    ///
    /// ```swift
    /// Date.now.startOfDay()           // today, 00:00:00, in .current
    /// Date.now.startOfDay(in: gmt)    // 00:00:00 UTC
    /// ```
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }

    /// The last whole second of the day containing `self`, in `calendar`.
    ///
    /// Computed as `dateInterval(of: .day, for:).end - 1s` so it lands on
    /// `23:59:59` even on 23- or 25-hour DST days. For the exclusive
    /// start-of-next-day, use ``startOfDay(in:)`` on the next day instead.
    public func endOfDay(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .day, for: self) else {
            return self
        }
        return interval.end.addingTimeInterval(-1)
    }

    /// The first instant of the week containing `self`, in `calendar`.
    ///
    /// Respects `calendar.firstWeekday` (e.g. Sunday in `en_US`, Monday in `pt_BR`).
    public func startOfWeek(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: self) else {
            return self
        }
        return interval.start
    }

    /// The last whole second of the week containing `self`, in `calendar`.
    public func endOfWeek(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: self) else {
            return self
        }
        return interval.end.addingTimeInterval(-1)
    }

    /// The first instant of the month containing `self`, in `calendar`.
    public func startOfMonth(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: self) else {
            return self
        }
        return interval.start
    }

    /// The last whole second of the month containing `self`, in `calendar`.
    public func endOfMonth(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: self) else {
            return self
        }
        return interval.end.addingTimeInterval(-1)
    }

    /// The first instant of the year containing `self`, in `calendar`.
    public func startOfYear(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .year, for: self) else {
            return self
        }
        return interval.start
    }

    /// The last whole second of the year containing `self`, in `calendar`.
    public func endOfYear(in calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .year, for: self) else {
            return self
        }
        return interval.end.addingTimeInterval(-1)
    }

    // MARK: - Addition

    /// Returns `self` offset by `components`, computed in `calendar`.
    ///
    /// DST-aware via `calendar.date(byAdding:to:)`. Returns `self` unchanged if
    /// the offset is not representable.
    public func adding(_ components: DateComponents, in calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: components, to: self) ?? self
    }

    /// Returns `self` offset by `value` of `component`, computed in `calendar`.
    ///
    /// DST-aware via `calendar.date(byAdding:value:to:)`. Returns `self`
    /// unchanged if the offset is not representable.
    public func adding(
        _ value: Int,
        _ component: Calendar.Component,
        in calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: component, value: value, to: self) ?? self
    }

    /// `self` snapped to the nearest multiple of `interval` seconds.
    ///
    /// `interval` must be positive; otherwise `self` is returned unchanged.
    /// Half-multiples round away from zero (matches `Foundation` rounding).
    public func rounded(toNearest interval: TimeInterval) -> Date {
        guard interval > 0 else { return self }
        let reference = timeIntervalSinceReferenceDate
        let snapped = (reference / interval).rounded() * interval
        return Date(timeIntervalSinceReferenceDate: snapped)
    }

    // MARK: - Predicates

    /// `true` if `self` and `other` fall on the same calendar day in `calendar`.
    public func isInSameDay(as other: Date, in calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, inSameDayAs: other)
    }

    /// `true` if `self` and `other` fall in the same calendar month in `calendar`.
    public func isInSameMonth(as other: Date, in calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, equalTo: other, toGranularity: .month)
    }

    /// `true` if `self` is strictly later than `Date.now`.
    public var isInFuture: Bool { self > Date() }

    /// `true` if `self` is strictly earlier than `Date.now`.
    public var isInPast: Bool { self < Date() }

    /// `true` if `self` falls on today's calendar day in `calendar`.
    public func isInToday(in calendar: Calendar = .current) -> Bool {
        calendar.isDateInToday(self)
    }

    /// `true` if `self` falls on yesterday's calendar day in `calendar`.
    public func isInYesterday(in calendar: Calendar = .current) -> Bool {
        calendar.isDateInYesterday(self)
    }

    /// `true` if `self` falls on tomorrow's calendar day in `calendar`.
    public func isInTomorrow(in calendar: Calendar = .current) -> Bool {
        calendar.isDateInTomorrow(self)
    }

    /// `true` if `self` falls within the next `days` calendar days (today
    /// inclusive), in `calendar`.
    ///
    /// The window is `[startOfDay(now), startOfDay(now) + days days)`.
    /// `days` is clamped to be non-negative.
    public func isInNextDays(_ days: Int, in calendar: Calendar = .current) -> Bool {
        let span = max(days, 0)
        let now = Date()
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: span, to: start) else {
            return false
        }
        return self >= start && self < end
    }

    // MARK: - ISO 8601

    /// Formats `self` as an ISO 8601 string with time zone.
    ///
    /// Wraps ``NebulaDateFormat/iso8601WithFractionalSeconds`` when
    /// `includingFractionalSeconds` is true, else ``NebulaDateFormat/iso8601``.
    /// Pinned to GMT and `en_US_POSIX` for stable, locale-independent output
    /// suitable for logs and persistence.
    public func toISO8601(includingFractionalSeconds: Bool = false) -> String {
        let strategy: Date.ISO8601FormatStyle = includingFractionalSeconds
            ? NebulaDateFormat.iso8601WithFractionalSeconds
            : NebulaDateFormat.iso8601
        return formatted(strategy)
    }

    /// Parses an ISO 8601 string via Foundation's `ParseableFormatStyle`.
    ///
    /// Uses ``NebulaDateFormat/iso8601`` as the parse strategy (fractional
    /// seconds accepted when present in the strategy's tolerance). Returns
    /// `nil` for malformed input — never traps.
    public init?(iso8601 string: String) {
        guard let parsed = try? Date(string, strategy: NebulaDateFormat.iso8601) else {
            return nil
        }
        self = parsed
    }
}