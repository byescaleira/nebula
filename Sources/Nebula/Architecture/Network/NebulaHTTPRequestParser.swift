//
//  NebulaHTTPRequestParser.swift
//  Nebula
//
//  Wave N7 — Network. An internal, bounded HTTP/1.1 request parser: request
//  line + headers + a `Content-Length`-bounded body, hand-rolled (no
//  third-party dep). Returns the same ``NebulaHTTPRequest`` value type the
//  client uses, so the server-side parsed request and the client-side built
//  request share one shape. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//
//  Scope = "simple": plain HTTP/1.1, no chunked transfer-encoding, no
//  keep-alive, `Content-Length` bodies only.
//

import Foundation

/// A bounded HTTP/1.1 request parser.
///
/// Parses a complete request (request line, headers, and a `Content-Length`
/// body) from an accumulated `Data` buffer into a ``NebulaHTTPRequest``. Returns
/// `nil` when the buffer does not yet contain a complete request (the caller
/// reads more and retries); throws ``NebulaHTTPServerError/parseFailed(_:)`` on
/// malformed input. Plain HTTP/1.1 only — no chunked transfer-encoding, no
/// keep-alive, `Content-Length` bodies only.
enum NebulaHTTPRequestParser {

    /// The maximum accepted request body size (10 MiB). A `Content-Length`
    /// above this is rejected as a parse failure (bounded bodies only).
    static let maxBodyLength = 10 * 1024 * 1024

    /// Parses a complete HTTP/1.1 request from `data`.
    ///
    /// - Returns: A ``NebulaHTTPRequest`` once the full request line, headers,
    ///   and `Content-Length` body are present; `nil` when more bytes are
    ///   needed (the caller should read again and retry).
    /// - Throws: ``NebulaHTTPServerError/parseFailed(_:)`` on malformed input.
    static func parse(_ data: Data) throws -> NebulaHTTPRequest? {
        // 1. Locate the end of the headers (\r\n\r\n). Not present yet → need
        //    more bytes.
        guard let headerEnd = findHeaderTerminator(in: data) else { return nil }
        let bodyStart = headerEnd + 4
        guard let head = String(data: data.subdata(in: 0..<headerEnd), encoding: .utf8) else {
            throw NebulaHTTPServerError.parseFailed("Non-UTF-8 request head")
        }

        // 2. Request line: "METHOD SP REQUEST-TARGET SP HTTP-VERSION".
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, requestLine.isEmpty == false else {
            throw NebulaHTTPServerError.parseFailed("Empty request line")
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            throw NebulaHTTPServerError.parseFailed("Malformed request line: \(requestLine)")
        }
        guard let method = NebulaHTTPMethod(rawValue: parts[0]) else {
            throw NebulaHTTPServerError.parseFailed("Unsupported method: \(parts[0])")
        }

        // 3. Headers (case-insensitive Content-Length lookup). Header name case
        //    is preserved as received.
        var headers: [String: String] = [:]
        var contentLength = 0
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
            if name.lowercased() == "content-length" {
                // Reject malformed Content-Length (non-numeric, negative, or
                // oversized) up front: a negative value would otherwise build a
                // reversed `Range` in `subdata(in:)` and trap the process, and an
                // absurd value would have the server wait forever for a body that
                // never arrives. Bounded `Content-Length` bodies only.
                guard let length = Int(value), length >= 0, length <= NebulaHTTPRequestParser.maxBodyLength else {
                    throw NebulaHTTPServerError.parseFailed("Invalid Content-Length: \(value)")
                }
                contentLength = length
            }
        }

        // 4. Wait until the full body is present.
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        // 5. Split the request target into path + query.
        let target = parts[1]
        var path = target
        var query: [URLQueryItem] = []
        if let question = target.firstIndex(of: "?") {
            path = String(target[..<question])
            let queryString = String(target[target.index(after: question)...])
            // URLComponents parses query items off a synthetic absolute path.
            if let comps = URLComponents(string: "/?" + queryString) {
                query = comps.queryItems ?? []
            }
        }

        // 6. Build the request (the same value type the client builds).
        let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value
        let bodyValue: NebulaHTTPBody = body.isEmpty
            ? .none
            : .data(body, contentType: contentType ?? "application/octet-stream")
        return NebulaHTTPRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: bodyValue
        )
    }

    /// Finds the offset of the `\r\n\r\n` header terminator in `data`, or `nil`.
    static func findHeaderTerminator(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        for index in 0...(data.count - 4) {
            if data[index] == 0x0D && data[index + 1] == 0x0A
                && data[index + 2] == 0x0D && data[index + 3] == 0x0A {
                return index
            }
        }
        return nil
    }
}