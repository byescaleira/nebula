//
//  DataURLExtensionsTests.swift
//  NebulaTests
//
//  Tests for the Data/URL/URLComponents Nebula extensions (Swift Testing).
//  SHA-256/384/512 are deterministic; expected digests below are the canonical
//  vectors for the documented inputs.
//

import Testing
import Foundation
import Nebula

// MARK: - Data hex

@Suite("Data.nebulaHexEncodedString")
struct DataHexEncodeTests {
    @Test func encodesLowercaseByDefault() {
        #expect(Data([0xDE, 0xAD, 0xBE, 0xEF]).nebulaHexEncodedString() == "deadbeef")
    }

    @Test func encodesUppercaseOnRequest() {
        #expect(Data([0xDE, 0xAD, 0xBE, 0xEF]).nebulaHexEncodedString(uppercase: true) == "DEADBEEF")
    }

    @Test func emptyDataEncodesToEmptyString() {
        #expect(Data().nebulaHexEncodedString() == "")
    }

    @Test func encodesSingleByteWithLeadingZero() {
        #expect(Data([0x00, 0x0F]).nebulaHexEncodedString() == "000f")
    }
}

@Suite("Data(nebulaHexEncoded:)")
struct DataHexDecodeTests {
    @Test func decodesLowercase() throws {
        let data = try #require(Data(nebulaHexEncoded: "deadbeef"))
        #expect(Array(data) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func decodesUppercase() throws {
        let data = try #require(Data(nebulaHexEncoded: "DEADBEEF"))
        #expect(Array(data) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func decodesMixedCase() throws {
        let data = try #require(Data(nebulaHexEncoded: "DeAdBeEf"))
        #expect(Array(data) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func stripsOptional0xPrefix() throws {
        let data = try #require(Data(nebulaHexEncoded: "0xdeadbeef"))
        #expect(Array(data) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func stripsOptional0XPrefix() throws {
        let data = try #require(Data(nebulaHexEncoded: "0Xdeadbeef"))
        #expect(Array(data) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func emptyStringProducesEmptyData() throws {
        let data = try #require(Data(nebulaHexEncoded: ""))
        #expect(data.isEmpty)
    }

    @Test func returnsNilOnOddLength() {
        #expect(Data(nebulaHexEncoded: "abc") == nil)
    }

    @Test func returnsNilOnNonHexCharacters() {
        #expect(Data(nebulaHexEncoded: "xyzz") == nil)
        #expect(Data(nebulaHexEncoded: "de ad") == nil)
    }

    @Test func roundTripsWithEncode() {
        let original = Data([0x00, 0x01, 0xFF, 0x80, 0x7F])
        let encoded = original.nebulaHexEncodedString()
        #expect(Data(nebulaHexEncoded: encoded) == original)
    }
}

// MARK: - Data UTF-8

@Suite("Data UTF-8 round-trip")
struct DataUTF8Tests {
    @Test func roundTripsASCII() throws {
        let data = try #require(Data(nebulaUTF8String: "hello"))
        #expect(data.nebulaUTF8String == "hello")
    }

    @Test func roundTripsMultibyte() throws {
        let s = "olá, mundo 🌍"
        let data = try #require(Data(nebulaUTF8String: s))
        #expect(data.nebulaUTF8String == s)
    }
}

// MARK: - Data base64 (thin alias)

@Suite("Data base64 thin alias")
struct DataBase64AliasTests {
    @Test func encodesViaNative() {
        let data = Data([0x4D, 0x65, 0x6E])  // "Men"
        #expect(data.nebulaBase64String() == data.base64EncodedString())
        #expect(data.nebulaBase64String() == "TWVu")
    }

    @Test func decodesViaNative() throws {
        let data = try #require(Data(nebulaBase64Encoded: "TWVu"))
        #expect(Array(data) == [0x4D, 0x65, 0x6E])
    }

    @Test func returnsNilOnMalformed() {
        #expect(Data(nebulaBase64Encoded: "!!!not base64!!!") == nil)
    }
}

