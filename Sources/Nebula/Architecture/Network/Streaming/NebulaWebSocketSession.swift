//
//  NebulaWebSocketSession.swift
//  Nebula
//
//  Wave N17b — Streaming. The pinned WebSocket-session builder: a tiny `enum`
//  namespace + a `Sendable` value carrying the constructed `URLSession` and its
//  ``NebulaWebSocketSessionDelegate``. The caller composes a pinned WebSocket
//  client with zero gateway changes:
//
//  ```swift
//  let ws = NebulaWebSocketSession.open(
//      url: URL(string: "wss://api.test/events")!,
//      using: NebulaWebSocketSession.pinned(by: policy))
//  ```
//
//  Ownership: `URLSession` does NOT strongly retain its delegate, so the
//  ``NebulaURLSessionWebSocket`` façade holds the ``NebulaPinnedWebSocketSession``
//  (session + delegate) — retaining the façade retains everything. No
//  process-wide accessor (pinning is per-session, unlike logging/measurement).
//
//  Foundation-only here — the `Sec*` evaluation lives in the N17a delegate
//  composed via ``NebulaURLSessionDelegate``. See
//  vault/03-padroes/nebula-streaming.md.
//

import Foundation

/// A `URLSession` paired with the ``NebulaWebSocketSessionDelegate`` that owns
/// its pinning evaluation + WebSocket lifecycle.
///
/// `Sendable` is derived — both fields are `Sendable` (`URLSession` is
/// `Sendable`; the delegate derives `Sendable`). The ``NebulaURLSessionWebSocket``
/// façade retains this value so the delegate is not silently dropped
/// (`URLSession` does NOT strongly retain its delegate).
public struct NebulaPinnedWebSocketSession: Sendable {

    /// The pinned `URLSession`.
    public let session: URLSession

    /// The delegate evaluating server trust + surfacing WebSocket lifecycle.
    public let delegate: NebulaWebSocketSessionDelegate

    /// Creates the pair.
    public init(session: URLSession, delegate: NebulaWebSocketSessionDelegate) {
        self.session = session
        self.delegate = delegate
    }
}

/// Convenience builders for pinned WebSocket sessions + clients.
public enum NebulaWebSocketSession {

    /// Creates a `URLSession` whose delegate evaluates server trust against
    /// `pinning` (via the N17a ``NebulaURLSessionDelegate``) and surfaces the
    /// WebSocket lifecycle, returning the session and delegate together as a
    /// ``NebulaPinnedWebSocketSession``.
    ///
    /// - Parameters:
    ///   - pinning: the pinning policy.
    ///   - configuration: the session configuration (default `.ephemeral`).
    ///   - logger: an optional logger for pinning + lifecycle diagnostics.
    ///   - onOpen: called when the WebSocket opens (subprotocol or `nil`).
    ///   - onClose: called when the WebSocket closes (close code + reason).
    public static func pinned(
        by pinning: NebulaSSLPinning,
        configuration: URLSessionConfiguration = .ephemeral,
        logger: NebulaLogger? = nil,
        onOpen: @escaping @Sendable (String?) -> Void = { _ in },
        onClose: @escaping @Sendable (URLSessionWebSocketTask.CloseCode, Data?) -> Void = { _, _ in }
    ) -> NebulaPinnedWebSocketSession {
        let pinningDelegate = NebulaURLSessionDelegate(pinning: pinning, logger: logger)
        let delegate = NebulaWebSocketSessionDelegate(
            pinningDelegate: pinningDelegate, logger: logger, onOpen: onOpen, onClose: onClose)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return NebulaPinnedWebSocketSession(session: session, delegate: delegate)
    }

    /// Opens a WebSocket client to `url` (optionally with subprotocols) on the
    /// pinned session, returning a ``NebulaURLSessionWebSocket`` façade that
    /// retains the pinned session.
    public static func open(
        url: URL,
        protocols: [String] = [],
        using pinned: NebulaPinnedWebSocketSession,
        logger: NebulaLogger? = nil
    ) -> NebulaURLSessionWebSocket {
        let task = pinned.session.webSocketTask(with: url, protocols: protocols)
        task.resume()
        return NebulaURLSessionWebSocket(task: task, pinned: pinned, logger: logger)
    }

    /// Opens a WebSocket client to `request` (for custom headers) on the
    /// pinned session, returning a ``NebulaURLSessionWebSocket`` façade that
    /// retains the pinned session.
    public static func open(
        request: URLRequest,
        using pinned: NebulaPinnedWebSocketSession,
        logger: NebulaLogger? = nil
    ) -> NebulaURLSessionWebSocket {
        let task = pinned.session.webSocketTask(with: request)
        task.resume()
        return NebulaURLSessionWebSocket(task: task, pinned: pinned, logger: logger)
    }
}