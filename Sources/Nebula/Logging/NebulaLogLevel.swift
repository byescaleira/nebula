//
//  NebulaLogLevel.swift
//  Nebula
//
//  Nebula's five-level log taxonomy, mapped 1:1 to `os.OSLogType`.
//  See the logging foundation note in vault/01-fundamentos/nebula-logging.md.
//

import Foundation
import os

/// A Nebula log level, mapped 1:1 to `os.OSLogType`.
///
/// Nebula adopts `os.Logger`'s five-level taxonomy (see WWDC20 "Explore logging
/// in Swift"). ``NebulaLogLevel/notice`` maps to `OSLogType.default` (the os
/// overlay has no `.notice` case); ``NebulaLogLevel/warning`` is an alias for
/// ``NebulaLogLevel/error`` exactly as `Logger.warning` does internally
/// (`osLogInternal(... type: .error)`, verified against the installed
/// `os.swiftmodule`).
///
/// Levels are ordered by severity so callers can gate with `>=` against a
/// configuration's `minLevel`:
///
/// ```swift
/// guard level >= config.minLevel else { return }
/// ```
public enum NebulaLogLevel: Int, Sendable, Codable, CaseIterable, Comparable {
    /// Debug-level messages — `OSLogType.debug`. High volume, persisted only when
    /// the system is configured to collect debug data.
    case debug = 0
    /// Info-level messages — `OSLogType.info`. Captured to disk but not shown in
    /// Console.app by default.
    case info = 1
    /// Notice-level messages — `OSLogType.default`. The default os level; always
    /// persisted.
    case notice = 2
    /// Error-level messages — `OSLogType.error`. Always persisted.
    case error = 3
    /// Fault-level messages — `OSLogType.fault`. Captures a backtrace; reserved
    /// for unexpected failures.
    case fault = 4

    /// A severity alias for ``NebulaLogLevel/error``, matching `Logger.warning`
    /// (which forwards to `OSLogType.error`). Not a `case`, so it is absent from
    /// `CaseIterable`; it equals ``error``.
    public static let warning: NebulaLogLevel = .error

    /// The `os.OSLogType` this level forwards to.
    public var osLogType: OSLogType {
        switch self {
        case .debug:  return .debug
        case .info:   return .info
        case .notice: return .default
        case .error:  return .error
        case .fault:  return .fault
        }
    }

    /// Creates the level that maps to the given `os.OSLogType`.
    ///
    /// Unknown / unmapped os types (e.g. a future case) fall back to
    /// ``NebulaLogLevel/notice`` (`OSLogType.default`).
    public init(osLogType: OSLogType) {
        switch osLogType {
        case .debug:  self = .debug
        case .info:   self = .info
        case .error:  self = .error
        case .fault:  self = .fault
        default:      self = .notice
        }
    }

    /// `Comparable` by `rawValue` (severity).
    public static func < (lhs: NebulaLogLevel, rhs: NebulaLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}