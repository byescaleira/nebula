//
//  StringExtensionsTests.swift
//  NebulaTests
//
//  String module extension tests (Swift Testing).
//

import Testing
import Foundation
import RegexBuilder
import Nebula

@Suite("String blank/trim/nilify")
struct StringBlankTests {
    @Test func isBlank() {
        #expect("".isBlank)
        #expect("   ".isBlank)
        #expect("\t\n ".isBlank)
        #expect(!"x".isBlank)
        #expect(!" x ".isBlank)
        #expect(!"a b".isBlank)
    }

    @Test func trimmed() {
        #expect("  hi  ".trimmed == "hi")
        #expect("\n\thi\t\n".trimmed == "hi")
        #expect("hi".trimmed == "hi")
        #expect("".trimmed == "")
        #expect("   ".trimmed == "")
    }

    @Test func nilIfEmpty() {
        #expect("".nilIfEmpty() == nil)
        #expect("x".nilIfEmpty() == "x")
        #expect(" ".nilIfEmpty() == " ")      // not blank-aware
        #expect("abc".nilIfEmpty() == "abc")
    }

    @Test func nilIfBlank() {
        #expect("".nilIfBlank() == nil)
        #expect("   ".nilIfBlank() == nil)
        #expect("\n".nilIfBlank() == nil)
        #expect("x".nilIfBlank() == "x")
        #expect(" x ".nilIfBlank() == " x ")
    }
}

@Suite("String.truncated")
struct StringTruncateTests {
    @Test func shorterThanMaxIsUntouched() {
        #expect("abc".truncated(to: 10) == "abc")
        #expect("abc".truncated(to: 3) == "abc")
    }

    @Test func truncatesWithEllipsis() {
        // The ellipsis counts toward maxLength: keep = maxLength - ellipsis.count.
        #expect("abcdef".truncated(to: 5) == "abcd…")
        #expect("abcdef".truncated(to: 5, with: "...") == "ab...")
    }

    @Test func noEllipsisHardCut() {
        #expect("abcdef".truncated(to: 3, with: nil) == "abc")
    }

    @Test func ellipsisLongerThanMax() {
        // maxLength (3) <= ellipsis.count (4): ellipsis itself is truncated to 3.
        #expect("abcdef".truncated(to: 3, with: "....") == "...")
    }

    @Test func maxLengthZero() {
        #expect("abc".truncated(to: 0) == "")
        #expect("abc".truncated(to: 0, with: nil) == "")
    }

    @Test func graphemeClusterSafe() {
        // "é" is one Character (one grapheme cluster) but multiple UTF-16 units.
        let s = "ééééé"     // 5 Characters
        // maxLength 3, ellipsis 1 → keep 2 graphemes + "…".
        #expect(s.truncated(to: 3) == "éé…")
        #expect(s.truncated(to: 3, with: nil) == "ééé")
    }
}

@Suite("String case conversion")
struct StringCaseTests {
    @Test func snakeFromCamelAndKebab() {
        #expect("camelCaseThing".snakeCased() == "camel_case_thing")
        #expect("kebab-case-thing".snakeCased() == "kebab_case_thing")
        #expect("PascalCaseThing".snakeCased() == "pascal_case_thing")
        #expect("XMLParser".snakeCased() == "xml_parser")
        #expect("already_snake".snakeCased() == "already_snake")
        #expect("".snakeCased() == "")
    }

    @Test func kebabFromCamelAndSnake() {
        #expect("camelCaseThing".kebabCased() == "camel-case-thing")
        #expect("snake_case_thing".kebabCased() == "snake-case-thing")
        #expect("XMLParser".kebabCased() == "xml-parser")
        #expect("".kebabCased() == "")
    }

    @Test func camelFromSnakeAndKebab() {
        #expect("snake_case_thing".camelCased() == "snakeCaseThing")
        #expect("kebab-case-thing".camelCased() == "kebabCaseThing")
        #expect("PascalCaseThing".camelCased() == "pascalCaseThing")
        #expect("XMLParser".camelCased() == "xmlParser")
        #expect("".camelCased() == "")
    }

    @Test func handlesSpacesAndDigits() {
        #expect("hello world".snakeCased() == "hello_world")
        #expect("v2 release notes".camelCased() == "v2ReleaseNotes")
        #expect("section 4 title".kebabCased() == "section-4-title")
    }
}

@Suite("String base64")
struct StringBase64Tests {
    @Test func roundTrip() throws {
        let s = "Hello, Nebula! 🚀"
        let encoded = s.base64EncodedString()
        let decoded = String(base64Encoded: encoded)
        #expect(decoded == s)
    }

    @Test func emptyString() {
        #expect("".base64EncodedString() == "")
        #expect(String(base64Encoded: "") == "")
    }

    @Test func invalidBase64ReturnsNil() {
        #expect(String(base64Encoded: "!!! not base64 !!!") == nil)
    }

