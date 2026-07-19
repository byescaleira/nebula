//
//  Integer+Nebula.swift
//  Nebula
//
//  `BinaryInteger` gap-fillers: `isEven`/`isOdd` (delegating to stdlib
//  `isMultiple(of:)` — never redeclared) and `times(_:)` (non-escaping
//  `rethrows`, matching stdlib `forEach`). Natural names per CLAUDE.md.
//  See vault/01-fundamentos/nebula-primitive-extensions.md.
//

import Foundation

extension BinaryInteger {
    /// `true` if `self` is a multiple of 2.
    ///
    /// Delegates to stdlib `isMultiple(of:)` (Swift 5.0); never redeclared.
    public var isEven: Bool { isMultiple(of: 2) }

    /// `true` if `self` is not a multiple of 2.
    ///
    /// Delegates to stdlib `isMultiple(of:)` (Swift 5.0); never redeclared.
    public var isOdd: Bool { !isMultiple(of: 2) }

    /// Calls `body` `self` times.
    ///
    /// The closure is **non-escaping** and **non-`@Sendable`** `rethrows`
    /// (matching stdlib `forEach`); it never escapes this call, so `@Sendable`
    /// would be incorrect. `self` is interpreted as `Int` (small loop counts
    /// only — passing a value that does not fit in `Int` traps).
    public func times(_ body: () throws -> Void) rethrows {
        for _ in 0..<Int(self) {
            try body()
        }
    }
}