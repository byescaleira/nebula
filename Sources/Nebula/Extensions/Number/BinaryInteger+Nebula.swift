//
//  BinaryInteger+Nebula.swift
//  Nebula
//
//  `BinaryInteger` gap-filler: a generic `.measured(in:)` `Measurement<Unit>`
//  builder. Sibling to `BinaryFloatingPoint.measured(in:)`. `clamped(to:)` and
//  `isEven`/`isOdd`/`times(_:)` are NOT redeclared — they live in
//  `Primitive/Comparable+Nebula.swift` and `Primitive/Integer+Nebula.swift`.
//  See vault/01-fundamentos/nebula-number-measurement-extensions.md.
//

import Foundation

extension BinaryInteger {
    /// Wraps `self` as a `Measurement<Unit>` for the given `Dimension` unit.
    ///
    /// Generic over `Unit: Dimension`, so callers write
    /// `100.measured(in: UnitMass.kilograms).converted(to: .pounds)` without a
    /// per-unit property explosion. The value is converted to `Double` (the
    /// storage type of `Measurement`) via the `Double(Self)` bridge.
    public func measured<Unit: Dimension>(in unit: Unit) -> Measurement<Unit> {
        Measurement(value: Double(self), unit: unit)
    }
}