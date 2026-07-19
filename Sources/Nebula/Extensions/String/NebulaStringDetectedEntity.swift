//
//  NebulaStringDetectedEntity.swift
//  Nebula
//
//  Sendable extraction of `NSDataDetector` results. `NSDataDetector` and
//  `NSTextCheckingResult` are Objective-C classes (NOT in the textual
//  `.swiftinterface`; source of truth is `NSRegularExpression.h` /
//  `NSTextCheckingResult.h` in the SDK, `API_AVAILABLE(macos(10.7), ios(4.0),
//  watchos(2.0), tvos(9.0))` — all below the .v26 floor). They are not
//  `Sendable`, so results are consumed immediately into these Sendable
//  value types. See vault/01-fundamentos/nebula-string-extensions.md.
//

import Foundation

/// Address components extracted by `NSDataDetector` for an
/// `NSTextCheckingTypeAddress` match.
///
/// Mirrors the Swift `NSTextCheckingKey` members (`.name`, `.jobTitle`,
/// `.organization`, `.street`, `.city`, `.state`, `.zip`, `.country`,
/// `.phone`) read from `NSTextCheckingResult.components`. Sendable by derived
/// conformance — every field is `String?`.
public struct NebulaStringAddressComponents: Sendable, Equatable {
    /// The recipient name, if detected.
    public let name: String?
    /// The job title, if detected.
    public let jobTitle: String?
    /// The organization, if detected.
    public let organization: String?
    /// The street address, if detected.
    public let street: String?
    /// The city, if detected.
    public let city: String?
    /// The state / region, if detected.
    public let state: String?
    /// The postal / ZIP code, if detected.
    public let zip: String?
    /// The country, if detected.
    public let country: String?
    /// The phone number associated with the address, if detected.
    public let phone: String?

    /// Creates address components.
    public init(
        name: String? = nil,
        jobTitle: String? = nil,
        organization: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        country: String? = nil,
        phone: String? = nil
    ) {
        self.name = name
        self.jobTitle = jobTitle
        self.organization = organization
        self.street = street
        self.city = city
        self.state = state
        self.zip = zip
        self.country = country
        self.phone = phone
    }
}

/// A `Sendable` entity extracted from natural-language text by
/// `NSDataDetector`.
///
/// Per Apple's `NSRegularExpression.h` guidance, `NSDataDetector` is for
/// **natural-language detection, NOT validation** — it discards uncertain
/// matches. To validate a candidate (e.g. a URL), use the type's own
/// failable initializer (`URL(string:)`). This enum carries only the
/// `Sendable` fragments of an `NSTextCheckingResult`; the non-`Sendable`
/// Foundation class is consumed at construction time and never retained.
public enum NebulaStringDetectedEntity: Sendable {
    /// A detected URL/link.
    case link(URL)
    /// A detected phone number (as the matched substring).
    case phoneNumber(String)
    /// A detected date with optional time zone and duration (seconds).
    case date(Date, timeZone: TimeZone?, duration: TimeInterval)
    /// A detected mailing address.
    case address(NebulaStringAddressComponents)
    /// Detected transit information (e.g. flight number), as the matched
    /// substring.
    case transitInformation(String)

    /// Builds a ``NebulaStringDetectedEntity`` from an `NSTextCheckingResult`,
    /// or `nil` for result types Nebula does not surface (orthography,
    /// spelling, grammar, quotes, dashes, replacements, corrections, raw
    /// regular-expression matches).
    ///
    /// The non-`Sendable` `result` is consumed here and never escapes; only
    /// `Sendable` fragments (URL, String, Date, TimeZone, TimeInterval,
    /// address components) are retained.
    ///
    /// - Parameters:
    ///   - result: The `NSTextCheckingResult` produced by `NSDataDetector`.
    ///   - source: The `NSString` the detector ran against, used to recover
    ///     matched substrings for phone/transit results.
    internal init?(result: NSTextCheckingResult, in source: NSString) {
        switch result.resultType {
        case .link:
            guard let url = result.url else { return nil }
            self = .link(url)
        case .phoneNumber:
            let phone = result.phoneNumber ?? source.substring(with: result.range)
            self = .phoneNumber(phone)
        case .date:
            let date = result.date ?? Date(timeIntervalSince1970: 0)
            self = .date(date, timeZone: result.timeZone, duration: result.duration)
        case .address:
            let components = result.components
            let address = NebulaStringAddressComponents(
                name: components?[.name],
                jobTitle: components?[.jobTitle],
                organization: components?[.organization],
                street: components?[.street],
                city: components?[.city],
                state: components?[.state],
                zip: components?[.zip],
                country: components?[.country],
                phone: components?[.phone]
            )
            self = .address(address)
        case .transitInformation:
            self = .transitInformation(source.substring(with: result.range))
        default:
            return nil
        }
    }
}