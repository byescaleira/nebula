//
//  StandardizeTests.swift
//  NebulaTests
//
//  Wave F — STANDARDIZE half: NebulaStandards formatting facade tests
//  (Swift Testing). Covers the four-contract shape (Sendable struct + .with*
//  builders + static .default, minus the handler), every typed FormatStyle
//  accessor, deterministic pinned output, the at-floor DateComponents accessors,
//  and the process-wide Mutex accessor.
//

import Testing
import Foundation
import Nebula

// A fixed, deterministic locale/timezone/calendar so output assertions do not
// depend on the host. en_US + GMT + gregorian yields stable, well-known
// strings (e.g. "1,234", "Jul 18, 2026…", "2026-07-18T13:30:45Z").
private let enUS = Locale(identifier: "en_US")
private let gmt = TimeZone.gmt
private let gregorianGMT: Calendar = {
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
    return gregorianGMT.date(from: comps)!
}()

// A pinned standards instance used by deterministic-output tests.
private let pinned = NebulaStandards(locale: enUS, timeZone: gmt, calendar: gregorianGMT)

@Suite("NebulaStandards")
struct NebulaStandardsTests {
    // MARK: - Defaults + builders

    @Test func defaultHoldsAutoupdatingCurrentComponents() {
        let s = NebulaStandards.default
        // The init defaults are exactly the `.autoupdatingCurrent` singletons,
        // which track the user's settings at use time.
        #expect(s.locale == Locale.autoupdatingCurrent)
        #expect(s.timeZone == TimeZone.autoupdatingCurrent)
        #expect(s.calendar == Calendar.autoupdatingCurrent)
    }

    @Test func withLocaleReplacesOnlyLocale() {
        let s = NebulaStandards.default
        let l = Locale(identifier: "fr_FR")
        let s2 = s.withLocale(l)
        #expect(s2.locale == l)
        #expect(s2.timeZone == s.timeZone)
        #expect(s2.calendar == s.calendar)
        // Original is unchanged (value semantics).
        #expect(s.locale != l)
    }

    @Test func withTimeZoneReplacesOnlyTimeZone() {
        let s = NebulaStandards.default
        let tz = TimeZone(secondsFromGMT: -3 * 3600)! // -03:00
        let s2 = s.withTimeZone(tz)
        #expect(s2.timeZone == tz)
        #expect(s2.locale == s.locale)
        #expect(s2.calendar == s.calendar)
    }

    @Test func withCalendarReplacesOnlyCalendar() {
        let s = NebulaStandards.default
        let c = Calendar(identifier: .buddhist)
        let s2 = s.withCalendar(c)
        #expect(s2.calendar == c)
        #expect(s2.locale == s.locale)
        #expect(s2.timeZone == s.timeZone)
    }

    @Test func initOverridesAllThree() {
        let s = NebulaStandards(locale: enUS, timeZone: gmt, calendar: gregorianGMT)
        #expect(s.locale == enUS)
        #expect(s.timeZone == gmt)
        #expect(s.calendar == gregorianGMT)
    }

    // MARK: - Sendable (derived)

    @Test func derivedSendableCompiles() {
        // Proves derived `Sendable` conformance: passing to a `T: Sendable`
        // generic requires the conformance the struct declares.
        func consume<T: Sendable>(_ value: T) { _ = value }
        consume(NebulaStandards.default)
        consume(NebulaStandards.default.withLocale(.current))
        consume(NebulaStandards.default.withTimeZone(.current).withCalendar(.current))
        #expect(true)
    }

    // MARK: - Date accessors

    @Test func dateAccessorProducesNonEmptyString() {
        let s = refDate.formatted(pinned.date)
        #expect(!s.isEmpty)
        // En_US + GMT + gregorian: the abbreviated month name "Jul" appears.
        #expect(s.contains("Jul"))
        #expect(s.contains("2026"))
    }

    @Test func iso8601StringProducesGMTZSuffix() {
        // GMT → Z suffix, no offset.
        let s = pinned.iso8601String(for: refDate)
        #expect(s == "2026-07-18T13:30:45Z")
    }

    @Test func iso8601StringWithFractionalSecondsParsesBack() {
        let s = pinned.iso8601String(for: refDate, includingFractionalSeconds: true)
        // refDate has zero fractional seconds; the style may omit fractional
        // digits for an exact-second value, but it must still round-trip.
        let parsed = Date(iso8601: s)
        #expect(parsed != nil)
        #expect(parsed == refDate)
    }

