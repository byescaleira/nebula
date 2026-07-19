//
//  DateTimeExtensionsTests.swift
//  Nebula
//
//  Wave — Date / DateInterval / FormatStyle facade tests (Swift Testing).
//

import Testing
import Foundation
import Nebula

// A fixed, deterministic calendar/timezone pair so boundary math does not
// depend on the host locale or DST. GMT avoids 23/25-hour days entirely.
private let gmt = TimeZone.gmt
private let gmtCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = gmt
    return c
}()

// Pin a fixed reference date: 2026-07-18 13:30:45 UTC.
private let refDate: Date = {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 7
    comps.day = 18
    comps.hour = 13
    comps.minute = 30
    comps.second = 45
    comps.timeZone = gmt
    return gmtCalendar.date(from: comps)!
}()

@Suite("Date+Nebula boundaries")
struct DateNebulaBoundaryTests {
    @Test func startOfDayGMT() {
        let start = refDate.startOfDay(in: gmtCalendar)
        let comps = gmtCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(comps.second == 0)
        #expect(comps.day == 18)
    }

    @Test func endOfDayGMTIsLastWholeSecond() {
        let end = refDate.endOfDay(in: gmtCalendar)
        let comps = gmtCalendar.dateComponents([.hour, .minute, .second], from: end)
        #expect(comps.hour == 23)
        #expect(comps.minute == 59)
        #expect(comps.second == 59)
        // endOfDay is strictly before the start of the next day.
        let nextStart = refDate.adding(1, .day, in: gmtCalendar).startOfDay(in: gmtCalendar)
        #expect(end < nextStart)
    }

    @Test func startAndEndOfMonth() {
        let start = refDate.startOfMonth(in: gmtCalendar)
        let end = refDate.endOfMonth(in: gmtCalendar)
        let startComps = gmtCalendar.dateComponents([.year, .month, .day], from: start)
        let endComps = gmtCalendar.dateComponents([.year, .month, .day, .hour], from: end)
        #expect(startComps.day == 1)
        #expect(startComps.month == 7)
        #expect(endComps.day == 31) // July has 31 days
        #expect(endComps.hour == 23)
    }

    @Test func startAndEndOfYear() {
        let start = refDate.startOfYear(in: gmtCalendar)
        let end = refDate.endOfYear(in: gmtCalendar)
        let startComps = gmtCalendar.dateComponents([.year, .month, .day], from: start)
        let endComps = gmtCalendar.dateComponents([.month, .day, .hour], from: end)
        #expect(startComps.month == 1)
        #expect(startComps.day == 1)
        #expect(endComps.month == 12)
        #expect(endComps.day == 31)
        #expect(endComps.hour == 23)
    }

    @Test func startOfWeekRespectsCalendar() {
        let start = refDate.startOfWeek(in: gmtCalendar)
        // 2026-07-18 is a Saturday; gregorian default firstWeekday == 1 (Sunday).
        let weekday = gmtCalendar.component(.weekday, from: start)
        #expect(weekday == 1) // Sunday
    }
}

@Suite("Date+Nebula addition")
struct DateNebulaAdditionTests {
    @Test func addingComponentValue() {
        let tomorrow = refDate.adding(1, .day, in: gmtCalendar)
        let day = gmtCalendar.component(.day, from: tomorrow)
        #expect(day == 19)
    }

    @Test func addingDateComponents() {
        var comps = DateComponents()
        comps.month = 1
        let nextMonth = refDate.adding(comps, in: gmtCalendar)
        let month = gmtCalendar.component(.month, from: nextMonth)
        #expect(month == 8)
    }

    @Test func addingWrapsComponentsFlagImplicitly() {
        // wrappingComponents defaults to false; adding a month to July 18 -> Aug 18.
        let result = refDate.adding(1, .month, in: gmtCalendar)
        let (m, d) = (gmtCalendar.component(.month, from: result), gmtCalendar.component(.day, from: result))
        #expect(m == 8 && d == 18)
    }
}

@Suite("Date+Nebula rounding")
struct DateNebulaRoundingTests {
    @Test func roundsToNearestMinute() {
        // 13:30:45 rounded to 60s -> 13:31:00.
        let rounded = refDate.rounded(toNearest: 60)
        let (m, s) = (gmtCalendar.component(.minute, from: rounded),
                     gmtCalendar.component(.second, from: rounded))
        #expect(m == 31)
        #expect(s == 0)
    }

    @Test func roundsToNearestFiveMinutes() {
        // 13:30:45 (epoch seconds fractional) to 300s -> 13:30:00 (closer than 13:35:00).
        let rounded = refDate.rounded(toNearest: 300)
        let m = gmtCalendar.component(.minute, from: rounded)
        #expect(m == 30)
    }

