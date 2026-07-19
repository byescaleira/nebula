//
//  NebulaError+Mapping.swift
//  Nebula
//
//  Lossy mapping initializers from the common Apple error types and from
//  arbitrary `any Error`. The source existential is CONSUMED at construction
//  time (any Error is not Sendable, SE-0302); only Sendable fragments are kept.
//  See vault/01-fundamentos/nebula-errors.md.
//

import Foundation

extension NebulaError {
    // MARK: - NSError

    /// Maps an `NSError` lossily into a `NebulaError`.
    ///
    /// The domain/code become ``Code``; the `NSLocalized*` userInfo entries
    /// populate `message`/`failureReason`/`recoverySuggestion`/`helpAnchor`;
    /// remaining `String`-valued userInfo (excluding the consumed `NSLocalized*`
    /// and `NSUnderlyingErrorKey` keys) populate `metadata`; `kind` is inferred
    /// from the domain. `NSUnderlyingErrorKey` is wrapped as a single-level
    /// ``underlying`` (deep chains flatten to one level).
    public init(_ nsError: NSError) {
        let info = nsError.userInfo
        let message = (info[NSLocalizedDescriptionKey] as? String) ?? nsError.localizedDescription
        let failureReason = info[NSLocalizedFailureReasonErrorKey] as? String
        let recoverySuggestion = info[NSLocalizedRecoverySuggestionErrorKey] as? String
        let helpAnchor = info[NSHelpAnchorErrorKey] as? String

        let consumedKeys: Set<String> = [
            NSLocalizedDescriptionKey,
            NSLocalizedFailureReasonErrorKey,
            NSLocalizedRecoverySuggestionErrorKey,
            NSHelpAnchorErrorKey,
            NSUnderlyingErrorKey,
        ]
        var metadata: [String: String] = [:]
        for (key, value) in info where !consumedKeys.contains(key) {
            if let s = value as? String { metadata[key] = s }
        }

        var underlying: NebulaError.Box? = nil
        if let raw = info[NSUnderlyingErrorKey] as? Error {
            // Flatten to one level: the boxed error's own underlying is dropped.
            var inner = NebulaError(error: raw)
            inner.underlying = nil
            underlying = NebulaError.Box(inner)
        }

        self.init(
            code: NebulaError.Code(domain: nsError.domain, code: nsError.code),
            kind: NebulaError.kind(forDomain: nsError.domain),
            message: message,
            failureReason: failureReason,
            recoverySuggestions: recoverySuggestion.map { [$0] } ?? [],
            helpAnchor: helpAnchor,
            metadata: metadata,
            underlying: underlying
        )
    }

    // MARK: - DecodingError

    /// Maps a `DecodingError` lossily into a `NebulaError` with `kind = .decoding`.
    ///
    /// The coding path is stringified (`CodingKey` is not `Sendable`-portable
    /// across the envelope boundary) and stored in ``context``. The
    /// `underlyingError` from the decoding context is wrapped as a single-level
    /// ``underlying``.
    public init(decodingError: DecodingError) {
        let ctx: DecodingError.Context
        switch decodingError {
        case .typeMismatch(_, let c), .valueNotFound(_, let c),
             .keyNotFound(_, let c), .dataCorrupted(let c):
            ctx = c
        @unknown default:
            // Fall back to a synthesized context for future cases.
            self.init(
                code: NebulaError.Code(domain: "Swift.DecodingError", code: 0),
                kind: .decoding,
                message: decodingError.localizedDescription
            )
            return
        }
        var underlying: NebulaError.Box? = nil
        if let raw = ctx.underlyingError {
            var inner = NebulaError(error: raw)
            inner.underlying = nil
            underlying = NebulaError.Box(inner)
        }
        self.init(
            code: NebulaError.Code(domain: "Swift.DecodingError", code: 0),
            kind: .decoding,
            message: ctx.debugDescription.isEmpty
                ? decodingError.localizedDescription
                : "Decoding failed: \(ctx.debugDescription)",
            context: NebulaError.Context(
                codingPath: ctx.codingPath.map { $0.stringValue },
                debugDescription: ctx.debugDescription
            ),
            underlying: underlying
        )
    }

    // MARK: - URLError / CocoaError

    /// Maps a `URLError` lossily into a `NebulaError` with `kind = .network`.
    public init(urlError: URLError) {
        self.init(urlError as NSError)
        // The NSError init infers `kind` from the domain (NSURLErrorDomain →
        // .network); pin it explicitly so the intent is resilient to that
        // inference changing.
        self.kind = .network
    }

    /// Maps a `CocoaError` lossily into a `NebulaError` (`kind = .cocoa`).
    public init(cocoaError: CocoaError) {
        self.init(cocoaError as NSError)
        self.kind = .cocoa
    }

    // MARK: - any Error (dispatch)

    /// Maps an arbitrary `any Error` lossily into a `NebulaError`.
    ///
    /// Dispatches on the concrete type (`NebulaError` / `DecodingError` /
    /// `URLError` / `CocoaError` / `NSError`). The source existential is NOT
    /// retained — only `Sendable` fragments are kept. Consumers needing the
    /// original error must catch it before mapping.
    public init(error: any Error) {
        if let e = error as? NebulaError {
            self = e
        } else if let e = error as? DecodingError {
            self.init(decodingError: e)
        } else if let e = error as? EncodingError {
            // `EncodingError` bridges to `NSError` with domain
            // `NSCocoaErrorDomain` when thrown out of `JSONEncoder`, so the
            // NSError path below would misclassify it as `.cocoa`. Route it
            // through the Codable module's faithful mapping (`kind = .encoding`).
            self = NebulaError.encoding(e)
        } else if let e = error as? URLError {
            self.init(urlError: e)
        } else if let e = error as? CocoaError {
            self.init(cocoaError: e)
        } else {
            self.init(error as NSError)
        }
    }

    // MARK: - wrap

    /// Runs `body`, capturing any thrown error as a `NebulaError` in a `Result`.
    ///
    /// Uses `Result` losslessly (SE-0413 updated `Result.init(catching:)` to the
    /// typed-throws form). A thrown `NebulaError` is preserved as-is; any other
    /// `Error` is mapped lossily via ``init(error:)``.
    public static func wrap<T>(_ body: () throws -> T) -> Result<T, NebulaError> {
        do {
            return .success(try body())
        } catch let e as NebulaError {
            return .failure(e)
        } catch {
            return .failure(NebulaError(error: error))
        }
    }

    // MARK: - Kind inference

    /// Infers a ``Kind`` from an NSError domain string.
    private static func kind(forDomain domain: String) -> Kind {
        switch domain {
        case NSURLErrorDomain:    return .network
        case NSCocoaErrorDomain:   return .cocoa
        case "Swift.DecodingError": return .decoding
        case "Swift.EncodingError": return .encoding
        default:                   return .unknown
        }
    }
}