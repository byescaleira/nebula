//
//  CodableFoundationTests.swift
//  NebulaTests
//
//  Tests for the Codable foundation layer (Swift Testing):
//  NebulaJSONDecoderConfiguration / NebulaJSONEncoderConfiguration, the
//  NebulaJSONDecoder / NebulaJSONEncoder wrappers, the DecodingError/
//  EncodingError projections, the NebulaError factory entry points, and the
//  Decodable/Encodable/Data ergonomics.
//

import Testing
import Foundation
import Nebula

// MARK: - Fixtures

private struct SnakeUser: Codable, Equatable, Sendable {
    let id: Int
    let fullName: String
    let createdAt: Date
}

private struct Blob: Codable, Equatable, Sendable {
    let payload: Data
}

private struct Pin: Codable, Equatable, Sendable {
    let value: Int
}

// MARK: - Configuration builders

@Suite("NebulaJSONDecoderConfiguration")
struct NebulaJSONDecoderConfigurationTests {
    @Test func defaultsMatchApple() {
        let c = NebulaJSONDecoderConfiguration.default
        if case .useDefaultKeys = c.keyDecodingStrategy { /* ok */ } else {
            Issue.record("expected .useDefaultKeys")
        }
        if case .deferredToDate = c.dateDecodingStrategy { /* ok */ } else {
            Issue.record("expected .deferredToDate")
        }
        if case .base64 = c.dataDecodingStrategy { /* ok */ } else {
            Issue.record("expected .base64")
        }
        if case .throw = c.nonConformingFloatDecodingStrategy { /* ok */ } else {
            Issue.record("expected .throw")
        }
        #expect(c.allowsJSON5 == false)
        #expect(c.assumesTopLevelDictionary == false)
        #expect(c.userInfo.isEmpty)
    }

    @Test func apiPreset() {
        let c = NebulaJSONDecoderConfiguration.api
        if case .convertFromSnakeCase = c.keyDecodingStrategy { /* ok */ } else {
            Issue.record("expected .convertFromSnakeCase")
        }
        if case .iso8601 = c.dateDecodingStrategy { /* ok */ } else {
            Issue.record("expected .iso8601 date strategy")
        }
    }

    @Test func withBuildersReturnCopies() {
        let original = NebulaJSONDecoderConfiguration.default
        let modified = original
            .withKeyDecodingStrategy(.convertFromSnakeCase)
            .withDateDecodingStrategy(.iso8601)
            .withAllowsJSON5(true)
            .withAssumesTopLevelDictionary(true)
        // Original unchanged.
        if case .useDefaultKeys = original.keyDecodingStrategy { /* ok */ } else {
            Issue.record("original should remain .useDefaultKeys")
        }
        #expect(original.allowsJSON5 == false)
        if case .convertFromSnakeCase = modified.keyDecodingStrategy { /* ok */ } else {
            Issue.record("expected .convertFromSnakeCase")
        }
        if case .iso8601 = modified.dateDecodingStrategy { /* ok */ } else {
            Issue.record("expected .iso8601")
        }
        #expect(modified.allowsJSON5 == true)
        #expect(modified.assumesTopLevelDictionary == true)
    }

    @Test func withUserInfoReplacesDictionary() {
        let key = CodingUserInfoKey(rawValue: "test")!
        let c = NebulaJSONDecoderConfiguration.default.withUserInfo([key: 42])
        #expect(c.userInfo[key] as? Int == 42)
        #expect(NebulaJSONDecoderConfiguration.default.userInfo.isEmpty)
    }
}

@Suite("NebulaJSONEncoderConfiguration")
struct NebulaJSONEncoderConfigurationTests {
    @Test func defaultsMatchApple() {
        let c = NebulaJSONEncoderConfiguration.default
        #expect(c.outputFormatting.rawValue == 0)
        if case .deferredToDate = c.dateEncodingStrategy { /* ok */ } else {
            Issue.record("expected .deferredToDate")
        }
        if case .base64 = c.dataEncodingStrategy { /* ok */ } else {
            Issue.record("expected .base64")
        }
        if case .throw = c.nonConformingFloatEncodingStrategy { /* ok */ } else {
            Issue.record("expected .throw")
        }
        if case .useDefaultKeys = c.keyEncodingStrategy { /* ok */ } else {
            Issue.record("expected .useDefaultKeys")
        }
        #expect(c.userInfo.isEmpty)
    }

    @Test func apiPreset() {
        let c = NebulaJSONEncoderConfiguration.api
        if case .convertToSnakeCase = c.keyEncodingStrategy { /* ok */ } else {
            Issue.record("expected .convertToSnakeCase")
        }
        if case .iso8601 = c.dateEncodingStrategy { /* ok */ } else {
            Issue.record("expected .iso8601 date strategy")
        }
    }

    @Test func withBuildersComposeFlags() {
        let c = NebulaJSONEncoderConfiguration.default
            .withPrettyPrinting()
            .withSortedKeys()
            .withWithoutEscapingSlashes()
        #expect(c.outputFormatting.contains(.prettyPrinted))
        #expect(c.outputFormatting.contains(.sortedKeys))
        #expect(c.outputFormatting.contains(.withoutEscapingSlashes))
        // Original still empty.
        #expect(NebulaJSONEncoderConfiguration.default.outputFormatting.isEmpty)
    }

