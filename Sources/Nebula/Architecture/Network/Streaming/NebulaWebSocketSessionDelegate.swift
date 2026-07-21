//
//  NebulaWebSocketSessionDelegate.swift
//  Nebula
//
//  Wave N17b — Streaming. The combined `URLSession` delegate for a pinned
//  WebSocket session: ONE object per session that does SSL/TLS pinning (via
//  composition with the N17a ``NebulaURLSessionDelegate``) AND surfaces the
//  WebSocket lifecycle callbacks (`didOpenWithProtocol` / `didCloseWithCode`).
//
//  `final class : NSObject, URLSessionWebSocketDelegate, Sendable`. `Sendable`
//  is **derived** — all stored props are immutable `let`s of `Sendable` type
//  (`NebulaURLSessionDelegate` derives `Sendable`; `NebulaLogger?` is `Sendable`;
//  the `@Sendable` closures are `Sendable`). NO `@unchecked`. This matches the
//  ``NebulaUNNotificationCenter`` precedent (`final class : NSObject,
//  UNUserNotificationCenterDelegate, Sendable`, derived) — `URLSessionWebSocketDelegate`
//  is an `@objc` protocol NOT annotated `NS_SWIFT_SENDABLE`, but conformance to
//  a non-`NS_SWIFT_SENDABLE` `@objc` protocol does NOT block derived `Sendable`
//  on a `final class` whose only stored props are immutable `let`s of `Sendable`
//  type. Probed against the Xcode 27 Beta 3 SDK with
//  `swiftc -typecheck -swift-version 6 -strict-concurrency=complete
//  -warnings-as-errors` → EXIT=0, zero warnings. See
//  vault/03-padroes/nebula-streaming.md.
//
//  NSObject base: `URLSessionWebSocketDelegate` is an `@objc` protocol with
//  `@objc optional` methods, so the conforming class must be Obj-C-runtime-
//  dispatched — the ``NebulaUNNotificationCenter`` / ``NebulaURLSessionDelegate``
//  precedent establishes NSObject for `@objc` delegate protocols in Nebula.
//
//  Pinning reuse: the auth-challenge method **forwards** to the held
//  ``NebulaURLSessionDelegate`` (the N17a delegate) — `pinningDelegate.urlSession(…)`
//  is `public` and callable directly. Zero N17a source change, zero pinning-
//  logic duplication. No `import Security` here — the `Sec*` evaluation lives in
//  the N17a delegate; this class only forwards the call.
//

import Foundation

/// A `final class : NSObject, URLSessionWebSocketDelegate, Sendable` that
/// combines SSL/TLS pinning (via composition with ``NebulaURLSessionDelegate``)
/// and the WebSocket lifecycle callbacks (`didOpenWithProtocol` /
/// `didCloseWithCode`).
///
/// Attach it to a `URLSession` via `URLSession(configuration:delegate:delegateQueue:)`
/// — or use the ``NebulaWebSocketSession/pinned(by:configuration:logger:onOpen:onClose:)``
/// builder, which returns a ``NebulaPinnedWebSocketSession`` carrying both the
/// session and this delegate (the caller must retain the delegate:
/// `URLSession` does NOT strongly retain its delegate — the
/// ``NebulaURLSessionWebSocket`` façade holds the pinned session for this
/// reason).
public final class NebulaWebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {

    /// The N17a pinning delegate — handles server-trust challenges. The
    /// `urlSession(_:didReceive:completionHandler:)` method forwards to it.
    public let pinningDelegate: NebulaURLSessionDelegate

    /// An optional logger for WebSocket lifecycle diagnostics (`nil` = silent).
    public let logger: NebulaLogger?

    /// Called when the WebSocket opens (with the negotiated subprotocol, or
    /// `nil`).
    public let onOpen: @Sendable (String?) -> Void

    /// Called when the WebSocket closes (with the close code + optional reason).
    public let onClose: @Sendable (URLSessionWebSocketTask.CloseCode, Data?) -> Void

    /// Creates the delegate.
    public init(
        pinningDelegate: NebulaURLSessionDelegate,
        logger: NebulaLogger? = nil,
        onOpen: @escaping @Sendable (String?) -> Void = { _ in },
        onClose: @escaping @Sendable (URLSessionWebSocketTask.CloseCode, Data?) -> Void = { _, _ in }
    ) {
        self.pinningDelegate = pinningDelegate
        self.logger = logger
        self.onOpen = onOpen
        self.onClose = onClose
        super.init()
    }

    // MARK: - URLSessionDelegate (pinning — forwarded to the N17a delegate)

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Forward to the N17a pinning delegate — zero pinning-logic duplication.
        pinningDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    // MARK: - URLSessionWebSocketDelegate (lifecycle)

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolName: String?
    ) {
        logger?.debug("WebSocket opened\(protocolName.map { " (\($0))" } ?? "")")
        onOpen(protocolName)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        logger?.debug("WebSocket closed: code \(closeCode.rawValue)")
        onClose(closeCode, reason)
    }
}