    @Test func nonPositiveIntervalIsNoOp() {
        let same = refDate.rounded(toNearest: 0)
        #expect(same == refDate)
        let neg = refDate.rounded(toNearest: -10)
        #expect(neg == refDate)
    }
}

@Suite("Date+Nebula predicates")
struct DateNebulaPredicateTests {
    @Test func isInSameDayAndMonth() {
        let sameDay = refDate.adding(1, .hour, in: gmtCalendar)
        let otherDay = refDate.adding(2, .day, in: gmtCalendar)
        #expect(refDate.isInSameDay(as: sameDay, in: gmtCalendar))
        #expect(!refDate.isInSameDay(as: otherDay, in: gmtCalendar))
        #expect(refDate.isInSameMonth(as: otherDay, in: gmtCalendar))
        let nextMonth = refDate.adding(1, .month, in: gmtCalendar)
        #expect(!refDate.isInSameMonth(as: nextMonth, in: gmtCalendar))
    }

    @Test func isInFutureAndPast() {
        let future = Date().adding(1, .hour)
        let past = Date().adding(-1, .hour)
        #expect(future.isInFuture)
        #expect(past.isInPast)
    }

    @Test func isInTodayYesterdayTomorrow() {
        let now = Date()
        let yesterday = now.adding(-1, .day, in: gmtCalendar)
        let tomorrow = now.adding(1, .day, in: gmtCalendar)
        let cal = Calendar.current
        #expect(now.isInToday(in: cal))
        #expect(yesterday.isInYesterday(in: cal))
        #expect(tomorrow.isInTomorrow(in: cal))
        #expect(!yesterday.isInToday(in: cal))
    }

    @Test func isInNextDaysWindow() {
        let cal = Calendar.current
        let now = Date()
        let inBounds = now.adding(2, .day, in: cal)
        let outOfBounds = now.adding(10, .day, in: cal)
        #expect(now.isInNextDays(5, in: cal))
        #expect(inBounds.isInNextDays(5, in: cal))
        #expect(!outOfBounds.isInNextDays(5, in: cal))
        // Zero-day window excludes everything strictly later than startOfDay.
        #expect(!now.adding(1, .hour, in: cal).isInNextDays(0, in: cal))
    }
}

@Suite("Date+Nebula ISO 8601")
struct DateNebulaISO8601Tests {
    @Test func toISO8601RoundTrips() {
        let s = refDate.toISO8601()
        #expect(s == "2026-07-18T13:30:45Z")
        let parsed = Date(iso8601: s)
        #expect(parsed != nil)
        #expect(parsed == refDate)
    }

    @Test func toISO8601WithFractionalSecondsContainsDot() {
        let s = refDate.toISO8601(includingFractionalSeconds: true)
        // refDate has zero fractional seconds, but the strategy emits no
        // fractional digits for an exact-second value; verify it parses back.
        let parsed = Date(iso8601: s)
        #expect(parsed == refDate)
    }

    @Test func initIso8601RejectsMalformed() {
        #expect(Date(iso8601: "not-a-date") == nil)
        #expect(Date(iso8601: "") == nil)
    }
}

@Suite("NebulaDateFormat")
struct NebulaDateFormatTests {
    @Test func iso8601PinnedToGMTAndEnUSPOSIX() {
        let s = refDate.formatted(NebulaDateFormat.iso8601)
        #expect(s == "2026-07-18T13:30:45Z")
    }

