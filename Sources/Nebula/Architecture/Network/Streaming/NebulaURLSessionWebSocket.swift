//
//  NebulaURLSessionWebSocket.swift
//  Nebula
//
//  Wave N17b — Streaming. The concrete ``NebulaWebSocketClient`` adapter: a
//  `final class` façade over `URLSessionWebSocketTask`. `URLSessionWebSocketTask`
//  is annotated `NS_SWIFT_SENDABLE` (NSURLSession.h:1121) so the class derives
//  `Sendable` from its `let` stored props — NO `@unchecked`. Probed against the
//  Xcode 27 Beta 3 SDK → EXIT=0.
//
//  The façade holds the ``NebulaPinnedWebSocketSession`` (the ownership anchor:
//  it retains the `URLSession` AND the ``NebulaWebSocketSessionDelegate`` —
//  `URLSession` does NOT strongly retain its delegate, so dropping the pinned
//  session would silently disable pinning + lifecycle callbacks). Retaining
//  the façade retains everything (session + delegate + task).
//
//  `init`/`new` on `URLSessionWebSocketTask` is unavailable (`NSURLSession.h:1184`),
//  so the façade cannot create the task itself — the session builder
//  (``NebulaWebSocketSession/open(url:using:logger:)``) creates the task via
//  `URLSession.webSocketTask(with:)` + `.resume()` and hands it here.
//
//  Error mapping (the testable seam): `mapSend`/`mapReceive`/`mapPing` are
//  `internal` helpers unit-tested directly (a live `URLSessionWebSocketTask`
//  round-trip is covered by the `NWListener` echo server in the tests; the
//  pure mapping covers the error-bridging logic). All symbols are below the
//  `.v26` floor — **no `@available` gate**. `import Foundation` only.
//

import Foundation

/// The concrete ``NebulaWebSocketClient`` adapter: a `Sendable` `final class`
/// façade over `URLSessionWebSocketTask`.
///
/// Retain this value for the socket's lifetime — it holds the
/// ``NebulaPinnedWebSocketSession`` (session + delegate) so the delegate is not
/// silently dropped (`URLSession` does NOT strongly retain its delegate).
public final class NebulaURLSessionWebSocket: NebulaWebSocketClient, Sendable {

    /// The ownership anchor: the pinned `URLSession` + its
    /// ``NebulaWebSocketSessionDelegate``. Retained so pinning + lifecycle
    /// callbacks stay alive for the socket's lifetime.
    public let pinned: NebulaPinnedWebSocketSession

    /// The underlying WebSocket task.
    public let task: URLSessionWebSocketTask

    /// An optional logger for failure diagnostics (`nil` = silent).
    public let logger: NebulaLogger?

    /// Creates the façade. The session builder is the normal constructor (it
    /// creates the task via `URLSession.webSocketTask(with:)` + `.resume()`);
    /// this `init` is public for callers that construct their own task.
    public init(
        task: URLSessionWebSocketTask,
        pinned: NebulaPinnedWebSocketSession,
        logger: NebulaLogger? = nil
    ) {
        self.task = task
        self.pinned = pinned
        self.logger = logger
    }

    // MARK: - NebulaWebSocketClient

    public func send(_ message: NebulaWebSocketMessage) async throws {
        do {
            try await task.send(message.rawMessage)
        } catch {
            let error = mapSend(error)
            logger?.error("WebSocket send failed: \(error.message)")
            throw error
        }
    }

    public func receive() async throws -> NebulaWebSocketMessage {
        do {
            let raw = try await task.receive()
            guard let message = NebulaWebSocketMessage(raw) else {
                // Non-frozen Apple enum gained an unknown case.
                let error = NebulaWebSocketError.unknown("Unsupported WebSocket message case")
                logger?.error("WebSocket receive failed: \(error.message)")
                throw error
            }
            return message
        } catch {
            let error = mapReceive(error)
            logger?.error("WebSocket receive failed: \(error.message)")
            throw error
        }
    }

    public func sendPing() async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                task.sendPing { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            let error = mapPing(error)
            logger?.error("WebSocket ping failed: \(error.message)")
            throw error
        }
    }

    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        task.cancel(with: closeCode, reason: reason)
    }

    public var closeCode: URLSessionWebSocketTask.CloseCode? {
        let code = task.closeCode
        return code == .invalid ? nil : code
    }

    public var maximumMessageSize: Int {
        get { task.maximumMessageSize }
        set { task.maximumMessageSize = newValue }
    }

    // MARK: - Error mapping (the testable seam)
    //
    // `internal` so the test module covers them directly (no live socket
    // needed). Cancellation surfaces as `CancellationError` or
    // `URLError(.cancelled)` → `.cancelled`; a peer-close (when `task.closeCode`
    // is set) → `.closed`; otherwise the per-verb failure.

    /// Maps a `send` error to a ``NebulaWebSocketError``.
    internal func mapSend(_ error: Error) -> NebulaWebSocketError {
        if isCancellation(error) { return .cancelled() }
        return .sendFailed("WebSocket send failed: \(error.localizedDescription)",
                           underlying: box(error))
    }

    /// Maps a `receive` error to a ``NebulaWebSocketError``. A set `closeCode`
    /// indicates the peer closed gracefully.
    internal func mapReceive(_ error: Error) -> NebulaWebSocketError {
        let code = task.closeCode
        if code != .invalid {
            return .closed(code: code, reason: task.closeReason)
        }
        if isCancellation(error) { return .cancelled() }
        return .receiveFailed("WebSocket receive failed: \(error.localizedDescription)",
                              underlying: box(error))
    }

    /// Maps a `sendPing` error to a ``NebulaWebSocketError``.
    internal func mapPing(_ error: Error) -> NebulaWebSocketError {
        if isCancellation(error) { return .cancelled() }
        return .pingFailed("WebSocket ping failed: \(error.localizedDescription)",
                           underlying: box(error))
    }

    /// `true` for `CancellationError` and `URLError(.cancelled)`.
    internal func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// Boxes an arbitrary error lossily into a ``NebulaError/Box``.
    internal func box(_ error: Error) -> NebulaError.Box {
        NebulaError.Box(NebulaError(error: error))
    }
}