    @Test func nonUTF8ReturnsNil() {
        // 0xFF is a single byte that's invalid UTF-8 but valid base64 alphabet
        // only if the decoded bytes aren't UTF-8. Encode a raw byte string via
        // Data to produce base64 of non-UTF-8 bytes.
        let nonUTF8 = Data([0xFF, 0xFE, 0xFD])
        let b64 = nonUTF8.base64EncodedString()
        #expect(String(base64Encoded: b64) == nil)
    }

    @Test func base64URLOptionsAvailableSinceNebula26_4() {
        // Standard base64 contains '+'/'/'/'='; URL-alphabet replaces those.
        let s = "??>>=="
        let standard = s.base64EncodedString()
        #expect(standard.contains("+") || standard.contains("/") || standard.contains("="))

        if #available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) {
            let url = s.base64EncodedString(options: [.base64URLAlphabet, .omitPaddingCharacter])
            #expect(!url.contains("+"))
            #expect(!url.contains("/"))
            #expect(!url.contains("="))
        }
    }
}

@Suite("String hex codec")
struct StringHexTests {
    @Test func roundTrip() {
        let s = "Hello, Nebula! 🚀"
        let hex = s.hexEncodedString()
        #expect(String(hexEncoded: hex) == s)
    }

    @Test func emptyString() {
        #expect("".hexEncodedString() == "")
        #expect(String(hexEncoded: "") == "")
    }

    @Test func knownValue() {
        // "Ab" -> 0x41 0x62
        #expect("Ab".hexEncodedString() == "4162")
        // "\n" (0x0a) exercises a hex letter.
        #expect("\n".hexEncodedString() == "0a")
    }

    @Test func upperCaseOption() {
        #expect("\n".hexEncodedString(options: .upperCase) == "0A")
    }

    @Test func prefix0xOption() {
        #expect("\n".hexEncodedString(options: .prefix0x) == "0x0a")
        #expect("\n".hexEncodedString(options: [.upperCase, .prefix0x]) == "0x0A")
    }

    @Test func accepts0xPrefixAndCase() {
        #expect(String(hexEncoded: "0x4162") == "Ab")
        #expect(String(hexEncoded: "0X4162") == "Ab")
        #expect(String(hexEncoded: "4162") == "Ab")
        #expect(String(hexEncoded: "416B") == "Ak")
    }

    @Test func oddLengthReturnsNil() {
        #expect(String(hexEncoded: "416") == nil)
    }

    @Test func nonHexReturnsNil() {
        #expect(String(hexEncoded: "zzzz") == nil)
    }

    @Test func nonUTF8BytesReturnNil() {
        #expect(String(hexEncoded: "fffe") == nil)   // 0xFF 0xFE is invalid UTF-8
    }

    @Test func dataRoundTrip() {
        // hex is over UTF-8 bytes; the underlying bytes equal the original.
        let s = "abc"
        let bytes = Array(s.utf8)
        let hex = s.hexEncodedString()
        var decoded = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            decoded.append(UInt8(hex[idx..<next], radix: 16)!)
            idx = next
        }
        #expect(decoded == bytes)
    }
}

@Suite("NSDataDetector wrappers")
struct StringDetectionTests {
    @Test func urlsExtractedFromText() throws {
        let text = "Visit https://example.com today"
        let urls = try text.urls()
        #expect(urls.count == 1)
        #expect(urls.first?.absoluteString == "https://example.com")
    }

    @Test func firstURLReturnsNilWhenAbsent() throws {
        #expect(try "no links here".firstURL() == nil)
    }

    @Test func firstURLConvenience() throws {
        let text = "see http://alpha.example.com and https://beta.example.com"
        #expect(try text.firstURL()?.absoluteString == "http://alpha.example.com")
        #expect(try text.urls().count == 2)
    }

    @Test func dataDetectedEntitiesLinkAndDate() throws {
        let text = "Meet on March 5 2025 at https://example.com"
        let entities = try text.dataDetectedEntities(types: [.link, .date])
        // At least one link and one date; order matches appearance.
        let hasLink = entities.contains { if case .link = $0 { return true }; return false }
        let hasDate = entities.contains { if case .date = $0 { return true }; return false }
        #expect(hasLink)
        #expect(hasDate)
    }

    @Test func linkEntityCarriesURL() throws {
        let text = "see https://example.com"
        let entities = try text.dataDetectedEntities(types: .link)
        guard case .link(let url)? = entities.first else {
            Issue.record("expected a .link entity")
            return
        }
        #expect(url.absoluteString == "https://example.com")
    }

    @Test func dateEntityCarriesDate() throws {
        let text = "March 5 2025"
        let entities = try text.dataDetectedEntities(types: .date)
        guard case .date(let d, let tz, _)? = entities.first else {
            Issue.record("expected a .date entity")
            return
        }
        // Use the detector's own time zone so the calendar day is stable
        // regardless of the host's local zone.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz ?? .current
        let comps = cal.dateComponents([.year, .month, .day], from: d)
        #expect(comps.year == 2025)
        #expect(comps.month == 3)
        #expect(comps.day == 5)
    }
}