    @Test func iso8601AccessorNonGMTEmitsOffset() {
        let tz = TimeZone(secondsFromGMT: -3 * 3600)! // -03:00
        let s = pinned.withTimeZone(tz).iso8601String(for: refDate)
        #expect(s.contains("-03:00"))
    }

    @Test func iso8601PropertyFormatsDate() {
        let s = refDate.formatted(pinned.iso8601)
        #expect(s == "2026-07-18T13:30:45Z")
    }

    @Test func dateVerbatimUsesSymbolInterpolation() {
        // Verbatim uses a symbol-interpolation DSL, not a printf pattern:
        // passing a strftime-style "yyyy-MM-dd HH:mm:ss" would be emitted
        // literally. Exact output is asserted in the deterministic section.
        let style = pinned.date(verbatim: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)")
        let s = refDate.formatted(style)
        #expect(s == "2026-07-18")
    }

    // MARK: - Number accessors

    @Test func decimalProducesNonEmptyString() {
        let s = Decimal(1234.5).formatted(pinned.decimal)
        #expect(!s.isEmpty)
        // en_US uses '.' as the decimal separator and ',' as the grouping
        // separator (grouping may or may not appear depending on default
        // grouping rules for this magnitude — assert the digits).
        #expect(s.contains("1"))
        #expect(s.contains("234"))
    }

    @Test func integerProducesDeterministicString() {
        let s = 1234567.formatted(pinned.integer())
        #expect(!s.isEmpty)
        // en_US thousands grouping uses ','.
        #expect(s.contains("1,234,567"))
    }

    @Test func doubleProducesNonEmptyString() {
        let s = 3.14159.formatted(pinned.double())
        #expect(!s.isEmpty)
        #expect(s.contains("3"))
    }

    @Test func percentProducesNonEmptyString() {
        let s = (0.42).formatted(pinned.percent())
        #expect(!s.isEmpty)
        #expect(s.contains("42"))
    }

    @Test func currencyProducesNonEmptyString() {
        let s = (0.42).formatted(pinned.currency(code: "USD"))
        #expect(!s.isEmpty)
        // en_US + USD renders the dollar sign; the magnitude 0.42 stays.
        #expect(s.contains("$") || s.contains("USD") || s.contains("0.42"))
    }

    @Test func byteCountProducesDeterministicString() {
        let s = 1234567.formatted(pinned.byteCount(style: .file))
        #expect(!s.isEmpty)
        // en_US file-style: "1.23 MB" (abbreviated). Assert the MB unit, which
        // is stable across en_US* locales; the leading digits vary with
        // rounding conventions but "MB" does not.
        #expect(s.contains("MB"))
    }

    // MARK: - List

    @Test func listProducesNonEmptyString() {
        // `Base` cannot be inferred from `memberStyle`/`type` alone (it is a free
        // generic parameter constrained only by `MemberStyle.FormatInput ==
        // Base.Element`), so annotate it at the call site.
        let style: ListFormatStyle<IntegerFormatStyle<Int>, [Int]> =
            pinned.list(memberStyle: IntegerFormatStyle<Int>(), type: .and)
        let s = [1, 2, 3].formatted(style)
        #expect(!s.isEmpty)
        #expect(s.contains("1"))
        #expect(s.contains("3"))
    }

    // MARK: - Measurement

    @Test func measurementProducesNonEmptyString() {
        let m = Measurement(value: 42.0, unit: UnitLength.kilometers)
        let s = m.formatted(pinned.measurement(usage: .asProvided))
        #expect(!s.isEmpty)
        #expect(s.contains("42"))
    }

    // MARK: - Duration

    @Test func durationUnitsProducesNonEmptyString() {
        let d: Duration = .seconds(75)
        let s = d.formatted(pinned.durationUnits(allowed: [.minutes, .seconds]))
        #expect(!s.isEmpty)
    }

    @Test func durationTimeProducesNonEmptyString() {
        let d: Duration = .seconds(75)
        let s = d.formatted(pinned.durationTime(pattern: .minuteSecond))
        #expect(!s.isEmpty)
    }

    // MARK: - URL

