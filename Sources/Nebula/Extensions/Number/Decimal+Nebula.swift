//
//  Decimal+Nebula.swift
//  Nebula
//
//  `Decimal` gap-fillers. `Decimal` is its own value type — it does NOT conform
//  to `FloatingPoint` (the interface marks the FloatingPoint static members
//  `@available(*, unavailable, "Decimal does not yet fully adopt FloatingPoint.")`,
//  lines 7075/7079/7150), so it must NOT be routed through
//  `FloatingPointFormatStyle`. Rounding uses `NSDecimalNumber`/`NSDecimalNumberHandler`
//  because the raw C `NSDecimalRound` is `internal` in the Swift overlay and not
//  callable from Nebula (verified `.swiftinterface` line 7051). See
//  vault/01-fundamentos/nebula-number-measurement-extensions.md.
//

import Foundation

extension Decimal {
    /// Returns `self` rounded to `places` decimal places using `rule`.
    ///
    /// `Decimal` has no value-level `rounded(_:)` method (the only `rounded`
    /// members on `Decimal` return a `Decimal.FormatStyle`, not a `Decimal`).
    /// This bridges through `NSDecimalNumber` with an `NSDecimalNumberHandler`
    /// configured to `scale = places` and the requested rounding mode — the
    /// public, all-platform path (the raw C `NSDecimalRound` is `internal` in
    /// the Foundation Swift overlay and cannot be called from Nebula).
    ///
    /// There is **no `Double` round-trip**: the value stays base-10 accurate.
    /// Negative `places` rounds to the left of the decimal point (matching
    /// `NSDecimalNumberHandler.scale`).
    ///
    /// ```swift
    /// Decimal(string: "1.235")!.rounded(toDecimalPlaces: 2)            // 1.24
    /// Decimal(string: "1.235")!.rounded(toDecimalPlaces: 2, rule: .down) // 1.23
    /// ```
    public func rounded(
        toDecimalPlaces places: Int,
        rule: NebulaDecimalRoundingRule = .bankers
    ) -> Decimal {
        // `NSDecimalNumberHandler` and `NSDecimalNumber` are Clang-imported
        // (no `API_AVAILABLE` annotation → available on every platform since
        // the beginning). The handler is constructed per call and discarded —
        // never cached — so there is no shared mutable state to guard.
        let behavior = NSDecimalNumberHandler(
            roundingMode: rule.nsRoundingMode,
            scale: Int16(places),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: self)
            .rounding(accordingToBehavior: behavior)
            .decimalValue
    }
}