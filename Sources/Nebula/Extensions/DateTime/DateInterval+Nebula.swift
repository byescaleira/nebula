//
//  DateInterval+Nebula.swift
//  Nebula
//
//  A `Swift.Duration`-typed bridge to `DateInterval.init(start:duration:)`,
//  which Foundation declares only for `TimeInterval`. Explicit `Swift.Duration`
//  typing disambiguates the overload. Attosecond-aware conversion (no
//  precision loss for whole-second durations). Stateless; `DateInterval`
//  derives `Sendable`.
//  See vault/01-fundamentos/nebula-date-time-extensions.md.
//

import Foundation

extension DateInterval {
    /// Creates an interval starting at `start` spanning `duration`.
    ///
    /// Foundation already declares `init(start: Date, duration: TimeInterval)`
    /// — this is the **distinct `Swift.Duration`-typed overload**, explicitly
    /// typed to avoid ambiguity. Conversion is attosecond-aware:
    /// `Duration.components` yields `(seconds, attoseconds)`, reconstructed
    /// as `TimeInterval` without a sub-second round trip.
    public init(start: Date, duration: Swift.Duration) {
        let components = duration.components
        let seconds = TimeInterval(components.seconds)
        let attoseconds = TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        self.init(start: start, duration: seconds + attoseconds)
    }
}