// MARK: - Data base64URL (26.4 gated)

@Suite("Data base64URL (iOS 26.4)")
struct DataBase64URLTests {
    @Test func encodesURLSafeUnpadded() {
        guard #available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) else {
            // Skipped on Swift 6.3 / pre-26.4 runtimes; the API exists but is unavailable.
            return
        }
        // 4 bytes → standard base64 has 2 padding `=`; URL-safe omits them and
        // uses `-`/`_` instead of `+`/`/`.
        let data = Data([0xFB, 0xFF, 0xBF, 0x00])
        let standard = data.base64EncodedString()       // "+/+/AA=="
        let urlSafe = data.nebulaBase64URLEncoded()     // "-_-_AA"
        #expect(!urlSafe.contains("="))
        #expect(!urlSafe.contains("+"))
        #expect(!urlSafe.contains("/"))
        #expect(standard.contains("+"))
        #expect(standard.contains("/"))
        #expect(standard.contains("="))
    }

    @Test func decodesURLSafeUnpadded() throws {
        let data = Data([0xFB, 0xFF, 0xBF, 0x00])
        guard #available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) else { return }
        let urlSafe = data.nebulaBase64URLEncoded()      // "-_-_AA"
        #expect(urlSafe.count % 4 != 0)                  // padding was omitted
        let decoded = try #require(Data(nebulaBase64URLEncoded: urlSafe))
        #expect(decoded == data)
    }

    @Test func decodesURLSafePadded() throws {
        let data = Data([0xFB, 0xFF, 0xBF, 0x00])
        // Manually pad the URL-safe form to verify padding tolerance.
        let urlSafePadded = "-_-_AA=="
        let decoded = try #require(Data(nebulaBase64URLEncoded: urlSafePadded))
        #expect(decoded == data)
    }

    @Test func decodesStandardAlphabetAlsoAccepted() throws {
        // The decoder should also accept standard base64 input (it only translates
        // `-`/`_`, leaving `+`/`/` untouched).
        let data = Data([0xFB, 0xFF, 0xBF, 0x00])
        let standard = data.base64EncodedString()
        let decoded = try #require(Data(nebulaBase64URLEncoded: standard))
        #expect(decoded == data)
    }

    @Test func returnsNilOnMalformed() {
        #expect(Data(nebulaBase64URLEncoded: "!!!not base64!!!") == nil)
    }
}

// MARK: - Data digests

@Suite("Data.nebulaDigest")
struct DataDigestTests {
    @Test func sha256OfHelloIsCanonicalVector() {
        // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let digest = Data("hello".utf8).nebulaDigest(of: .sha256)
        #expect(digest.nebulaHexEncodedString()
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(digest.count == 32)
    }

    @Test func sha384OfHelloIs32Bytes() {
        let digest = Data("hello".utf8).nebulaDigest(of: .sha384)
        #expect(digest.count == 48)
    }

    @Test func sha512OfHelloIs64Bytes() {
        let digest = Data("hello".utf8).nebulaDigest(of: .sha512)
        #expect(digest.count == 64)
    }

