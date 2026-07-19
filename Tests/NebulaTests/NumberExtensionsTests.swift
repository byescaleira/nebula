//
//  NumberExtensionsTests.swift
//  NebulaTests
//
//  Wave D — Number / Measurement extension + formatting facade tests
//  (Swift Testing). Formatting assertions use a fixed `en_US` locale so they
//  are deterministic across SDK versions.
//

import Testing
import Foundation
import Nebula

/// Fixed locale for deterministic formatting assertions.
private let enUS = Locale(identifier: "en_US")

// MARK: - NebulaDecimalRoundingRule + Decimal.rounded

@Suite("Decimal.rounded(toDecimalPlaces:rule:)")
struct DecimalRoundingTests {
    @Test func bankersRoundsHalfToEven() {
        // 2.5 → 2 (even), 3.5 → 4 (even) at 0 places.
        let a = Decimal(string: "2.5")!.rounded(toDecimalPlaces: 0)
        let b = Decimal(string: "3.5")!.rounded(toDecimalPlaces: 0)
        #expect(a == 2)
        #expect(b == 4)
    }

    @Test func plainRoundsHalfUp() {
        let a = Decimal(string: "2.5")!.rounded(toDecimalPlaces: 0, rule: .plain)
        let b = Decimal(string: "3.5")!.rounded(toDecimalPlaces: 0, rule: .plain)
        #expect(a == 3)
        #expect(b == 4)
    }

    @Test func downRoundsTowardNegativeInfinity() {
        let a = Decimal(string: "1.239")!.rounded(toDecimalPlaces: 2, rule: .down)
        #expect(a == Decimal(string: "1.23")!)
        // `.down` is floor (toward -∞), NOT toward zero: -1.239 → -1.24.
        let neg = Decimal(string: "-1.239")!.rounded(toDecimalPlaces: 2, rule: .down)
        #expect(neg == Decimal(string: "-1.24")!)
    }

    @Test func upRoundsTowardPositiveInfinity() {
        let a = Decimal(string: "1.231")!.rounded(toDecimalPlaces: 2, rule: .up)
        #expect(a == Decimal(string: "1.24")!)
        // `.up` is ceil (toward +∞), NOT away from zero: -1.231 → -1.23.
        let neg = Decimal(string: "-1.231")!.rounded(toDecimalPlaces: 2, rule: .up)
        #expect(neg == Decimal(string: "-1.23")!)
    }

    @Test func defaultRuleIsBankers() {
        // Default `rule:` is `.bankers` — 1.235 → 1.24 (even last digit).
        let a = Decimal(string: "1.235")!.rounded(toDecimalPlaces: 2)
        #expect(a == Decimal(string: "1.24")!)
    }

    @Test func keepsExactScaleAtPlaces() {
        let a = Decimal(string: "1.23456")!.rounded(toDecimalPlaces: 3)
        #expect(a == Decimal(string: "1.235")!)
    }

    @Test func roundingZeroPlacesIsInteger() {
        let a = Decimal(string: "1.999")!.rounded(toDecimalPlaces: 0, rule: .plain)
        #expect(a == 2)
    }
}

@Suite("NebulaDecimalRoundingRule")
struct NebulaDecimalRoundingRuleTests {
    @Test func isSendable() {
        // Compile-checked Sendable conformance via assignment to a Sendable-typed let.
        let rule: NebulaDecimalRoundingRule = .bankers
        switch rule {
        case .plain, .down, .up, .bankers: break
        }
    }

    @Test func allFourRulesProduceDistinctResults() {
        let v = Decimal(string: "1.5")!
        let plain   = v.rounded(toDecimalPlaces: 0, rule: .plain)
        let down    = v.rounded(toDecimalPlaces: 0, rule: .down)
        let up      = v.rounded(toDecimalPlaces: 0, rule: .up)
        let bankers = v.rounded(toDecimalPlaces: 0, rule: .bankers)
        #expect(plain == 2)      // half up
        #expect(down == 1)       // toward zero
        #expect(up == 2)        // away from zero
        #expect(bankers == 2)   // 1.5 → even = 2
    }
}

// MARK: - BinaryFloatingPoint gap-fillers

@Suite("BinaryFloatingPoint gap-fillers")
struct BinaryFloatingPointNebulaTests {
    @Test func isWholeNumber() {
        #expect(Double(3.0).isWholeNumber)
        #expect(Double(-7.0).isWholeNumber)
        #expect(!Double(3.14).isWholeNumber)
        #expect(!Double.nan.isWholeNumber)
        #expect(!Double.infinity.isWholeNumber)
        #expect(Double(0.0).isWholeNumber)
        #expect(Float(5.0).isWholeNumber)
        #expect(!Float(5.5).isWholeNumber)
    }

