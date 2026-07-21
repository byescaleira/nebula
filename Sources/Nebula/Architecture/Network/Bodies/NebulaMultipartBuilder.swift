//
//  NebulaMultipartBuilder.swift
//  Nebula
//
//  Wave N17c — Bodies & downloads. A pure `multipart/form-data` (RFC 2388)
//  body composer: assembles `NebulaMultipartPart`s into a `Data` blob with a
//  random boundary, and writes the body to a temp file for streaming uploads
//  via `URLSession.upload(for:fromFile:)`. Foundation has NO multipart API (a
//  full grep of `Foundation.swiftinterface` for `multipart`/`form-data`/
//  `boundary` returns zero hits) — this is genuinely new app-layer code, not a
//  wrapper.
//
//  Gateway-compatible by design: the built `Data` + content-type feeds the
//  existing ``NebulaHTTPBody/data(_:contentType:)`` case (a raw body + a
//  content-type) — **no new ``NebulaHTTPBody`` case**, no
//  ``NebulaHTTPRequest`` / ``NebulaHTTPRequestParser`` ripple. The buffered
//  ``NebulaHTTPGateway`` (Wave N1) carries it unchanged:
//
//  ```swift
//  let body = NebulaMultipartBuilder()
//      .adding(.field(name: "title", value: "Nebula"))
//      .adding(.file(name: "upload", filename: "f.bin", contentType: "application/octet-stream", data: bytes))
//      .build()
//  let request = NebulaHTTPRequest.post("https://api.example.com/upload",
//                                       body: .data(body.data, contentType: body.contentType))
//  ```
//
//  Boundary generation reuses the N17a idiom: `Data.random(in:)` (Foundation)
//  + ``Data/nebulaHexEncodedString()`` → `"----NebulaBoundary<HEX>"`. No new
//  `import CryptoKit` (multipart doesn't hash; only
//  ``NebulaHashAlgorithm`` imports CryptoKit — the invariant is preserved).
//
//  `build()` is pure (no `URLSession`, no `@Sendable` closure, no I/O except
//  the explicit ``file(in:)`` writer). All public value types derive `Sendable`
//  from value-type fields (no `@unchecked`). All symbols are below the `.v26`
//  floor on every platform — **no `@available` gate**. `import Foundation` only.
//  See vault/03-padroes/nebula-bodies-downloads.md.
//

import Foundation

/// A single part of a `multipart/form-data` body (RFC 2388).
///
/// A form **field** carries a `name` + a `Data` value (no `filename`, no
/// `contentType`). A **file** part carries a `name` + `filename` + `contentType`
/// + `Data`. `Sendable`, `Equatable`, and `Hashable` are derived from the
/// value-type fields.
public struct NebulaMultipartPart: Sendable, Equatable, Hashable {

    /// The form field name.
    public let name: String

    /// The filename (file parts only; `nil` for form fields).
    public let filename: String?

    /// The part content-type (file parts only; `nil` for form fields — a form
    /// field has no `Content-Type` header per the common convention).
    public let contentType: String?

    /// The part body bytes.
    public let body: Data

    /// Creates a form field part (no filename, no content-type).
    public static func field(name: String, value: Data) -> NebulaMultipartPart {
        .init(name: name, filename: nil, contentType: nil, body: value)
    }

    /// Creates a form field part with a string value (UTF-8 encoded).
    public static func field(name: String, value: String) -> NebulaMultipartPart {
        .field(name: name, value: Data(value.utf8))
    }

    /// Creates a file part.
    public static func file(name: String, filename: String, contentType: String, data: Data) -> NebulaMultipartPart {
        .init(name: name, filename: filename, contentType: contentType, body: data)
    }

    /// Creates a part directly.
    public init(name: String, filename: String?, contentType: String?, body: Data) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.body = body
    }
}

/// The built `multipart/form-data` body: the encoded `Data` + the
/// `Content-Type` header value (carrying the boundary) + the boundary string.
///
/// Feed `data` into ``NebulaHTTPBody/data(_:contentType:)`` for a buffered
/// upload, or call ``file(in:)`` on the builder for a streaming
/// `URLSession.upload(for:fromFile:)`. `Sendable`, `Equatable`, and `Hashable`
/// are derived from the value-type fields.
public struct NebulaMultipartFormData: Sendable, Equatable, Hashable {

    /// The encoded multipart body bytes.
    public let data: Data

    /// The `Content-Type` header value: `multipart/form-data; boundary=<boundary>`.
    public let contentType: String

