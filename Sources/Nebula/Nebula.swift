//
//  Nebula.swift
//  Nebula
//
//  Foundation layer for the Nebula package. The public surface is built up
//  wave-by-wave (see ROADMAP.md); this file is the Wave A scaffold that makes
//  the package build and establishes the versioning spine.
//

/// The Nebula foundation library.
///
/// A Swift foundation/architecture SwiftPM package consumed by apps and other
/// SPM packages. Mirrors the Cosmos sibling design-system package's
/// conventions: `Sendable` value types, `@Sendable` handlers, `Mutex`/`Atomic`
/// from `Synchronization`, no third-party dependencies, no UIKit, and
/// Apple-aligned modern APIs (`FormatStyle`, `Measurement`, `os.Logger`,
/// `os.signpost`, `Regex`, `AttributedString`, `Duration`/`Clock`).
///
/// See `CLAUDE.md` for the binding guidelines, `ARCHITECTURE.md` for the module
/// structure, and `VERSIONING.md` for the versioning policy.
public enum Nebula {
    /// The Nebula package version, aligned to the Apple OS major it targets
    /// (Nebula major == OS major). Baseline: Nebula 26 (OS 26 / Liquid Glass).
    public static let version = NebulaVersion(major: 26, minor: 0, patch: 0)
}

/// A `Sendable` value type describing a Nebula package version.
///
/// A Nebula major release targets the matching OS major across all supported
/// platforms; within a major, semantic minor/patch applies. See `VERSIONING.md`.
public struct NebulaVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    /// The OS-aligned major (Nebula 26 == OS 26).
    public let major: Int
    /// Additive APIs / non-breaking changes within a major.
    public let minor: Int
    /// Bug fixes within a minor.
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: NebulaVersion, rhs: NebulaVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}