//
//  BinaryFloatingPoint+Nebula.swift
//  Nebula
//
//  `BinaryFloatingPoint` gap-fillers: `isWholeNumber`, a value-level
//  `rounded(toDecimalPlaces:rule:)` (lossy — documented), and a generic
//  `.measured(in:)` `Measurement<Unit>` builder. Natural names per CLAUDE.md —
//  the stdlib deliberately lacks these. `clamped(to:)` is NOT redeclared: it is
//  inherited from `Comparable.clamped(to:)` (Primitive/Comparable+Nebula.swift),
//  since `FloatingPoint` conforms to `Comparable`. See
//  vault/01-fundamentos/nebula-number-measurement-extensions.md.
//

import Foundation

extension BinaryFloatingPoint {
    /// `true` if `self` is finite and has no fractional part.
    ///
    /// The stdlib's `FloatingPoint` exposes `isZero`/`isFinite`/`isNaN` but no
    /// "is whole number" predicate — this fills the gap by checking the rounded
    /// value equals `self`. `NaN`/infinity are not whole numbers.
    public var isWholeNumber: Bool {
        isFinite && rounded() == self
    }

    /// Returns `self` rounded to `places` decimal places using `rule`.
    ///
    /// Scales by `pow(10, places)`, rounds with the stdlib `FloatingPointRoundingRule`,
    /// and rescales. This is **lossy** for binary floating-point: values that
    /// cannot be represented exactly in base-2 (e.g. `0.1`) may not produce the
    /// visually-expected decimal result. For money or any base-10-exact context,
    /// use `Decimal` and `Decimal.rounded(toDecimalPlaces:rule:)` instead.
    ///
    /// ```swift
    /// (3.14159).rounded(toDecimalPlaces: 2)            // 3.14
    /// (2.5).rounded(toDecimalPlaces: 0, rule: .up)    // 3.0
    /// ```
    public func rounded(
        toDecimalPlaces places: Int,
        rule: FloatingPointRoundingRule = .toNearestOrEven
    ) -> Self {
        let factor = Self(pow(10.0, Double(places)))
        return (self * factor).rounded(rule) / factor
    }

    /// Wraps `self` as a `Measurement<Unit>` for the given `Dimension` unit.
    ///
    /// Generic over `Unit: Dimension`, so callers write
    /// `100.0.measured(in: UnitLength.kilometers).converted(to: .miles)` without
    /// a per-unit property explosion. The value is converted to `Double`
    /// (the storage type of `Measurement`) via the `Double(Self)` bridge.
    public func measured<Unit: Dimension>(in unit: Unit) -> Measurement<Unit> {
        Measurement(value: Double(self), unit: unit)
    }
}