    @Test func hexDigestDefaultsToSha256() {
        let hex = Data("hello".utf8).nebulaHexDigest()
        #expect(hex == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func sha2_256AliasEqualsSha256() {
        // The 26-floor alias should produce the same digest as .sha256.
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            let input = Data("nebula".utf8)
            #expect(input.nebulaDigest(of: .sha2_256) == input.nebulaDigest(of: .sha256))
        }
    }

    @Test func emptyDataSha256IsCanonicalVector() {
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(Data().nebulaHexDigest(of: .sha256)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}

// MARK: - Data trap-free slicing

@Suite("Data.nebulaSubdata")
struct DataSubdataTests {
    @Test func slicesInRange() {
        let d = Data([0, 1, 2, 3, 4])
        #expect(Array(d.nebulaSubdata(in: 2..<4)) == [2, 3])
    }

    @Test func emptyIntersectionReturnsEmptyNotTrap() {
        let d = Data([0, 1, 2, 3, 4])
        #expect(d.nebulaSubdata(in: 100..<200).isEmpty)
    }

    @Test func clampsUpperBound() {
        let d = Data([0, 1, 2, 3, 4])
        #expect(Array(d.nebulaSubdata(in: 3..<100)) == [3, 4])
    }

    @Test func clampsLowerBound() {
        let d = Data([0, 1, 2, 3, 4])
        #expect(Array(d.nebulaSubdata(in: -5..<2)) == [0, 1])
    }

    @Test func emptyRangeReturnsEmpty() {
        let d = Data([0, 1, 2, 3, 4])
        #expect(d.nebulaSubdata(in: 2..<2).isEmpty)
    }
}

// MARK: - URL query helpers

@Suite("URL query helpers")
struct URLQueryTests {
    @Test func appendsSingleQueryItem() throws {
        let base = try #require(URL(string: "https://example.com/path"))
        let result = try #require(base.nebulaAppending(queryItem: URLQueryItem(name: "q", value: "nebula")))
        #expect(result.nebulaQueryItem(named: "q")?.value == "nebula")
    }

    @Test func appendingQueryItemPreservesExisting() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1"))
        let result = try #require(base.nebulaAppending(queryItem: URLQueryItem(name: "b", value: "2")))
        #expect(result.nebulaQueryItem(named: "a")?.value == "1")
        #expect(result.nebulaQueryItem(named: "b")?.value == "2")
    }

    @Test func settingQueryItemReplacesSameName() throws {
        let base = try #require(URL(string: "https://example.com/p?lang=fr&lang=de"))
        let result = try #require(base.nebulaSettingQueryItem(URLQueryItem(name: "lang", value: "en")))
        // All same-name items collapse to one.
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: true))
        let langItems = components.queryItems?.filter { $0.name == "lang" } ?? []
        #expect(langItems.count == 1)
        #expect(langItems.first?.value == "en")
    }

    @Test func settingQueryItemAppendsWhenAbsent() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1"))
        let result = try #require(base.nebulaSettingQueryItem(URLQueryItem(name: "b", value: "2")))
        #expect(result.nebulaQueryItem(named: "a")?.value == "1")
        #expect(result.nebulaQueryItem(named: "b")?.value == "2")
    }

    @Test func removesQueryItemByName() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1&b=2&c=3"))
        let result = try #require(base.nebulaRemovingQueryItem(named: "b"))
        #expect(result.nebulaQueryItem(named: "b") == nil)
        #expect(result.nebulaQueryItem(named: "a")?.value == "1")
        #expect(result.nebulaQueryItem(named: "c")?.value == "3")
    }

    @Test func removeIsNoOpWhenAbsent() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1"))
        let result = try #require(base.nebulaRemovingQueryItem(named: "zzz"))
        #expect(result.nebulaQueryItem(named: "a")?.value == "1")
    }

    @Test func queryItemNamedReturnsFirstMatch() throws {
        let base = try #require(URL(string: "https://example.com/p?id=1&id=2"))
        #expect(base.nebulaQueryItem(named: "id")?.value == "1")
    }

    @Test func queryItemNamedReturnsNilWhenAbsent() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1"))
        #expect(base.nebulaQueryItem(named: "missing") == nil)
    }

    @Test func appendingQueryDictionaryIsSortedByKey() throws {
        let base = try #require(URL(string: "https://example.com/p"))
        let result = try #require(base.nebulaAppending(query: ["zeta": "1", "alpha": "2", "mike": "3"]))
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: true))
        let names = components.queryItems?.map(\.name) ?? []
        #expect(names == ["alpha", "mike", "zeta"])
    }

    @Test func appendingQueryItemsArray() throws {
        let base = try #require(URL(string: "https://example.com/p?a=1"))
        let result = try #require(base.nebulaAppendingQueryItems([
            URLQueryItem(name: "b", value: "2"),
            URLQueryItem(name: "c", value: "3")
        ]))
        #expect(result.nebulaQueryItem(named: "a")?.value == "1")
        #expect(result.nebulaQueryItem(named: "b")?.value == "2")
        #expect(result.nebulaQueryItem(named: "c")?.value == "3")
    }

    @Test func percentEncodesValuesWithSpecialChars() throws {
        let base = try #require(URL(string: "https://example.com/p"))
        let result = try #require(base.nebulaAppending(queryItem: URLQueryItem(name: "q", value: "hello world&co")))
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: true))
        // The decoded query item should round-trip the literal value.
        #expect(components.queryItems?.first?.value == "hello world&co")
    }
}

