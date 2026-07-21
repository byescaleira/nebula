//
//  ArchitectureWebSocketTests.swift
//  NebulaTests
//
//  Wave N17b — Streaming. Unit tests for the WebSocket surface:
//  - A. the pure ``NebulaWebSocketMessage`` ↔ `URLSessionWebSocketTask.Message`
//       bridge (no live socket),
//  - B. the error mapping (the `internal` `mapSend`/`mapReceive`/`mapPing`/`isCancellation`
//       seams on ``NebulaURLSessionWebSocket``, plus ``NebulaWebSocketError``),
//  - C. the pinned-session builder (``NebulaWebSocketSession/pinned(by:)`` +
//       ``NebulaPinnedWebSocketSession``) + the `NebulaURLSessionDelegate`
//       composition,
//  - D. the combined delegate's lifecycle callbacks + the auth-challenge
//       **forwarding** to the N17a ``NebulaURLSessionDelegate`` (a spy
//       delegate records the forwarded call — no live socket),
//  - E. a live round-trip against an `NWListener` WebSocket echo server (plain
//       `ws://` — `Network.framework` is admissible, the ``NebulaHTTPServer``
//       precedent); the high-value integration test proving the façade talks
//       to a real `URLSessionWebSocketTask`.
//
//  `@testable import Nebula` exposes the `internal` mapping helpers + the
//  `NebulaWebSocketMessage` bridge. The echo server (E) is `@Suite(.serialized)`
//  (process-wide listener port allocation). See vault/03-padroes/nebula-streaming.md.
//

import Testing
import Foundation
import Network
import Synchronization
@testable import Nebula

// MARK: - A Sendable box so a ~Copyable Mutex can be captured in @Sendable
// closures (mirrors ArchitectureHTTPGatewayTests / ArchitectureSSETests).

private final class SendableBox<T: Sendable>: Sendable {
    private let mutex: Mutex<T>
    init(_ initial: T) { mutex = Mutex<T>(initial) }
    func mutate(_ body: (inout T) -> Void) { mutex.withLock { body(&$0) } }
    var value: T { mutex.withLock { $0 } }
}
// MARK: - A URLAuthenticationChallengeSender stub (the challenge sender is
// required to construct a URLAuthenticationChallenge but is never exercised).
// `NebulaURLSessionDelegate` is `final` (cannot be subclassed for a spy), so
// auth-challenge forwarding is verified by feeding the WebSocket delegate a
// non-server-trust challenge and asserting the disposition the *real*
// `NebulaURLSessionDelegate` returns for such a challenge (`.performDefaultHandling`).
// This proves the forward executed — the real delegate's logic ran through the
// WebSocket delegate's `urlSession(_:didReceive:completionHandler:)`.

private final class URLAuthenticationChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

@Suite struct ArchitectureWebSocketTests {

    // MARK: - A. Message bridge (pure)
    //
    // `URLSessionWebSocketTask.Message` is NOT `Equatable` (only `Sendable`),
    // so the bridge is verified by round-tripping through the failable
    // `NebulaWebSocketMessage(_:)` init (which is `Equatable`) and by pattern-
    // matching the raw case.

    @Test func messageBridgesStringToRawAndBack() {
        let msg = NebulaWebSocketMessage.string("hello")
        if case .string(let s) = msg.rawMessage {
            #expect(s == "hello")
        } else {
            Issue.record("expected .string raw case")
        }
        let round = NebulaWebSocketMessage(msg.rawMessage)
        #expect(round == .string("hello"))
    }

    @Test func messageBridgesDataToRawAndBack() {
        let payload = Data([0x00, 0xFF, 0x42])
        let msg = NebulaWebSocketMessage.data(payload)
        if case .data(let d) = msg.rawMessage {
            #expect(d == payload)
        } else {
            Issue.record("expected .data raw case")
        }
        let round = NebulaWebSocketMessage(msg.rawMessage)
        #expect(round == .data(payload))
    }

    @Test func messageIsEquatableAndHashable() {
        #expect(NebulaWebSocketMessage.string("x") == NebulaWebSocketMessage.string("x"))
        #expect(NebulaWebSocketMessage.string("x") != NebulaWebSocketMessage.data(Data([0x78])))
        #expect(NebulaWebSocketMessage.string("x").hashValue == NebulaWebSocketMessage.string("x").hashValue)
    }

    // MARK: - B. Error mapping (pure, the internal seams)