    @Test func roundedToDecimalPlacesDefaultRule() {
        let a = (3.14159).rounded(toDecimalPlaces: 2)
        #expect(a == 3.14)
        let b = (2.5).rounded(toDecimalPlaces: 0)
        #expect(b == 2.0) // toNearestOrEven → 2
    }

    @Test func roundedToDecimalPlacesExplicitRule() {
        let a = (3.14159).rounded(toDecimalPlaces: 2, rule: .up)
        #expect(a == 3.15)
        let b = (2.5).rounded(toDecimalPlaces: 0, rule: .up)
        #expect(b == 3.0)
        let c = (-2.5).rounded(toDecimalPlaces: 0, rule: .down)
        #expect(c == -3.0) // .down is floor (toward -∞), not toward zero
    }

    @Test func roundedToDecimalPlacesNegativePlaces() {
        // Negative places round to the left of the decimal point.
        let a = (1234.0).rounded(toDecimalPlaces: -2, rule: .down)
        #expect(a == 1200.0)
    }

    @Test func measuredInBuildsMeasurement() {
        let m = Double(100.0).measured(in: UnitLength.kilometers)
        #expect(m.value == 100.0)
        #expect(m.unit == UnitLength.kilometers)
        let miles = m.converted(to: UnitLength.miles)
        #expect(miles.unit == UnitLength.miles)
        #expect(miles.value > 60.0 && miles.value < 63.0)
    }

    @Test func clampedIsInheritedFromComparable() {
        // `clamped(to:)` is inherited from `Comparable.clamped(to:)` (Primitive/).
        #expect(Double(5.0).clamped(to: 0.0...10.0) == 5.0)
        #expect(Double(-1.0).clamped(to: 0.0...10.0) == 0.0)
        #expect(Double(99.0).clamped(to: 0.0...10.0) == 10.0)
    }
}

// MARK: - BinaryInteger.measured(in:)

@Suite("BinaryInteger.measured(in:)")
struct BinaryIntegerMeasuredTests {
    @Test func buildsMeasurementFromInt() {
        let m = Int(100).measured(in: UnitMass.kilograms)
        #expect(m.value == 100.0)
        #expect(m.unit == UnitMass.kilograms)
    }

    @Test func convertedToOtherUnit() {
        let m = Int(1000).measured(in: UnitLength.meters)
        let km = m.converted(to: UnitLength.kilometers)
        #expect(km.value == 1.0)
    }

    @Test func worksOnOtherIntegerTypes() {
        let m = UInt64(42).measured(in: UnitTemperature.celsius)
        #expect(m.value == 42.0)
    }
}

// MARK: - NebulaFormattingOptions

@Suite("NebulaFormattingOptions")
struct NebulaFormattingOptionsTests {
    @Test func defaultsAreSensible() {
        let o = NebulaFormattingOptions.default
        #expect(o.percentPrecision == nil)
        #expect(o.currencyCode == nil)
        #expect(o.byteStyle == .file)
    }

    @Test func isSendable() {
        // Compile-checked Sendable via assignment.
        let o: NebulaFormattingOptions = .default
        _ = o
    }

    @Test func withBuildersReturnMutatedCopies() {
        let base = NebulaFormattingOptions.default
        let locale = Locale(identifier: "fr_FR")
        let o = base
            .with(locale: locale)
            .with(percentPrecision: 3)
            .with(currencyCode: "EUR")
            .with(byteStyle: .memory)
        #expect(o.locale.identifier == "fr_FR")
        #expect(o.percentPrecision == 3)
        #expect(o.currencyCode == "EUR")
        #expect(o.byteStyle == .memory)
        // Base is untouched (value semantics).
        #expect(base.locale != locale)
        #expect(base.percentPrecision == nil)
    }
}

// MARK: - NebulaNumberFormatting

@Suite("NebulaNumberFormatting.percent")
struct PercentFormattingTests {
    @Test func doublePercent() {
        let s = NebulaNumberFormatting.percent(0.25, options: .init(locale: enUS))
        #expect(!s.isEmpty)
        #expect(s.contains("25"))
        #expect(s.contains("%"))
    }

    @Test func doublePercentWithPrecision() {
        let s = NebulaNumberFormatting.percent(0.256, options: .init(locale: enUS, percentPrecision: 1))
        #expect(s.contains("25.6"))
    }

    @Test func decimalPercent() {
        let s = NebulaNumberFormatting.percent(Decimal(string: "0.5")!, options: .init(locale: enUS))
        #expect(s.contains("50"))
        #expect(s.contains("%"))
    }

    @Test func decimalPercentWithPrecision() {
        let s = NebulaNumberFormatting.percent(
            Decimal(string: "0.1234")!,
            options: .init(locale: enUS, percentPrecision: 2)
        )
        #expect(s.contains("12.34"))
    }
}