@Suite("NebulaRegex wrapper")
struct NebulaRegexTests {
    @Test func firstMatch() {
        let r = NebulaRegex(NebulaRegexPatterns.uuid)
        let input = "id=12345678-1234-1234-1234-123456789012 trailing"
        let m = r.firstMatch(in: input)
        #expect(m != nil)
        #expect(String(m!.output) == "12345678-1234-1234-1234-123456789012")
    }

    @Test func wholeMatch() {
        let r = NebulaRegex(NebulaRegexPatterns.uuid)
        #expect(r.wholeMatch("12345678-1234-1234-1234-123456789012") != nil)
        #expect(r.wholeMatch("not a uuid") == nil)
    }

    @Test func matchesAllOccurrences() {
        let r = NebulaRegex(/#fff|#000/)
        let input = "bg #fff text #000 done"
        #expect(r.matches(in: input).count == 2)
    }

    @Test func contains() {
        let r = NebulaRegex(/Nebula/)
        #expect(r.contains("hello Nebula!"))
        #expect(!r.contains("hello Cosmos!"))
    }

    @Test func builderInit() {
        let r = NebulaRegex { /\d+/ }
        #expect(r.wholeMatch("12345") != nil)
        #expect(r.wholeMatch("12a45") == nil)
    }
}

@Suite("NebulaRegexPatterns")
struct NebulaRegexPatternsTests {
    @Test func uuid() {
        #expect("12345678-1234-1234-1234-123456789012".wholeMatch(of: NebulaRegexPatterns.uuid) != nil)
        #expect("ABCDEF12-1234-1234-1234-123456789012".wholeMatch(of: NebulaRegexPatterns.uuid) != nil)
        #expect("not-a-uuid".wholeMatch(of: NebulaRegexPatterns.uuid) == nil)
    }

    @Test func ipv4() {
        #expect("192.168.0.1".wholeMatch(of: NebulaRegexPatterns.ipv4) != nil)
        #expect("10.0.0.1".wholeMatch(of: NebulaRegexPatterns.ipv4) != nil)
        #expect("999.999.999.999".wholeMatch(of: NebulaRegexPatterns.ipv4) != nil) // shape-only
        #expect("no ip here".wholeMatch(of: NebulaRegexPatterns.ipv4) == nil)
    }

    @Test func hexColor() {
        #expect("#fff".wholeMatch(of: NebulaRegexPatterns.hexColor) != nil)
        #expect("#FFAABB".wholeMatch(of: NebulaRegexPatterns.hexColor) != nil)
        #expect("#12".wholeMatch(of: NebulaRegexPatterns.hexColor) == nil)
        #expect("fff".wholeMatch(of: NebulaRegexPatterns.hexColor) == nil)
    }

    @Test func semver() {
        #expect("1.2.3".wholeMatch(of: NebulaRegexPatterns.semver) != nil)
        #expect("0.0.0".wholeMatch(of: NebulaRegexPatterns.semver) != nil)
        #expect("1.2".wholeMatch(of: NebulaRegexPatterns.semver) == nil)
    }

    @Test func iso8601() {
        #expect("2025-03-05T12:30:00Z".wholeMatch(of: NebulaRegexPatterns.iso8601) != nil)
        #expect("2025-03-05T12:30:00.123-08:00".wholeMatch(of: NebulaRegexPatterns.iso8601) != nil)
        #expect("2025-03-05".wholeMatch(of: NebulaRegexPatterns.iso8601) == nil)
    }
}

@Suite("NebulaStringLocalization")
struct NebulaStringLocalizationTests {
    @Test func defaultContract() {
        let l = NebulaStringLocalization.default
        #expect(l.bundle == nil)
        #expect(l.locale == nil)
        #expect(l.table == "Localizable")
    }

    @Test func stringReturnsKeyFallbackWhenNoCatalog() {
        // With no Localizable catalog in the test target, the key itself is
        // the standard Apple fallback.
        let key: String.LocalizationValue = "nebula.test.missing.key"
        let resolved = NebulaStringLocalization.default.string(key)
        #expect(resolved == "nebula.test.missing.key")
    }

    @Test func attributedReturnsAttributedString() {
        let key: String.LocalizationValue = "nebula.test.missing.key"
        let resolved = NebulaStringLocalization.default.attributed(key)
        #expect(String(resolved.characters) == "nebula.test.missing.key")
    }

    @Test func customContractRoundTripsFields() {
        let l = NebulaStringLocalization(bundle: .main, locale: Locale(identifier: "en_US"), table: "MyTable")
        #expect(l.table == "MyTable")
        #expect(l.locale?.identifier == "en_US")
        #expect(l.bundle == .main)
    }
}