    @Test func mapSendCancellationIsCancelledKind() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(by: pinning)
        // A dummy task via the pinned session — never connected; the mapping
        // helpers are pure w.r.t. the thrown error (they only inspect it + the
        // task's closeCode/closeReason).
        let task = pinned.session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/unused")!)
        let ws = NebulaURLSessionWebSocket(task: task, pinned: pinned)
        #expect(ws.mapSend(CancellationError()).kind == .cancelled)
        #expect(ws.mapSend(CancellationError()).coarseKind == .unknown)
        #expect(ws.mapPing(CancellationError()).kind == .cancelled)
    }

    @Test func mapSendURLErrorIsSendFailed() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(by: pinning)
        let task = pinned.session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/unused")!)
        let ws = NebulaURLSessionWebSocket(task: task, pinned: pinned)
        let err = ws.mapSend(URLError(.cannotConnectToHost))
        #expect(err.kind == .sendFailed)
        #expect(err.coarseKind == .network)
        #expect(err.underlying != nil)
    }

    @Test func mapReceiveCancellationIsCancelledKind() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(by: pinning)
        let task = pinned.session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/unused")!)
        let ws = NebulaURLSessionWebSocket(task: task, pinned: pinned)
        // closeCode == .invalid (socket never opened) → not a peer-close.
        #expect(task.closeCode == .invalid)
        #expect(ws.mapReceive(CancellationError()).kind == .cancelled)
    }

    @Test func isCancellationRecognizesBothForms() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(by: pinning)
        let task = pinned.session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/unused")!)
        let ws = NebulaURLSessionWebSocket(task: task, pinned: pinned)
        #expect(ws.isCancellation(CancellationError()))
        #expect(ws.isCancellation(URLError(.cancelled)))
        #expect(!ws.isCancellation(URLError(.cannotConnectToHost)))
    }

    @Test func webSocketErrorCoarseKindAndBridge() {
        let err = NebulaWebSocketError.sendFailed("boom")
        #expect(err.coarseKind == .network)
        #expect(err.kind == .sendFailed)
        let bridged = err.toNebulaError(kind: err.coarseKind)
        #expect(bridged.code.domain == "Nebula.NebulaWebSocketError")
        #expect(bridged.metadata["NebulaCode"] == "send-failed")
    }

    @Test func webSocketErrorClosedCarriesCodeAndReason() {
        let reason = Data("bye".utf8)
        let err = NebulaWebSocketError.closed(code: .normalClosure, reason: reason)
        #expect(err.kind == .closed)
        #expect(err.coarseKind == .network)
        #expect(err.metadata["WebSocketCloseCode"] == "1000")
        #expect(err.metadata["WebSocketCloseReason"] == "bye")
    }

    @Test func webSocketErrorCancelledIsUnknown() {
        #expect(NebulaWebSocketError.cancelled().coarseKind == .unknown)
        #expect(NebulaWebSocketError.unknown().coarseKind == .unknown)
    }

    // MARK: - C. Session builder + composition

    @Test func pinnedSessionCarriesSessionAndDelegate() {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(
            by: pinning,
            onOpen: { _ in },
            onClose: { _, _ in })
        #expect(pinned.session.delegate === pinned.delegate)
        #expect(pinned.delegate.pinningDelegate.pinning == pinning)
    }

    @Test func openReturnsFacadeRetainingPinnedSession() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinned = NebulaWebSocketSession.pinned(by: pinning)
        let ws = NebulaWebSocketSession.open(
            url: URL(string: "ws://127.0.0.1:1/noop")!,
            using: pinned)
        #expect(ws.pinned.session === pinned.session)
        #expect(ws.pinned.delegate === pinned.delegate)
        #expect(ws.closeCode == nil)   // .invalid → nil; never opened
        // Cancel the resumed task so it does not leak / hang the test.
        await ws.close(with: .goingAway, reason: nil)
    }

    // MARK: - D. Delegate lifecycle + forwarding (no live socket)

    @Test func delegateFiresOnOpenAndOnClose() async throws {
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinningDelegate = NebulaURLSessionDelegate(pinning: pinning)
        let openProtocolBox = SendableBox<String?>(nil)
        let closeBox = SendableBox<URLSessionWebSocketTask.CloseCode?>(nil)
        let closeReasonBox = SendableBox<Data?>(nil)
        let delegate = NebulaWebSocketSessionDelegate(
            pinningDelegate: pinningDelegate,
            onOpen: { proto in openProtocolBox.mutate { $0 = proto } },
            onClose: { code, reason in
                closeBox.mutate { $0 = code }
                closeReasonBox.mutate { $0 = reason }
            })
        let session = URLSession(configuration: .ephemeral, delegate: NebulaURLSessionDelegate(pinning: pinning), delegateQueue: nil)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/unused")!)

        delegate.urlSession(session, webSocketTask: task, didOpenWithProtocol: "nebula-echo")
        delegate.urlSession(session, webSocketTask: task, didCloseWith: .normalClosure, reason: Data("done".utf8))

        #expect(openProtocolBox.value == "nebula-echo")
        #expect(closeBox.value == .normalClosure)
        #expect(closeReasonBox.value == Data("done".utf8))
    }

    @Test func delegateForwardsAuthChallengeToPinningDelegate() async throws {
        // `NebulaURLSessionDelegate` is `final` (no spy subclass), so the
        // forward is verified by feeding the WebSocket delegate a NON-server-
        // trust challenge: the real `NebulaURLSessionDelegate` returns
        // `.performDefaultHandling` for any non-server-trust challenge, so
        // observing that disposition proves the forward executed.
        let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let pinningDelegate = NebulaURLSessionDelegate(pinning: pinning)
        let delegate = NebulaWebSocketSessionDelegate(
            pinningDelegate: pinningDelegate,
            onOpen: { _ in },
            onClose: { _, _ in })
        let session = URLSession(configuration: .ephemeral, delegate: pinningDelegate, delegateQueue: nil)
        _ = session.webSocketTask(with: URL(string: "wss://example.test/unused")!)

        let protectionSpace = URLProtectionSpace(
            host: "example.test", port: 443, protocol: NSURLProtectionSpaceHTTPS,
            realm: nil, authenticationMethod: "nebula-not-server-trust")
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: URLAuthenticationChallengeSenderStub())

        let dispositionBox = SendableBox<URLSession.AuthChallengeDisposition?>(nil)
        delegate.urlSession(session, didReceive: challenge) { disposition, _ in
            dispositionBox.mutate { $0 = disposition }
        }
        #expect(dispositionBox.value == .performDefaultHandling)
    }

    // MARK: - E. Live round-trip via NWListener WebSocket echo server

    @Suite(.serialized) struct WebSocketLiveEchoTests {

        @Test func sendReceivePingAndCloseRoundTrip() async throws {
            let server = try NebulaWebSocketEchoServer()
            try await server.start()
            defer { server.stop() }
            #expect(server.port > 0)

            // Wait for the client's `onOpen` before sending (the handshake is
            // async; a fixed sleep races it). A mutex-stored continuation raced
            // against a 5s timeout so the test fails (not hangs) if it never
            // opens.
            let opened = Mutex<CheckedContinuation<Void, Never>?>(nil)
            let pinning = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
            let pinned = NebulaWebSocketSession.pinned(
                by: pinning,
                onOpen: { _ in opened.withLock { cont in cont?.resume(); cont = nil } },
                onClose: { _, _ in })
            let url = URL(string: "ws://127.0.0.1:\(server.port)")!
            let ws = NebulaWebSocketSession.open(url: url, using: pinned)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        opened.withLock { $0 = c }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    opened.withLock { cont in cont?.resume(); cont = nil }
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }

            try await ws.send(.string("ping"))
            let received = try await ws.receive()
            #expect(received == .string("ping"))

            try await ws.sendPing()

            await ws.close(with: .normalClosure, reason: Data("done".utf8))
            // The close code surfaces after the peer close is processed.
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(ws.closeCode == .normalClosure)
        }
    }
}

