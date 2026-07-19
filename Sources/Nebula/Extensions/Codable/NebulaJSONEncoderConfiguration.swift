//
//  NebulaJSONEncoderConfiguration.swift
//  Nebula
//
//  A Sendable, configure-once-and-freeze wrapper over `Foundation.JSONEncoder`.
//  Mirrors the Cosmos sibling's `CosmosLogConfiguration` contract — `Sendable`
//  struct + fluent `.with*` builders — WITHOUT SwiftUI `@Entry`/`@Observable`.
//  See vault/01-fundamentos/nebula-codable-foundation.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (Foundation.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `JSONEncoder` is `open class` (line 8564) and conforms to `Sendable` via
//    an `@unchecked` extension (line 8641, `@available(macOS 13.0, iOS 16.0,
//    tvOS 16.0, watchOS 9.0, *)` — always present at the `.v26` floor).
//  - `OutputFormatting` is a `Sendable OptionSet` (line 8565) with exactly
//    three cases: `prettyPrinted`, `sortedKeys` (iOS 11+), `withoutEscapingSlashes`
//    (iOS 13+). There is NO `fragmentsAllowed` on `OutputFormatting`.
//  - The strategy enums are all `Swift::Sendable` (lines 8580, 8589, 8594,
//    8598); their `custom` cases take `@Sendable` closures.
//  - `encode(_:configuration:)` is iOS 17+/macOS 14+ (line 8636); below the
//    `.v26` floor.
//  No `@available` gating is required inside Nebula — every consumed API is
//  at or below OS 26 on all five target platforms (visionOS 1.0+ via the `*`
//  wildcard).
//

import Foundation

/// A `Sendable` configuration value describing how a ``NebulaJSONEncoder``
/// configures its underlying `JSONEncoder`.
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// fluent `.with*` builders — without any SwiftUI environment plumbing.
///
/// `Sendable` is **derived** (not `@unchecked`): every stored field is
/// `Sendable` (`OutputFormatting` is a `Sendable OptionSet`; the strategy
/// enums are `Swift::Sendable`; `Bool` and `[CodingUserInfoKey: any Sendable]`
/// are `Sendable`).
///
/// - Warning: `DateEncodingStrategy.formatted(DateFormatter)` carries a
///   non-`Sendable` `DateFormatter`. Apple nonetheless declares the strategy
///   enum `Sendable`, so a configuration using that case **compiles** as
///   `Sendable` but is runtime-unsound if the formatter is mutated. Prefer
///   `.iso8601` or `.custom(@Sendable)`; treat `.formatted(DateFormatter)` as
///   an explicit, unsafe opt-in.
public struct NebulaJSONEncoderConfiguration: Sendable {

    /// The output formatting options. Defaults to `[]`.
    public var outputFormatting: JSONEncoder.OutputFormatting
    /// The date encoding strategy. Defaults to `.deferredToDate` (Apple's
    /// default, which emits a `Double` seconds-since-epoch). For interop with
    /// typical JSON web APIs, use the ``api`` preset (`.iso8601`).
    public var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy
    /// The data encoding strategy. Defaults to `.base64`.
    public var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy
    /// The strategy for non-conforming floats (`Infinity`/`NaN`). Defaults to
    /// `.throw`, matching Apple's default.
    public var nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy
    /// The key encoding strategy. Defaults to `.useDefaultKeys`.
    public var keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy
    /// Per-encode user info. All values MUST be `Sendable`.
    public var userInfo: [CodingUserInfoKey: any Sendable]

    /// Creates a configuration with Apple's `JSONEncoder` defaults.
    public init(
        outputFormatting: JSONEncoder.OutputFormatting = [],
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        dataEncodingStrategy: JSONEncoder.DataEncodingStrategy = .base64,
        nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy = .throw,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
        userInfo: [CodingUserInfoKey: any Sendable] = [:]
    ) {
        self.outputFormatting = outputFormatting
        self.dateEncodingStrategy = dateEncodingStrategy
        self.dataEncodingStrategy = dataEncodingStrategy
        self.nonConformingFloatEncodingStrategy = nonConformingFloatEncodingStrategy
        self.keyEncodingStrategy = keyEncodingStrategy
        self.userInfo = userInfo
    }

    /// The default configuration (Apple's `JSONEncoder` defaults).
    public static let `default` = NebulaJSONEncoderConfiguration()

    /// A preset tuned for typical JSON web APIs: snake_case keys emitted from
    /// camelCase Swift properties and ISO 8601 dates.
    public static let api = NebulaJSONEncoderConfiguration(
        dateEncodingStrategy: .iso8601,
        keyEncodingStrategy: .convertToSnakeCase
    )

    // MARK: - Fluent builders

    /// Returns a copy with the output formatting options replaced.
    public func withOutputFormatting(_ formatting: JSONEncoder.OutputFormatting) -> Self {
        var copy = self
        copy.outputFormatting = formatting
        return copy
    }