    @Test func withOutputFormattingReplaces() {
        let c = NebulaJSONEncoderConfiguration.default
            .withOutputFormatting([.prettyPrinted])
        #expect(c.outputFormatting.contains(.prettyPrinted))
        #expect(NebulaJSONEncoderConfiguration.default.outputFormatting.rawValue == 0)
    }
}

// MARK: - Round-trip decode/encode

@Suite("NebulaJSONDecoder/Encoder round-trip")
struct NebulaJSONRoundTripTests {
    @Test func snakeCaseKeyRoundTrip() throws {
        let encoder = NebulaJSONEncoder(
            .default
                .withKeyEncodingStrategy(.convertToSnakeCase)
                .withDateEncodingStrategy(.iso8601)
        )
        let decoder = NebulaJSONDecoder(
            .default
                .withKeyDecodingStrategy(.convertFromSnakeCase)
                .withDateDecodingStrategy(.iso8601)
        )

        // Construct a JSON payload in snake_case and decode it.
        let json = #"{"id":7,"full_name":"Ada","created_at":"2026-01-02T03:04:05Z"}"#
        let data = json.data(using: .utf8)!
        let user = try decoder.decode(SnakeUser.self, from: data)
        #expect(user.id == 7)
        #expect(user.fullName == "Ada")
        #expect(user.createdAt == ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"))

        // Re-encode with snake_case keys and decode back symmetrically.
        let reencoded = try encoder.encode(user)
        let again = try decoder.decode(SnakeUser.self, from: reencoded)
        #expect(again == user)
    }

    @Test func iso8601DateStrategy() throws {
        let decoder = NebulaJSONDecoder(.api)
        let json = #"{"id":1,"full_name":"x","created_at":"2026-07-18T12:00:00Z"}"#
        let user = try decoder.decode(SnakeUser.self, from: json.data(using: .utf8)!)
        let expected = ISO8601DateFormatter().date(from: "2026-07-18T12:00:00Z")
        #expect(user.createdAt == expected)
    }

    @Test func base64DataStrategy() throws {
        let encoder = NebulaJSONEncoder()
        let decoder = NebulaJSONDecoder()
        let original = Blob(payload: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let data = try encoder.encode(original)
        let back = try decoder.decode(Blob.self, from: data)
        #expect(back == original)
    }

    @Test func prettyPrintingAndSortedKeys() throws {
        let encoder = NebulaJSONEncoder(
            .default.withPrettyPrinting().withSortedKeys()
        )
        let pin = Pin(value: 3)
        let data = try encoder.encode(pin)
        let string = String(data: data, encoding: .utf8) ?? ""
        #expect(string.contains("\n"))
        // Sorted key is "value" (only one key, but sortedKeys shouldn't break it).
        #expect(string.contains("\"value\""))
    }
}

// MARK: - Decodable / Encodable / Data ergonomics

@Suite("Codable ergonomics")
struct CodableErgonomicsTests {
    @Test func initFromJSONDefaultDecoder() throws {
        let json = #"{"value":42}"#.data(using: .utf8)!
        let pin = try Pin(fromJSON: json)
        #expect(pin.value == 42)
    }

    @Test func staticDecodeFromJSONWithConfiguration() throws {
        let json = #"{"value":99}"#.data(using: .utf8)!
        let pin = try Pin.decode(fromJSON: json, configuration: .default)
        #expect(pin.value == 99)
    }

    @Test func toJSONDataAndString() throws {
        let pin = Pin(value: 5)
        let data = try pin.toJSONData()
        let string = try pin.toJSONString()
        #expect(string != nil)
        let back = try Pin(fromJSON: data)
        #expect(back == pin)
    }

    @Test func asPrettyJSONStringFormatsAndSorts() throws {
        let json = #"{"b":1,"a":2}"#.data(using: .utf8)!
        let pretty = json.asPrettyJSONString
        #expect(pretty != nil)
        // Sorted keys: "a" precedes "b".
        if let pretty {
            #expect(pretty.range(of: "\"a\"")!.lowerBound < pretty.range(of: "\"b\"")!.lowerBound)
            #expect(pretty.contains("\n"))
        }
    }

    @Test func asPrettyJSONStringReturnsNilForGarbage() {
        let garbage = "not json".data(using: .utf8)!
        #expect(garbage.asPrettyJSONString == nil)
    }
}

// MARK: - decodeAsNebulaError / encodeAsNebulaError

@Suite("NebulaJSONDecoder/Encoder NebulaError mapping")
struct NebulaJSONErrorMappingTests {
    @Test func decodeAsNebulaErrorMapsTypeMismatch() {
        let json = #"{"value":"not-an-int"}"#.data(using: .utf8)!
        let result = NebulaJSONDecoder().decodeAsNebulaError(Pin.self, from: json)
        switch result {
        case .success:
            Issue.record("expected failure")
        case .failure(let error):
            #expect(error.kind == .decoding)
            #expect(error.code.domain == "Swift.DecodingError")
            #expect(error.context != nil)
            #expect(!error.context!.codingPath.isEmpty)
        }
    }