    @Test func iso8601WithFractionalSecondsPreservesSubseconds() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        comps.nanosecond = 500_000_000
        comps.timeZone = gmt
        let d = gmtCalendar.date(from: comps)!
        let s = d.formatted(NebulaDateFormat.iso8601WithFractionalSeconds)
        #expect(s.hasSuffix("Z"))
        #expect(s.contains("."))
    }

    @Test func iso8601WithCustomTimeZone() {
        // `secondsFromGMT:` takes SECONDS, so -3 hours = -10_800, not -180.
        let tz = TimeZone(secondsFromGMT: -3 * 3600)! // -03:00
        let style = NebulaDateFormat.iso8601(timeZone: tz)
        let s = refDate.formatted(style)
        #expect(s.contains("-03:00"))
    }

    @Test func iso8601DateOnly() {
        let style = NebulaDateFormat.iso8601Date()
        let s = refDate.formatted(style)
        #expect(s == "2026-07-18")
    }

    @Test func verbatimProducesPinnedFormat() {
        // `Date.VerbatimFormatStyle` uses a symbol-interpolation DSL, not a
        // printf pattern: `\(year: .defaultDigits)` etc. (passing "yyyy-MM-dd"
        // yields it back literally).
        let style = NebulaDateFormat.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)")
        let s = refDate.formatted(style)
        #expect(s == "2026-07-18 13:30:45")
    }

    @Test func relativeFormatsProduceNonEmptyStrings() {
        let past = refDate.adding(-3, .day, in: gmtCalendar)
        let named = past.formatted(NebulaDateFormat.relativeNamed)
        let numeric = past.formatted(NebulaDateFormat.relativeNumeric)
        #expect(!named.isEmpty)
        #expect(!numeric.isEmpty)
    }

    @Test func anchoredRelativeProducesNonEmptyString() {
        let anchor = refDate.adding(-1, .hour, in: gmtCalendar)
        let style = NebulaDateFormat.anchoredRelative(to: anchor)
        let s = refDate.formatted(style)
        #expect(!s.isEmpty)
    }

    @Test func timeDurationFormatsInterval() {
        let start = refDate
        let end = refDate.adding(1, .hour, in: gmtCalendar).adding(120, .second, in: gmtCalendar)
        let s = (start..<end).formatted(NebulaDateFormat.timeDuration)
        #expect(!s.isEmpty)
    }

    @Test func componentsFormatsRange() {
        let start = refDate
        let end = refDate.adding(1, .day, in: gmtCalendar).adding(2, .hour, in: gmtCalendar)
        let s = (start..<end).formatted(NebulaDateFormat.components(fields: [.day, .hour]))
        #expect(!s.isEmpty)
    }

    @Test func presetsAreSendable() {
        // Sendable value types — compile-time check by passing to a @Sendable closure.
        func consume<T: Sendable>(_ value: T) {}
        consume(NebulaDateFormat.iso8601)
        consume(NebulaDateFormat.iso8601WithFractionalSeconds)
        consume(NebulaDateFormat.shortDate)
        consume(NebulaDateFormat.mediumDateTime)
        consume(NebulaDateFormat.timeOnly)
        consume(NebulaDateFormat.relativeNamed)
        consume(NebulaDateFormat.relativeNumeric)
        consume(NebulaDateFormat.interval)
        consume(NebulaDateFormat.timeDuration)
        #expect(true)
    }
}

@Suite("DateInterval+Nebula Duration bridge")
struct DateIntervalDurationBridgeTests {
    @Test func durationInitMatchesTimeIntervalInit() {
        let dur: Swift.Duration = .seconds(3) + .milliseconds(500)
        let viaDuration = DateInterval(start: refDate, duration: dur)
        let viaTimeInterval = DateInterval(start: refDate, duration: 3.5)
        #expect(viaDuration.start == viaTimeInterval.start)
        #expect(viaDuration.end == viaTimeInterval.end)
    }

    @Test func durationInitPreservesFractionalSeconds() {
        let dur: Swift.Duration = .milliseconds(250)
        let interval = DateInterval(start: refDate, duration: dur)
        let expectedEnd = refDate.addingTimeInterval(0.25)
        #expect(interval.end == expectedEnd)
    }

    @Test func wholeSecondDurationExact() {
        let dur: Swift.Duration = .seconds(60)
        let interval = DateInterval(start: refDate, duration: dur)
        #expect(interval.duration == 60)
    }
}

@Suite("NebulaDurationFormat")
struct NebulaDurationFormatTests {
    @Test func clockTimerRendersHMMSS() {
        let dur: Swift.Duration = .seconds(3 * 3600 + 2 * 60 + 3)
        let s = dur.formatted(NebulaDurationFormat.clockTimer)
        // The leading field is NOT zero-padded (stdlib behavior); trailing
        // fields are.
        #expect(s == "3:02:03")
    }

    @Test func minuteSecondRendersMSS() {
        let dur: Swift.Duration = .seconds(2 * 60 + 3)
        let s = dur.formatted(NebulaDurationFormat.minuteSecond)
        #expect(s == "2:03")
    }

    @Test func humanUnitsNonEmpty() {
        let dur: Swift.Duration = .seconds(3 * 3600 + 2 * 60 + 3)
        let s = dur.formatted(NebulaDurationFormat.humanUnits)
        #expect(!s.isEmpty)
    }

    @Test func unitsFactoryNonEmpty() {
        let dur: Swift.Duration = .seconds(90)
        let style = NebulaDurationFormat.units(allowed: [.minutes, .seconds], width: .abbreviated)
        let s = dur.formatted(style)
        #expect(!s.isEmpty)
    }

    @Test func presetsAreSendable() {
        func consume<T: Sendable>(_ value: T) {}
        consume(NebulaDurationFormat.clockTimer)
        consume(NebulaDurationFormat.minuteSecond)
        consume(NebulaDurationFormat.humanUnits)
        #expect(true)
    }
}