// MARK: - A minimal NWListener WebSocket echo server (plain ws://). Handles the
// handshake via NWProtocolWebSocket auto-reply, echoes each received message,
// and tracks the bound port. `Network.framework` is admissible (the
// ``NebulaHTTPServer`` precedent). The server is a `final class @unchecked
// Sendable` — the only mutable state is a `Mutex`-backed flag + the listener
// (audited reference type; the binding forbids `@unchecked` on value types only).

private final class NebulaWebSocketEchoServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "nebula.test.ws-echo")
    private let stopped = Mutex<Bool>(false)
    private let connectionsLock = Mutex<[NWConnection]>([])

    /// The bound port (read after ``start()``).
    private(set) var port: UInt16 = 0

    init() throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true   // auto-responds to client pings
        // Accept every client handshake (handles the HTTP upgrade).
        wsOptions.setClientRequestHandler(queue) { subprotocols, _ in
            NWProtocolWebSocket.Response(
                status: .accept, subprotocol: subprotocols.first, additionalHeaders: nil)
        }
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        listener = try NWListener(using: params, on: .any)
    }

    func start() async throws {
        let started = Mutex<Bool>(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !started.withLock({ $0 }) {
                        started.withLock { $0 = true }
                        if let self { self.port = self.listener.port?.rawValue ?? 0 }
                        continuation.resume()
                    }
                case .failed:
                    if !started.withLock({ $0 }) {
                        started.withLock { $0 = true }
                        continuation.resume()
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    private func handle(_ connection: NWConnection) {
        connectionsLock.withLock { $0.append(connection) }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveLoop(connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            if error != nil {
                self?.removeConnection(connection)
                return
            }
            if let data, !data.isEmpty {
                // Echo with the same WebSocket opcode the peer sent. A raw
                // `send(content:)` without `NWProtocolWebSocket.Metadata` would
                // emit an invalid frame, so mirror the received opcode.
                var opcode = NWProtocolWebSocket.Opcode.text
                if let context {
                    for proto in context.protocolMetadata {
                        if let ws = proto as? NWProtocolWebSocket.Metadata {
                            opcode = ws.opcode
                        }
                    }
                }
                let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
                let echoContext = NWConnection.ContentContext(
                    identifier: "nebula.echo", metadata: [metadata])
                connection.send(content: data, contentContext: echoContext,
                                isComplete: true, completion: .contentProcessed { _ in })
            }
            // Re-arm for the next message.
            self?.receiveLoop(connection)
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.withLock { $0.removeAll { $0 === connection } }
        connection.cancel()
    }

    func stop() {
        guard !stopped.withLock({ $0 }) else { return }
        stopped.withLock { $0 = true }
        connectionsLock.withLock { $0 }.forEach { $0.cancel() }
        connectionsLock.withLock { $0.removeAll() }
        listener.cancel()
    }
}