// MARK: - URL resolving

@Suite("URL.nebulaResolving")
struct URLResolvingTests {
    @Test func returnsSelfWhenBaseIsNil() throws {
        let url = try #require(URL(string: "https://example.com/p"))
        #expect(url.nebulaResolving(against: nil) == url)
    }

    @Test func resolvesRelativeAgainstBase() throws {
        let base = try #require(URL(string: "https://example.com/a/"))
        let relative = try #require(URL(string: "b?q=1", relativeTo: base))
        let resolved = try #require(relative.nebulaResolving(against: base))
        #expect(resolved.nebulaQueryItem(named: "q")?.value == "1")
    }
}

// MARK: - URLComponents fluent builders

@Suite("URLComponents.nebulaWith*")
struct URLComponentsBuildersTests {
    @Test func withQueryItemAppends() throws {
        var components = URLComponents(string: "https://example.com/p?a=1")!
        components = components.nebulaWith(queryItem: URLQueryItem(name: "b", value: "2"))
        let url = try #require(components.url)
        #expect(url.nebulaQueryItem(named: "a")?.value == "1")
        #expect(url.nebulaQueryItem(named: "b")?.value == "2")
    }

    @Test func withQueryItemsArrayAppends() throws {
        var components = URLComponents(string: "https://example.com/p")!
        components = components.nebulaWith(queryItems: [
            URLQueryItem(name: "a", value: "1"),
            URLQueryItem(name: "b", value: "2")
        ])
        let url = try #require(components.url)
        #expect(url.nebulaQueryItem(named: "a")?.value == "1")
        #expect(url.nebulaQueryItem(named: "b")?.value == "2")
    }

    @Test func settingQueryItemReplacesExisting() throws {
        var components = URLComponents(string: "https://example.com/p?lang=fr&lang=de")!
        components = components.nebulaSettingQueryItem(URLQueryItem(name: "lang", value: "en"))
        let url = try #require(components.url)
        let langItems = (URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? [])
            .filter { $0.name == "lang" }
        #expect(langItems.count == 1)
        #expect(langItems.first?.value == "en")
    }

    @Test func removingQueryItemByName() throws {
        var components = URLComponents(string: "https://example.com/p?a=1&b=2")!
        components = components.nebulaRemovingQueryItem(named: "b")
        let url = try #require(components.url)
        #expect(url.nebulaQueryItem(named: "a")?.value == "1")
        #expect(url.nebulaQueryItem(named: "b") == nil)
    }

    @Test func withQueryDictionarySortedByKey() throws {
        var components = URLComponents(string: "https://example.com/p")!
        components = components.nebulaWith(query: ["zeta": "1", "alpha": "2", "mike": "3"])
        let url = try #require(components.url)
        let resolved = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        let names = resolved.queryItems?.map(\.name) ?? []
        #expect(names == ["alpha", "mike", "zeta"])
    }

    @Test func buildersDoNotMutateReceiver() {
        let original = URLComponents(string: "https://example.com/p?a=1")!
        let originalItems = original.queryItems
        _ = original.nebulaWith(queryItem: URLQueryItem(name: "b", value: "2"))
        _ = original.nebulaWith(queryItems: [URLQueryItem(name: "c", value: "3")])
        _ = original.nebulaSettingQueryItem(URLQueryItem(name: "a", value: "99"))
        _ = original.nebulaRemovingQueryItem(named: "a")
        _ = original.nebulaWith(query: ["d": "4"])
        #expect(original.queryItems == originalItems)
    }
}