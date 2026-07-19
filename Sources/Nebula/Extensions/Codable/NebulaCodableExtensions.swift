//
//  NebulaCodableExtensions.swift
//  Nebula
//
//  Codable convenience extensions: faithful `DecodingError`/`EncodingError`
//  shapes, `NebulaError` factory entry points, and `Decodable`/`Encodable`/
//  `Data` JSON ergonomics layered on ``NebulaJSONDecoder``/``NebulaJSONEncoder``.
//  See vault/01-fundamentos/nebula-codable-foundation.md.
//
//  `DecodingError`/`EncodingError` live in the Swift stdlib (not the
//  Foundation `.swiftinterface`); the four `DecodingError` cases and single
//  `EncodingError.invalidValue(_:_:)` case are iOS 8.0+/macOS 10.10+ and
//  therefore unconditionally available at the `.v26` floor. `Context` exposes
//  `codingPath: [any CodingKey]`, `debugDescription: String`,
//  `underlyingError: Error?`.
//

import Foundation

// MARK: - NebulaDecodingError

/// A `Sendable`, structured projection of a `DecodingError` that preserves
/// Apple's `DecodingError.Context` fields faithfully rather than flattening
/// to a string.
///
/// The `codingPath` is rendered to `[String]` because `any CodingKey` is an
/// existential (not portably `Equatable` or trivially `Sendable` to expose
/// verbatim). For the lossy `NebulaError` envelope mapping, use
/// ``NebulaError/decoding(_:)`` or the existing
/// `NebulaError.init(decodingError:)`.
public struct NebulaDecodingError: Sendable, Error {
    /// A coarse classification mirroring `DecodingError`'s four cases.
    public enum Kind: Sendable {
        /// `DecodingError.keyNotFound`.
        case keyNotFound
        /// `DecodingError.valueNotFound`.
        case valueNotFound
        /// `DecodingError.typeMismatch`.
        case typeMismatch
        /// `DecodingError.dataCorrupted`.
        case dataCorrupted
    }

    /// The classified error kind.
    public let kind: Kind
    /// The stringified `DecodingError.Context.codingPath`.
    public let codingPath: [String]
    /// The expected type, when present (rendered via `String(describing:)`).
    public let expectedType: String?
    /// The missing key, when present.
    public let missingKey: String?
    /// The `debugDescription` from the source context.
    public let debugDescription: String
    /// A stringified description of `Context.underlyingError`, when present.
    public let underlyingErrorDescription: String?

    /// Creates a structured decoding error.
    public init(
        kind: Kind,
        codingPath: [String],
        expectedType: String? = nil,
        missingKey: String? = nil,
        debugDescription: String,
        underlyingErrorDescription: String? = nil
    ) {
        self.kind = kind
        self.codingPath = codingPath
        self.expectedType = expectedType
        self.missingKey = missingKey
        self.debugDescription = debugDescription
        self.underlyingErrorDescription = underlyingErrorDescription
    }
}

extension DecodingError {
    /// Projects this `DecodingError` into a ``NebulaDecodingError``.
    public var nebula: NebulaDecodingError {
        switch self {
        case .keyNotFound(let key, let ctx):
            return NebulaDecodingError(
                kind: .keyNotFound,
                codingPath: ctx.codingPath.map(\.stringValue),
                missingKey: key.stringValue,
                debugDescription: ctx.debugDescription,
                underlyingErrorDescription: ctx.underlyingError.map { String(describing: $0) }
            )
        case .valueNotFound(let type, let ctx):
            return NebulaDecodingError(
                kind: .valueNotFound,
                codingPath: ctx.codingPath.map(\.stringValue),
                expectedType: String(describing: type),
                debugDescription: ctx.debugDescription,
                underlyingErrorDescription: ctx.underlyingError.map { String(describing: $0) }
            )
        case .typeMismatch(let type, let ctx):
            return NebulaDecodingError(
                kind: .typeMismatch,
                codingPath: ctx.codingPath.map(\.stringValue),
                expectedType: String(describing: type),
                debugDescription: ctx.debugDescription,
                underlyingErrorDescription: ctx.underlyingError.map { String(describing: $0) }
            )
        case .dataCorrupted(let ctx):
            return NebulaDecodingError(
                kind: .dataCorrupted,
                codingPath: ctx.codingPath.map(\.stringValue),
                debugDescription: ctx.debugDescription,
                underlyingErrorDescription: ctx.underlyingError.map { String(describing: $0) }
            )
        @unknown default:
            return NebulaDecodingError(
                kind: .dataCorrupted,
                codingPath: [],
                debugDescription: self.localizedDescription
            )
        }
    }
}

