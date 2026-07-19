//
//  NebulaJSONDecoderConfiguration.swift
//  Nebula
//
//  A Sendable, configure-once-and-freeze wrapper over `Foundation.JSONDecoder`.
//  Mirrors the Cosmos sibling's `CosmosLogConfiguration` contract — `Sendable`
//  struct + fluent `.with*` builders — WITHOUT SwiftUI `@Entry`/`@Observable`.
//  See vault/01-fundamentos/nebula-codable-foundation.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (Foundation.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `JSONDecoder` is `open class` (line 8493) and conforms to `Sendable` via an
//    `@unchecked` extension (line 8560, `@available(macOS 13.0, iOS 16.0, tvOS
//    16.0, watchOS 9.0, *)` — always present at the Nebula `.v26` floor).
//  - The strategy enums are all `Swift::Sendable` (lines 8494, 8503, 8508,
//    8512); their `custom` cases take `@Sendable` closures.
//  - `allowsJSON5` / `assumesTopLevelDictionary` are iOS 15+/macOS 12+ (lines
//    8542–8548); below the `.v26` floor.
//  - `decode(_:from:configuration:)` is iOS 17+/macOS 14+ (line 8554); below
//    the `.v26` floor.
//  No `@available` gating is required inside Nebula — every consumed API is
//  at or below OS 26 on all five target platforms (visionOS 1.0+ via the `*`
//  wildcard).
//

import Foundation

/// A `Sendable` configuration value describing how a ``NebulaJSONDecoder``
/// configures its underlying `JSONDecoder`.
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// fluent `.with*` builders — without any SwiftUI environment plumbing:
/// Nebula is a foundation, so configurations are constructed and passed
/// explicitly.
///
/// `Sendable` is **derived** (not `@unchecked`): every stored field is
/// `Sendable` (the strategy enums are `Swift::Sendable`; `Bool` and
/// `[CodingUserInfoKey: any Sendable]` are `Sendable`). The builder methods
/// return mutated copies, so a configuration is frozen the moment it is
/// handed to ``NebulaJSONDecoder``.
///
/// - Warning: `DateDecodingStrategy.formatted(DateFormatter)` carries a
///   non-`Sendable` `DateFormatter`. Apple nonetheless declares the strategy
///   enum `Sendable`, so a configuration using that case **compiles** as
///   `Sendable` but is runtime-unsound if the formatter is mutated. Prefer
///   `.iso8601` or `.custom(@Sendable)`; treat `.formatted(DateFormatter)` as
///   an explicit, unsafe opt-in.
public struct NebulaJSONDecoderConfiguration: Sendable {

    /// The key decoding strategy. Defaults to `.useDefaultKeys`.
    public var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy
    /// The date decoding strategy. Defaults to `.deferredToDate`.
    public var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
    /// The data decoding strategy. Defaults to `.base64`.
    public var dataDecodingStrategy: JSONDecoder.DataDecodingStrategy
    /// The strategy for non-conforming floats (`Infinity`/`NaN`). Defaults to
    /// `.throw`, matching Apple's default. Some APIs emit `Infinity`/`NaN`;
    /// switch to `.convertFromString(...)` to accept them.
    public var nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy
    /// Whether JSON5 extensions are permitted. Defaults to `false`.
    public var allowsJSON5: Bool
    /// Whether the decoder may assume the top-level JSON value is a
    /// dictionary. Defaults to `false`.
    public var assumesTopLevelDictionary: Bool
    /// Per-decode user info. All values MUST be `Sendable`; non-`Sendable`
    /// values would trigger Swift 6 data-race warnings.
    public var userInfo: [CodingUserInfoKey: any Sendable]

    /// Creates a configuration with Apple's `JSONDecoder` defaults.
    public init(
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate,
        dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64,
        nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy = .throw,
        allowsJSON5: Bool = false,
        assumesTopLevelDictionary: Bool = false,
        userInfo: [CodingUserInfoKey: any Sendable] = [:]
    ) {
        self.keyDecodingStrategy = keyDecodingStrategy
        self.dateDecodingStrategy = dateDecodingStrategy
        self.dataDecodingStrategy = dataDecodingStrategy
        self.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        self.allowsJSON5 = allowsJSON5
        self.assumesTopLevelDictionary = assumesTopLevelDictionary
        self.userInfo = userInfo
    }

    /// The default configuration (Apple's `JSONDecoder` defaults).
    public static let `default` = NebulaJSONDecoderConfiguration()

