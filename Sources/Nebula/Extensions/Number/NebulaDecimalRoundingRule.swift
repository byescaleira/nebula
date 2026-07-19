//
//  NebulaDecimalRoundingRule.swift
//  Nebula
//
//  A Nebula-side `Decimal` rounding rule that maps 1:1 to
//  `NSDecimalNumber.RoundingMode` (the four `NSRoundingMode` C cases). `Decimal`
//  has NO value-level `rounded(_:)` method (verified against the Xcode 27 Beta 3
//  `.swiftinterface` — the only `rounded` members on `Decimal` are
//  `Decimal.FormatStyle.rounded(rule:increment:)`, which return a *style*, not a
//  rounded `Decimal`). See vault/01-fundamentos/nebula-number-measurement-extensions.md
//  and DECISIONS.md (ADR: `Decimal.rounded(toDecimalPlaces:)`).
//

import Foundation

/// A `Decimal` rounding rule, mapping 1:1 to `NSDecimalNumber.RoundingMode`.
///
/// `Decimal` has no value-level `rounded(_:)` method (verified against the
/// Xcode 27 Beta 3 `Foundation.swiftinterface`: the only `rounded` members on
/// `Decimal` are `Decimal.FormatStyle.rounded(rule:increment:)`, which return a
/// *style builder*, not a rounded `Decimal`). ``NebulaDecimalRoundingRule``
/// exposes the four `NSRoundingMode` C cases (verified in `NSDecimal.h`,
/// `typedef NS_ENUM(NSUInteger, NSRoundingMode)`) as a Swift `Sendable` enum so
/// callers pick a rule without touching `NSDecimalNumber` directly.
///
/// - Note: The raw C function `NSDecimalRound` is `@usableFromInline internal`
///   in the Foundation Swift overlay (`.swiftinterface` line 7051), so it is
///   NOT callable from Nebula. `Decimal.nebulaRounded(toDecimalPlaces:rule:)`
///   bridges through `NSDecimalNumber` + `NSDecimalNumberHandler` instead — the
///   only public, all-platform path to Decimal rounding.
public enum NebulaDecimalRoundingRule: Sendable {
    /// Round to the closest possible value; halfway between two positives
    /// rounds up, halfway between two negatives rounds down (`NSRoundPlain`).
    case plain
    /// Round toward negative infinity — floor (`NSRoundDown`). Verified
    /// empirically against `NSDecimalNumber` on the Xcode 27 Beta 3 toolchain:
    /// `-1.239` at 2 places → `-1.24`, `1.239` → `1.23`. This matches stdlib
    /// `FloatingPointRoundingRule.down` (NOT `.toZero`).
    case down
    /// Round toward positive infinity — ceil (`NSRoundUp`). Verified
    /// empirically: `-1.231` at 2 places → `-1.23`, `1.231` → `1.24`. This
    /// matches stdlib `FloatingPointRoundingRule.up` (NOT `.awayFromZero`).
    case up
    /// Round to the closest possible value; halfway rounds to the even last
    /// digit (`NSRoundBankers`). Matches `FloatingPointRoundingRule.toNearestOrEven`.
    case bankers

    /// The corresponding `NSDecimalNumber.RoundingMode` (the Swift name for the
    /// Clang-imported `NSRoundingMode`).
    internal var nsRoundingMode: NSDecimalNumber.RoundingMode {
        switch self {
        case .plain:   return .plain
        case .down:    return .down
        case .up:      return .up
        case .bankers: return .bankers
        }
    }
}