    /// Returns a copy with pretty-printing enabled (`.prettyPrinted`).
    public func withPrettyPrinting() -> Self {
        var copy = self
        copy.outputFormatting.insert(.prettyPrinted)
        return copy
    }

    /// Returns a copy with sorted keys enabled (`.sortedKeys`). Keys sort
    /// lexicographically by `String`, not by declaration order.
    public func withSortedKeys() -> Self {
        var copy = self
        copy.outputFormatting.insert(.sortedKeys)
        return copy
    }

    /// Returns a copy with unescaped forward slashes (`.withoutEscapingSlashes`).
    public func withWithoutEscapingSlashes() -> Self {
        var copy = self
        copy.outputFormatting.insert(.withoutEscapingSlashes)
        return copy
    }

    /// Returns a copy with the date encoding strategy replaced.
    public func withDateEncodingStrategy(_ strategy: JSONEncoder.DateEncodingStrategy) -> Self {
        var copy = self
        copy.dateEncodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the data encoding strategy replaced.
    public func withDataEncodingStrategy(_ strategy: JSONEncoder.DataEncodingStrategy) -> Self {
        var copy = self
        copy.dataEncodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the non-conforming-float strategy replaced.
    public func withNonConformingFloatEncodingStrategy(_ strategy: JSONEncoder.NonConformingFloatEncodingStrategy) -> Self {
        var copy = self
        copy.nonConformingFloatEncodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the key encoding strategy replaced.
    public func withKeyEncodingStrategy(_ strategy: JSONEncoder.KeyEncodingStrategy) -> Self {
        var copy = self
        copy.keyEncodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the user-info dictionary replaced.
    public func withUserInfo(_ userInfo: [CodingUserInfoKey: any Sendable]) -> Self {
        var copy = self
        copy.userInfo = userInfo
        return copy
    }

    // MARK: - Build

    /// Builds and returns a freshly configured `JSONEncoder`.
    ///
    /// Called once by ``NebulaJSONEncoder.init(_:)``; the returned instance is
    /// held immutably and never re-exposed, preserving the configure-once-and-
    /// freeze discipline that makes the `@unchecked Sendable` `JSONEncoder`
    /// safe to share.
    internal func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = dateEncodingStrategy
        encoder.dataEncodingStrategy = dataEncodingStrategy
        encoder.nonConformingFloatEncodingStrategy = nonConformingFloatEncodingStrategy
        encoder.keyEncodingStrategy = keyEncodingStrategy
        encoder.userInfo = userInfo
        return encoder
    }
}

/// A `Sendable`, configure-once-and-freeze wrapper over `JSONEncoder`.
///
/// `JSONEncoder` conforms to `Sendable` via Apple's `@unchecked` extension
/// (iOS 16+/macOS 13+, always present at the `.v26` floor). Holding the
/// encoder in an immutable `let` after configuring it once — and never
/// re-exposing the underlying instance — gives a **derived** `Sendable`
/// conformance without authoring `@unchecked` on a Nebula-defined type. The
/// frozen encoder is safe to share across tasks because it is never mutated
/// after construction.
public struct NebulaJSONEncoder: Sendable {

    /// The configuration this encoder was built from.
    public let configuration: NebulaJSONEncoderConfiguration

    /// The underlying `JSONEncoder`, configured once at init and never mutated.
    private let encoder: JSONEncoder

    /// Creates an encoder from a configuration.
    public init(_ configuration: NebulaJSONEncoderConfiguration = .default) {
        self.configuration = configuration
        self.encoder = configuration.makeEncoder()
    }

    /// Encodes a top-level value to JSON `Data`.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    /// Encodes an `EncodableWithConfiguration` value with the given per-type
    /// configuration.
    public func encode<T: EncodableWithConfiguration>(
        _ value: T,
        configuration encodingConfiguration: T.EncodingConfiguration
    ) throws -> Data {
        try encoder.encode(value, configuration: encodingConfiguration)
    }

    /// Encodes an `EncodableWithConfiguration` value with a configuration
    /// provided by `C`.
    public func encode<T, C>(
        _ value: T,
        configuration configurationProvider: C.Type
    ) throws -> Data where T: EncodableWithConfiguration, C: EncodingConfigurationProviding, T.EncodingConfiguration == C.EncodingConfiguration {
        try encoder.encode(value, configuration: configurationProvider)
    }

    /// Encodes, mapping any thrown `EncodingError` (or other `Error`) to a
    /// ``NebulaError`` via the existing lossy mapping
    /// (`NebulaError.init(error:)`).
    public func encodeAsNebulaError(_ value: some Encodable) -> Result<Data, NebulaError> {
        NebulaError.wrap { try encoder.encode(value) }
    }
}