    /// The boundary string (without the `--` prefix).
    public let boundary: String

    /// Creates the built form data.
    public init(data: Data, contentType: String, boundary: String) {
        self.data = data
        self.contentType = contentType
        self.boundary = boundary
    }
}

/// A pure `multipart/form-data` (RFC 2388) body builder.
///
/// An immutable value type: ``adding(_:)`` returns a new builder (fluent), and
/// ``build()`` produces a ``NebulaMultipartFormData`` with no side effects. The
/// boundary auto-generates via `Data.random(in:)` + ``Data/nebulaHexEncodedString()``
/// when not supplied. `Sendable` and `Equatable` are derived (the stored `parts`
/// array + boundary string are value types).
///
/// ```swift
/// let form = NebulaMultipartBuilder()
///     .adding(.field(name: "title", value: "Nebula"))
///     .adding(.file(name: "upload", filename: "f.bin",
///                   contentType: "application/octet-stream", data: bytes))
///     .build()
/// let request = NebulaHTTPRequest.post(url, body: .data(form.data, contentType: form.contentType))
/// ```
public struct NebulaMultipartBuilder: Sendable, Equatable {

    /// The boundary prefix used by Nebula-generated boundaries.
    public static let boundaryPrefix = "----NebulaBoundary"

    /// The boundary string (without the `--` part-delimiter prefix).
    public let boundary: String

    /// The ordered parts.
    public let parts: [NebulaMultipartPart]

    /// Creates a builder. When `boundary` is `nil`, a random boundary is
    /// generated from 16 random bytes hex-encoded under ``boundaryPrefix``
    /// (RFC 2046 §5.1.1 boundaries are 0–70 chars; a 16-byte hex string is 32
    /// chars + the 18-char prefix = 50 chars — within the limit).
    public init(boundary: String? = nil, parts: [NebulaMultipartPart] = []) {
        self.boundary = boundary ?? NebulaMultipartBuilder.generateBoundary()
        self.parts = parts
    }

    /// Returns a new builder with `part` appended (fluent — value semantics).
    public func adding(_ part: NebulaMultipartPart) -> NebulaMultipartBuilder {
        .init(boundary: boundary, parts: parts + [part])
    }

    /// Builds the `multipart/form-data` body. Pure — no `URLSession`, no I/O.
    ///
    /// Each part is encoded as:
    /// `--<boundary>\r\n`
    /// `Content-Disposition: form-data; name="<name>"`[`; filename="<filename>"`]
    ///   [`Content-Type: <contentType>`]`\r\n\r\n`
    /// `<body>\r\n`
    /// then the closing `--<boundary>--\r\n`.
    public func build() -> NebulaMultipartFormData {
        var data = Data()
        // Local helper — `Data` has no `append(String)`; encode UTF-8 per segment.
        func append(_ string: String) { data.append(Data(string.utf8)) }
        for part in parts {
            append("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            append("\(disposition)\r\n")
            if let contentType = part.contentType {
                append("Content-Type: \(contentType)\r\n")
            }
            append("\r\n")
            data.append(part.body)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        let contentType = "multipart/form-data; boundary=\(boundary)"
        return NebulaMultipartFormData(data: data, contentType: contentType, boundary: boundary)
    }

    /// Writes the built body to a temp file and returns its URL — for streaming
    /// uploads via `URLSession.upload(for:fromFile:)` (a file body streams from
    /// disk and is suitable for large/background uploads, unlike the in-memory
    /// `URLSession.upload(for:from:)`). The caller owns the file's lifetime
    /// (delete it when the upload completes). Pass `directory` to control the
    /// location (default: `FileManager.default.temporaryDirectory`). Throws a
    /// ``NebulaMultipartError`` (`.ioFailed`) wrapping the filesystem error.
    public func file(in directory: URL? = nil) throws -> URL {
        let form = build()
        let dir = directory ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("NebulaMultipart-\(boundary).bin")
        do {
            try form.data.write(to: url, options: .atomic)
        } catch {
            let box = NebulaError.Box(NebulaError(error: error))
            throw NebulaMultipartError.ioFailed(
                "Multipart temp-file write failed: \(error.localizedDescription)",
                underlying: box)
        }
        return url
    }

    /// Generates a random boundary: 16 random bytes hex-encoded under
    /// ``boundaryPrefix``.
    private static func generateBoundary() -> String {
        let random = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return Self.boundaryPrefix + random.nebulaHexEncodedString()
    }
}