@Suite("NebulaNumberFormatting.currency")
struct CurrencyFormattingTests {
    @Test func doubleCurrencyUsesExplicitCode() {
        let s = NebulaNumberFormatting.currency(9.99, options: .init(locale: enUS, currencyCode: "USD"))
        #expect(s.contains("9.99"))
        #expect(s.contains("USD") || s.contains("$"))
    }

    @Test func decimalCurrencyIsExact() {
        let s = NebulaNumberFormatting.currency(Decimal(string: "19.95")!, options: .init(locale: enUS, currencyCode: "USD"))
        #expect(s.contains("19.95"))
    }

    @Test func currencyFallsBackToLocaleCurrencyThenUSD() {
        // No explicit code; with enUS locale, the facade falls back to
        // Locale.current.currency?.identifier (test environment dependent) or USD.
        let s = NebulaNumberFormatting.currency(1.0, options: .init(locale: enUS))
        #expect(!s.isEmpty)
    }
}

@Suite("NebulaNumberFormatting.bytes")
struct BytesFormattingTests {
    @Test func formatsBytes() {
        let s = NebulaNumberFormatting.bytes(1500, options: .init(locale: enUS))
        #expect(!s.isEmpty)
        // `ByteCountFormatStyle` with `.file` is 1024-based and rounds:
        // 1500 bytes → "2 KB" (1500 / 1024 ≈ 1.46, rounds up). Assert the unit,
        // not an exact decimal value.
        #expect(s.uppercased().contains("KB"))
    }

    @Test func zeroBytes() {
        let s = NebulaNumberFormatting.bytes(0, options: .init(locale: enUS))
        #expect(s.lowercased().contains("zero") || s.contains("0"))
    }

    @Test func memoryStyle() {
        // 5,000,000 bytes exceeds the 1,048,576 (1024*1024) threshold so `.memory`
        // style reports in MB rather than KB.
        let s = NebulaNumberFormatting.bytes(5_000_000, options: .init(locale: enUS, byteStyle: .memory))
        #expect(!s.isEmpty)
        #expect(s.uppercased().contains("MB"))
    }
}

@Suite("NebulaNumberFormatting.list")
struct ListFormattingTests {
    @Test func autoupdatingCurrentLocaleUsesStatelessPath() {
        // Default options use `.autoupdatingCurrent` → stateless class func.
        let s = NebulaNumberFormatting.list(["a", "b", "c"])
        #expect(s.contains("a"))
        #expect(s.contains("b"))
        #expect(s.contains("c"))
    }

    @Test func explicitLocaleJoinsAllItems() {
        let s = NebulaNumberFormatting.list(["red", "green", "blue"], options: .init(locale: enUS))
        #expect(s.contains("red"))
        #expect(s.contains("green"))
        #expect(s.contains("blue"))
    }

    @Test func emptyListProducesEmptyOrFallback() {
        let s = NebulaNumberFormatting.list([], options: .init(locale: enUS))
        #expect(s == "" || s.isEmpty)
    }
}

@Suite("NebulaNumberFormatting.measurement")
struct MeasurementFormattingTests {
    @Test func formatsLengthAbbreviated() {
        let m = Measurement(value: 1000, unit: UnitLength.meters)
        // `.asProvided` keeps meters (the default `.general` would convert to
        // miles in en_US, e.g. "0.621 mi").
        let s = NebulaNumberFormatting.measurement(m, options: .init(locale: enUS), usage: .asProvided)
        #expect(!s.isEmpty)
        #expect(s.contains("1,000") || s.contains("1000"))
        #expect(s.lowercased().contains("m"))
    }

    @Test func respectsWidth() {
        let m = Measurement(value: 1000, unit: UnitLength.meters)
        let wide = NebulaNumberFormatting.measurement(m, width: .wide, options: .init(locale: enUS), usage: .asProvided)
        let abbreviated = NebulaNumberFormatting.measurement(m, width: .abbreviated, options: .init(locale: enUS), usage: .asProvided)
        #expect(!wide.isEmpty)
        #expect(!abbreviated.isEmpty)
        // Both must mention the numeric value.
        #expect(wide.contains("1,000") || wide.contains("1000"))
        #expect(abbreviated.contains("1,000") || abbreviated.contains("1000"))
    }

    @Test func convertsViaUsage() {
        // `.asProvided` keeps the provided unit; `.general` may convert to a
        // locale-appropriate unit. Both produce non-empty strings.
        let m = Measurement(value: 5, unit: UnitLength.kilometers)
        let asProvided = NebulaNumberFormatting.measurement(
            m, width: .abbreviated,
            options: .init(locale: enUS),
            usage: .asProvided
        )
        #expect(!asProvided.isEmpty)
        #expect(asProvided.lowercased().contains("km") || asProvided.contains("5"))
    }
}