//
//  String+NebulaDetection.swift
//  Nebula
//
//  `NSDataDetector` wrappers: `dataDetectedEntities(types:)`, `urls()`,
//  `firstURL()`. Per Apple's `NSRegularExpression.h` guidance, `NSDataDetector`
//  is for natural-language **detection, NOT validation** — see the
//  `> Important` note at line 545. Instances are expensive to create but
//  thread-safe post-init, so detectors are cached in a
//  `Mutex<[NSTextCheckingResult.CheckingType: NSDataDetector]>` (Swift 6
//  `Synchronization`; `Mutex` requires iOS 18/macOS 15/tvOS 18/watchOS
//  11/visionOS 2 — all below the .v26 floor, no `@available` gate, no
//  `nonisolated(unsafe)` globals). See
//  vault/01-fundamentos/nebula-string-extensions.md.
//

import Foundation
import Synchronization

/// Caches `NSDataDetector` instances per checking-type mask. `NSDataDetector`
/// is an Objective-C class (not `Sendable`); it is held only inside the lock
/// and never escapes it — the `withLock` closure returns Sendable
/// `[NebulaStringDetectedEntity]` values built from non-Sendable results at
/// consumption time. `NSTextCheckingResult.CheckingType` is an `OptionSet`
/// that is `Equatable` but **not `Hashable`**, so the cache is keyed by its
/// `RawValue` (`UInt64`).
private let nebulaDetectorCache = Mutex<[NSTextCheckingResult.CheckingType.RawValue: NSDataDetector]>([:])

extension String {
    /// Returns the `NSDataDetector` entities found in `self` for the given
    /// `types`.
    ///
    /// Use only on natural-language text — `NSDataDetector` discards
    /// uncertain matches and Apple explicitly warns against using it for
    /// validation. To validate a candidate URL, use `URL(string:)`.
    ///
    /// The detector is created lazily and cached per `types` mask behind a
    /// `Mutex`, so repeated calls with the same `types` reuse one instance.
    /// Results are consumed immediately into ``NebulaStringDetectedEntity``
    /// (Sendable) values; the non-Sendable `NSTextCheckingResult` objects do
    /// not escape.
    ///
    /// - Parameter types: The checking types to detect (e.g.
    ///   `[.link, .phoneNumber]`). Combine via `OptionSet` array literal.
    /// - Returns: The detected entities, in order of appearance. Throws if
    ///   the `NSDataDetector` could not be initialized for `types`.
    public func dataDetectedEntities(
        types: NSTextCheckingResult.CheckingType
    ) throws -> [NebulaStringDetectedEntity] {
        let source = NSString(string: self)
        let range = NSRange(location: 0, length: source.length)
        return try nebulaDetectorCache.withLock { cache -> [NebulaStringDetectedEntity] in
            let detector: NSDataDetector
            if let cached = cache[types.rawValue] {
                detector = cached
            } else {
                detector = try NSDataDetector(types: types.rawValue)
                cache[types.rawValue] = detector
            }
            let results = detector.matches(in: source as String, options: [], range: range)
            return results.compactMap { NebulaStringDetectedEntity(result: $0, in: source) }
        }
    }

    /// Returns the URLs detected in `self` as natural-language text.
    ///
    /// Convenience over ``dataDetectedEntities(types:)`` restricted to
    /// `NSTextCheckingResult.CheckingType.link`, returning the `URL` values
    /// directly. See that method for the Apple "detection, not validation"
    /// caveat.
    public func urls() throws -> [URL] {
        try dataDetectedEntities(types: .link).compactMap { entity -> URL? in
            if case .link(let url) = entity { return url }
            return nil
        }
    }

    /// Returns the first URL detected in `self` as natural-language text, or
    /// `nil` if none.
    ///
    /// See ``urls()`` for the detection-vs-validation caveat.
    public func firstURL() throws -> URL? {
        try urls().first
    }
}