    @Test func decodeAsNebulaErrorSucceeds() throws {
        let json = #"{"value":7}"#.data(using: .utf8)!
        let result = NebulaJSONDecoder().decodeAsNebulaError(Pin.self, from: json)
        let pin = try result.get()
        #expect(pin.value == 7)
    }

    @Test func encodeAsNebulaErrorSucceeds() throws {
        let result = NebulaJSONEncoder().encodeAsNebulaError(Pin(value: 1))
        let data = try result.get()
        #expect(!data.isEmpty)
    }
}

// MARK: - NebulaDecodingError / NebulaEncodingError projections

@Suite("DecodingError/EncodingError projections")
struct NebulaErrorProjectionTests {
    @Test func decodingErrorProjectsToKindAndPath() throws {
        // Force a type mismatch by decoding a string into an int.
        let json = #"{"value":"x"}"#.data(using: .utf8)!
        let caught: DecodingError? = {
            do {
                _ = try JSONDecoder().decode(Pin.self, from: json)
                return nil
            } catch let e as DecodingError {
                return e
            } catch {
                return nil
            }
        }()
        let e = try #require(caught)
        let projected = e.nebula
        #expect(projected.kind == .typeMismatch)
        #expect(projected.expectedType != nil)
        #expect(projected.codingPath.contains("value"))
        #expect(!projected.debugDescription.isEmpty)
    }

    @Test func keyNotFoundProjectionPreservesMissingKey() throws {
        let json = #"{}"#.data(using: .utf8)!
        let caught: DecodingError? = {
            do {
                _ = try JSONDecoder().decode(Pin.self, from: json)
                return nil
            } catch let e as DecodingError {
                return e
            } catch {
                return nil
            }
        }()
        let e = try #require(caught)
        let projected = e.nebula
        #expect(projected.kind == .keyNotFound)
        #expect(projected.missingKey == "value")
    }

    @Test func dataCorruptedProjectionOnBadJSON() throws {
        let json = "this is not json".data(using: .utf8)!
        let caught: DecodingError? = {
            do {
                _ = try JSONDecoder().decode(Pin.self, from: json)
                return nil
            } catch let e as DecodingError {
                return e
            } catch {
                return nil
            }
        }()
        let e = try #require(caught)
        let projected = e.nebula
        #expect(projected.kind == .dataCorrupted)
    }

    @Test func nebulaErrorDecodingFactoryMatchesInitializer() throws {
        let json = #"{"value":"x"}"#.data(using: .utf8)!
        let caught: DecodingError? = {
            do {
                _ = try JSONDecoder().decode(Pin.self, from: json)
                return nil
            } catch let e as DecodingError {
                return e
            } catch {
                return nil
            }
        }()
        let e = try #require(caught)
        let viaFactory = NebulaError.decoding(e)
        let viaInit = NebulaError(decodingError: e)
        #expect(viaFactory.kind == .decoding)
        #expect(viaFactory.code == viaInit.code)
        #expect(viaFactory.context?.codingPath == viaInit.context?.codingPath)
    }

    @Test func encodingErrorFactoryProducesEncodingKind() {
        // Synthesize an EncodingError directly and exercise the factory.
        let ctx = EncodingError.Context(codingPath: [], debugDescription: "boom")
        let e = EncodingError.invalidValue(42, ctx)
        let error = NebulaError.encoding(e)
        #expect(error.kind == .encoding)
        #expect(error.code.domain == "Swift.EncodingError")
        #expect(error.context?.debugDescription == "boom")
    }

    @Test func encodeAsNebulaErrorMapsEncodingFailure() {
        struct Boom: Encodable {
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(AnyEncodableBad())
            }
        }
        struct AnyEncodableBad: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "bad")
                )
            }
        }
        let result = NebulaJSONEncoder().encodeAsNebulaError(Boom())
        switch result {
        case .success:
            Issue.record("expected encoding failure")
        case .failure(let error):
            // Through NebulaError.wrap -> init(error:) -> init(error as NSError);
            // the NSError domain is "Swift.EncodingError" so kind infers .encoding.
            #expect(error.kind == .encoding || error.kind == .unknown)
        }
    }
}

// MARK: - Sendable sanity

@Suite("Codable layer Sendable")
struct CodableSendableTests {
    @Test func configurationsAndWrappersAreSendable() {
        // Constructing and holding these in a `let` is enough to compile-check
        // Sendable; no runtime assertion needed.
        let configs: [any Sendable] = [
            NebulaJSONDecoderConfiguration.default,
            NebulaJSONEncoderConfiguration.default,
            NebulaJSONDecoder(),
            NebulaJSONEncoder(),
            NebulaJSONDecoderConfiguration.api,
            NebulaJSONEncoderConfiguration.api,
        ]
        #expect(configs.count == 6)
    }
}