    @Test func urlProducesNonEmptyString() {
        let u = URL(string: "https://example.com/path?query=1#frag")!
        let s = u.formatted(pinned.url)
        #expect(!s.isEmpty)
        #expect(s.contains("example.com"))
    }

    // MARK: - Convenience entry points

    @Test func stringFormatEntryAppliesStyle() {
        let s = pinned.string(1234567, format: pinned.integer())
        #expect(s.contains("1,234,567"))
    }

    @Test func attributedEntryReturnsAttributedString() {
        // `IntegerFormatStyle<Value>.attributed` is a non-deprecated
        // `FormatStyle<Value, AttributedString>` (unlike `Date.FormatStyle.attributed`,
        // which is deprecated in favor of `Date.FormatStyle.Attributed`).
        let a = pinned.attributed(1234567, format: pinned.integer().attributed)
        #expect(a.characters.isEmpty == false)
    }

    // MARK: - Deterministic pinned output (proves locale/timeZone applied)
    //
    // Three exact assertions on locale/timeZone-sensitive accessors. The
    // `date` accessor (`.abbreviated` + `.standard`) is intentionally NOT
    // asserted exactly — its `.standard` time includes seconds and the en_US
    // date+time joining punctuation can drift across SDK revisions; the verbatim
    // accessor below is the deterministic date witness instead.

    @Test func pinnedIntegerIsDeterministic() {
        let s = 1234567.formatted(pinned.integer())
        #expect(s == "1,234,567")
    }

    @Test func pinnedISO8601IsDeterministic() {
        let s = pinned.iso8601String(for: refDate)
        #expect(s == "2026-07-18T13:30:45Z")
    }

    @Test func pinnedDateVerbatimIsDeterministic() {
        let style = pinned.date(verbatim: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)")
        let s = refDate.formatted(style)
        #expect(s == "2026-07-18 13:30:45")
    }

    // MARK: - DateComponents (AT-FLOOR — OS 26 / Nebula 26)

    @Test func dateComponentsFormattedWithISO8601NonEmpty() {
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 7
            comps.day = 18
            comps.hour = 13
            comps.minute = 30
            comps.second = 45
            comps.timeZone = gmt
            let s = pinned.string(comps, format: DateComponents.ISO8601FormatStyle.iso8601)
            #expect(!s.isEmpty)
        }
    }

    @Test func dateComponentsDefaultAccessorNonEmpty() {
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 7
            comps.day = 18
            comps.hour = 13
            comps.minute = 30
            comps.second = 45
            comps.timeZone = gmt
            let s = pinned.string(comps)
            #expect(!s.isEmpty)
        }
    }
}

@Suite("NebulaStandardsConfig", .serialized)
struct NebulaStandardsConfigTests {
    // Serialized: these tests mutate process-wide state (`NebulaStandardsConfig`
    // is a `Mutex<NebulaStandards>` global), so concurrent runs would race even
    // with the `defer` restore. Each test still restores via `defer`.
    @Test func getReturnsDefaultByDefault() {
        // Restore in a defer so a prior test failure cannot pollute the
        // process-wide state for the rest of the run.
        let saved = NebulaStandardsConfig.get()
        defer { NebulaStandardsConfig.set(saved) }

        NebulaStandardsConfig.set(.default)
        let got = NebulaStandardsConfig.get()
        #expect(got.locale == NebulaStandards.default.locale)
        #expect(got.timeZone == NebulaStandards.default.timeZone)
        #expect(got.calendar == NebulaStandards.default.calendar)
    }

    @Test func setThenGetReturnsCustomConfig() {
        let saved = NebulaStandardsConfig.get()
        defer { NebulaStandardsConfig.set(saved) }

        let custom = NebulaStandards(locale: enUS, timeZone: gmt, calendar: gregorianGMT)
        NebulaStandardsConfig.set(custom)
        let got = NebulaStandardsConfig.get()
        #expect(got.locale == enUS)
        #expect(got.timeZone == gmt)
        #expect(got.calendar == gregorianGMT)
    }

    @Test func setRestoresDefaultAfterMutation() {
        let saved = NebulaStandardsConfig.get()
        NebulaStandardsConfig.set(NebulaStandards(locale: Locale(identifier: "de_DE")))
        NebulaStandardsConfig.set(saved)
        let got = NebulaStandardsConfig.get()
        #expect(got.locale == saved.locale)
    }
}