// MARK: - NebulaEncodingError

/// A `Sendable`, structured projection of an `EncodingError` that preserves
/// Apple's `EncodingError.Context` fields faithfully.
public struct NebulaEncodingError: Sendable, Error {
    /// The stringified `EncodingError.Context.codingPath`.
    public let codingPath: [String]
    /// The value that failed to encode, rendered via `String(describing:)`.
    public let valueDescription: String?
    /// The `debugDescription` from the source context.
    public let debugDescription: String
    /// A stringified description of `Context.underlyingError`, when present.
    public let underlyingErrorDescription: String?

    /// Creates a structured encoding error.
    public init(
        codingPath: [String],
        valueDescription: String? = nil,
        debugDescription: String,
        underlyingErrorDescription: String? = nil
    ) {
        self.codingPath = codingPath
        self.valueDescription = valueDescription
        self.debugDescription = debugDescription
        self.underlyingErrorDescription = underlyingErrorDescription
    }
}

extension EncodingError {
    /// Projects this `EncodingError` into a ``NebulaEncodingError``.
    public var nebula: NebulaEncodingError {
        switch self {
        case .invalidValue(let value, let ctx):
            return NebulaEncodingError(
                codingPath: ctx.codingPath.map(\.stringValue),
                valueDescription: String(describing: value),
                debugDescription: ctx.debugDescription,
                underlyingErrorDescription: ctx.underlyingError.map { String(describing: $0) }
            )
        @unknown default:
            return NebulaEncodingError(
                codingPath: [],
                debugDescription: self.localizedDescription
            )
        }
    }
}

// MARK: - NebulaError factory entry points

extension NebulaError {
    /// Maps a `DecodingError` into a ``NebulaError`` (`kind = .decoding`).
    ///
    /// Equivalent to `NebulaError(decodingError:)`; provided as a factory-style
    /// entry point symmetric with ``encoding(_:)``.
    public static func decoding(_ error: DecodingError) -> NebulaError {
        NebulaError(decodingError: error)
    }

    /// Maps an `EncodingError` into a ``NebulaError`` (`kind = .encoding`).
    public static func encoding(_ error: EncodingError) -> NebulaError {
        switch error {
        case .invalidValue(_, let ctx):
            var underlying: NebulaError.Box? = nil
            if let raw = ctx.underlyingError {
                var inner = NebulaError(error: raw)
                inner.underlying = nil
                underlying = NebulaError.Box(inner)
            }
            return NebulaError(
                code: NebulaError.Code(domain: "Swift.EncodingError", code: 0),
                kind: .encoding,
                message: ctx.debugDescription.isEmpty
                    ? error.localizedDescription
                    : "Encoding failed: \(ctx.debugDescription)",
                context: NebulaError.Context(
                    codingPath: ctx.codingPath.map(\.stringValue),
                    debugDescription: ctx.debugDescription
                ),
                underlying: underlying
            )
        @unknown default:
            return NebulaError(
                code: NebulaError.Code(domain: "Swift.EncodingError", code: 0),
                kind: .encoding,
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Decodable / Encodable / Data ergonomics

extension Decodable {
    /// Initializes `self` from JSON data using a ``NebulaJSONDecoder``.
    public init(fromJSON data: Data, using decoder: NebulaJSONDecoder = .init()) throws {
        self = try decoder.decode(Self.self, from: data)
    }

    /// Decodes a value of `Self` from JSON data using the given configuration.
    public static func decode(
        fromJSON data: Data,
        configuration: NebulaJSONDecoderConfiguration = .default
    ) throws -> Self {
        try NebulaJSONDecoder(configuration).decode(Self.self, from: data)
    }
}

extension Encodable {
    /// Encodes `self` to JSON `Data` using a ``NebulaJSONEncoder``.
    public func toJSONData(using encoder: NebulaJSONEncoder = .init()) throws -> Data {
        try encoder.encode(self)
    }

    /// Encodes `self` to a JSON `String` using a ``NebulaJSONEncoder``.
    public func toJSONString(using encoder: NebulaJSONEncoder = .init()) throws -> String? {
        String(data: try encoder.encode(self), encoding: .utf8)
    }
}

extension Data {
    /// Pretty-prints this JSON `Data` as a `String` using
    /// `[.prettyPrinted, .sortedKeys]`.
    ///
    /// Returns `nil` if the data is not a single valid JSON value. Top-level
    /// JSON fragments (bare number/string/bool/null) are NOT supported here —
    /// `JSONDecoder` cannot decode them; use
    /// `JSONSerialization.jsonObject(with:options:.allowFragments)` for
    /// fragment-tolerant parsing.
    public var asPrettyJSONString: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }
}