    /// A preset tuned for typical JSON web APIs: snake_case keys mapped to
    /// camelCase Swift properties and ISO 8601 dates.
    public static let api = NebulaJSONDecoderConfiguration(
        keyDecodingStrategy: .convertFromSnakeCase,
        dateDecodingStrategy: .iso8601
    )

    // MARK: - Fluent builders

    /// Returns a copy with the key decoding strategy replaced.
    public func withKeyDecodingStrategy(_ strategy: JSONDecoder.KeyDecodingStrategy) -> Self {
        var copy = self
        copy.keyDecodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the date decoding strategy replaced.
    public func withDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy) -> Self {
        var copy = self
        copy.dateDecodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the data decoding strategy replaced.
    public func withDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy) -> Self {
        var copy = self
        copy.dataDecodingStrategy = strategy
        return copy
    }

    /// Returns a copy with the non-conforming-float strategy replaced.
    public func withNonConformingFloatDecodingStrategy(_ strategy: JSONDecoder.NonConformingFloatDecodingStrategy) -> Self {
        var copy = self
        copy.nonConformingFloatDecodingStrategy = strategy
        return copy
    }

    /// Returns a copy with `allowsJSON5` replaced.
    public func withAllowsJSON5(_ allows: Bool) -> Self {
        var copy = self
        copy.allowsJSON5 = allows
        return copy
    }

    /// Returns a copy with `assumesTopLevelDictionary` replaced.
    public func withAssumesTopLevelDictionary(_ assumes: Bool) -> Self {
        var copy = self
        copy.assumesTopLevelDictionary = assumes
        return copy
    }

    /// Returns a copy with the user-info dictionary replaced.
    public func withUserInfo(_ userInfo: [CodingUserInfoKey: any Sendable]) -> Self {
        var copy = self
        copy.userInfo = userInfo
        return copy
    }

    // MARK: - Build

    /// Builds and returns a freshly configured `JSONDecoder`.
    ///
    /// Called once by ``NebulaJSONDecoder.init(_:)``; the returned instance is
    /// held immutably and never re-exposed, preserving the configure-once-and-
    /// freeze discipline that makes the `@unchecked Sendable` `JSONDecoder`
    /// safe to share.
    internal func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dateDecodingStrategy = dateDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        decoder.allowsJSON5 = allowsJSON5
        decoder.assumesTopLevelDictionary = assumesTopLevelDictionary
        decoder.userInfo = userInfo
        return decoder
    }
}

/// A `Sendable`, configure-once-and-freeze wrapper over `JSONDecoder`.
///
/// `JSONDecoder` conforms to `Sendable` via Apple's `@unchecked` extension
/// (iOS 16+/macOS 13+, always present at the `.v26` floor). Holding the
/// decoder in an immutable `let` after configuring it once — and never
/// re-exposing the underlying instance — gives a **derived** `Sendable`
/// conformance without authoring `@unchecked` on a Nebula-defined type. The
/// frozen decoder is safe to share across tasks because it is never mutated
/// after construction.
public struct NebulaJSONDecoder: Sendable {

    /// The configuration this decoder was built from.
    public let configuration: NebulaJSONDecoderConfiguration

    /// The underlying `JSONDecoder`, configured once at init and never mutated.
    private let decoder: JSONDecoder

    /// Creates a decoder from a configuration.
    public init(_ configuration: NebulaJSONDecoderConfiguration = .default) {
        self.configuration = configuration
        self.decoder = configuration.makeDecoder()
    }

    /// Decodes a top-level value of the given type from the given data.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// Decodes a value of a `DecodableWithConfiguration` type using the given
    /// per-type configuration.
    public func decode<T: DecodableWithConfiguration>(
        _ type: T.Type,
        from data: Data,
        configuration decodingConfiguration: T.DecodingConfiguration
    ) throws -> T {
        try decoder.decode(type, from: data, configuration: decodingConfiguration)
    }

    /// Decodes a value of a `DecodableWithConfiguration` type using a
    /// configuration provided by `C`.
    public func decode<T, C>(
        _ type: T.Type,
        from data: Data,
        configuration configurationProvider: C.Type
    ) throws -> T where T: DecodableWithConfiguration, C: DecodingConfigurationProviding, T.DecodingConfiguration == C.DecodingConfiguration {
        try decoder.decode(type, from: data, configuration: configurationProvider)
    }

    /// Decodes, mapping any thrown `DecodingError` (or other `Error`) to a
    /// ``NebulaError`` via the existing lossy mapping
    /// (`NebulaError.init(decodingError:)` / `NebulaError.init(error:)`).
    public func decodeAsNebulaError<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, NebulaError> {
        NebulaError.wrap { try decoder.decode(type, from: data) }
    }
}