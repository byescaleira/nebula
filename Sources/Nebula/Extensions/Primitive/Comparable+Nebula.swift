//
//  Comparable+Nebula.swift
//  Nebula
//
//  Fills the SE-0177 gap (`clamped(to:)` was returned for revision and never
//  re-accepted). Natural name per CLAUDE.md — the stdlib deliberately lacks it.
//  See vault/01-fundamentos/nebula-primitive-extensions.md.
//

import Foundation

extension Comparable {
    /// Returns `self` clamped to `range`.
    ///
    /// Fills the Apple-acknowledged gap from [SE-0177](https://github.com/apple/swift-evolution/blob/main/proposals/0177-add-clamped-to-method.md)
    /// (returned for revision, never re-accepted). Available on every
    /// `Comparable` (including non-numeric types such as `String`/`URL`).
    ///
    /// ```swift
    /// 5.clamped(to: 0...10)     // 5
    /// (-1).clamped(to: 0...10)  // 0
    /// 99.clamped(to: 0...10)   // 10
    /// ```
    public func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}