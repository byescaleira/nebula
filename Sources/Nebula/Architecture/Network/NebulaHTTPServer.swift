//
//  NebulaHTTPServer.swift
//  Nebula
//
//  Wave N7 — Network. A simple local HTTP/1.1 server over Network.framework
//  (`NWListener` / `NWConnection`) — the server-side counterpart to
//  ``NebulaHTTPGateway``. Foundation + Network only (no SwiftUI / UIKit / new
//  framework import). `NWListener` / `NWConnection` are `Sendable` from
//  macOS 14 / iOS 17 (verified against the Xcode 27 Beta 3 `.swiftinterface`),
//  well below the `.v26` floor — no `@available` gating. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//
//  Scope = "simple": plain HTTP/1.1, no TLS, no chunked transfer-encoding, no
//  keep-alive (the connection closes after one response), `Content-Length`
//  bodies only. A dev / test / full-stack-app tool, not a production server.
//

import Foundation
import Network
import Synchronization

/// A simple local HTTP/1.1 server over Network.framework.
///
/// Listens on a TCP port (`NWListener`), accepts connections (`NWConnection`),
/// parses each request via ``NebulaHTTPRequestParser`` into a
/// ``NebulaHTTPRequest``, dispatches it to a `@Sendable` handler, and writes
/// the handler's ``NebulaHTTPResponse`` back as HTTP/1.1 bytes. Each connection
/// is closed after one response (no keep-alive).
///
/// `Sendable` by derived conformance: `NWListener`, `NWConnection`, the
/// `@Sendable` handler, and `DispatchQueue` are all `Sendable` at the `.v26`
/// floor — no `@unchecked`. The `DispatchQueue` is Network.framework's required
/// event-dispatch queue (the `NWListener.start(queue:)` contract), **not** a
/// synchronization primitive — the only shared mutable state (the start-once
/// flag) is a `Mutex`-guarded `final class`.
///
/// ```swift
/// let server = try NebulaHTTPServer(port: 8080) { request in
///     NebulaHTTPResponse(statusCode: 200, body: Data("hello".utf8))
/// }
/// try await server.start()
/// // ... requests are served on the cooperative pool ...
/// server.stop()
/// ```
public final class NebulaHTTPServer: Sendable {

    /// A `Mutex`-guarded one-shot flag (the `~Copyable` `Mutex` is absorbed
    /// behind a copyable, `Sendable` reference — the ``NebulaDefaults`` /
    /// ``NebulaSpyUseCase`` precedent) so `start()` resumes its continuation
    /// exactly once across the `@Sendable` state-update callbacks.
    private final class OnceFlag: Sendable {
        private let mutex = Mutex<Bool>(false)
        /// Returns `true` the first time it is called, `false` thereafter.
        func trySet() -> Bool {
            mutex.withLock { value in
                if value { return false }
                value = true
                return true
            }
        }
    }

    /// The Network.framework listener.
    private let listener: NWListener
    /// The request handler. `@Sendable` so it can be invoked from connection
    /// tasks on the cooperative pool.
    private let handler: @Sendable (NebulaHTTPRequest) -> NebulaHTTPResponse
    /// Network.framework's event-dispatch queue (the `start(queue:)` contract —
    /// not a synchronization primitive).
    private let queue: DispatchQueue

    /// Creates a server that will listen on `port` (8080 by default; pass
    /// `NWEndpoint.Port(rawValue: 0)` for an OS-assigned ephemeral port, then
    /// read ``port`` after ``start()``).
    public init(
        port: NWEndpoint.Port = 8080,
        handler: @escaping @Sendable (NebulaHTTPRequest) -> NebulaHTTPResponse
    ) throws {
        // Plain TCP, no TLS.
        self.listener = try NWListener(using: .tcp, on: port)
        self.handler = handler
        self.queue = DispatchQueue(label: "Nebula.HTTPServer")
    }

    /// The bound port (`nil` until the listener is `.ready`; the OS-assigned
    /// port when initialized with port `0`).
    public var port: NWEndpoint.Port? { listener.port }

    /// Starts the listener and suspends until it is ready (or fails to bind).
    ///
    /// Throws ``NebulaHTTPServerError/bindFailed(_:)`` if the port cannot be
    /// bound. The `NWError` is folded into the message (it is not `Sendable`,
    /// so it is not boxed across isolation — lossy, mirroring the gateway's
    /// `URLError` bridging).
    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let started = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if started.trySet() { continuation.resume() }
                case .failed(let error):
                    if started.trySet() {
                        continuation.resume(throwing: NebulaHTTPServerError.bindFailed("Bind failed: \(error)"))
                    }
                case .cancelled:
                    if started.trySet() {
                        continuation.resume(throwing: NebulaHTTPServerError.cancelled())
                    }
                case .setup, .waiting:
                    break
                @unknown default:
                    break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                self.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Stops the listener (in-flight connections are cancelled).
    public func stop() {
        listener.cancel()
    }

    deinit { listener.cancel() }

    // MARK: - Connection handling

    /// Wires one accepted connection: starts it, and on `.ready` runs the
    /// read-parse-respond loop on the cooperative pool.
    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                Task { await self.serve(connection) }
            case .failed, .cancelled:
                connection.cancel()
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Reads, parses, dispatches, and responds for one connection, then closes
    /// it (no keep-alive). Best-effort: per-connection errors are surfaced as a
    /// 400 (parse) or 500 (send) response, then the connection is cancelled.
    private func serve(_ connection: NWConnection) async {
        var buffer = Data()
        while true {
            guard let chunk = await receive(connection), !chunk.isEmpty else {
                connection.cancel()
                return
            }
            buffer.append(chunk)
            do {
                guard let request = try NebulaHTTPRequestParser.parse(buffer) else {
                    continue  // need more bytes
                }
                let response = handler(request)
                await send(connection, response: response)
                connection.cancel()
                return
            } catch {
                await send(connection, response: NebulaHTTPResponse(
                    statusCode: 400,
                    headers: ["Content-Type": "text/plain"],
                    body: Data("Bad Request".utf8)
                ))
                connection.cancel()
                return
            }
        }
    }

    /// Reads one chunk from `connection` (async-wraps the callback-based
    /// `receive`). Returns `nil` on close, error, or an empty read.
    private func receive(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, _, _ in
                continuation.resume(returning: content)
            }
        }
    }

    /// Sends `response` to `connection` (async-wraps the callback-based `send`).
    private func send(_ connection: NWConnection, response: NebulaHTTPResponse) async {
        let bytes = NebulaHTTPServer.serialize(response)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: bytes, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    /// Serializes a response to HTTP/1.1 bytes (status line + headers +
    /// `Content-Length` + blank line + body).
    static func serialize(_ response: NebulaHTTPResponse) -> Data {
        var head = "HTTP/1.1 \(response.statusCode) \(NebulaHTTPServer.reasonPhrase(for: response.statusCode))\r\n"
        // Drop any existing Content-Length (case-insensitive) so the handler
        // cannot emit a duplicate or stale length — the actual body count wins.
        var headers = response.headers.filter { $0.key.lowercased() != "content-length" }
        headers["Content-Length"] = "\(response.body.count)"
        for (name, value) in headers {
            // Defense-in-depth: strip CR/LF from handler-provided header names and
            // values so a misbehaving handler cannot inject extra headers or a body.
            let safeName = name.replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let safeValue = value.replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            head += "\(safeName): \(safeValue)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        return data
    }

    /// Maps a status code to its reason phrase (a small subset; unknown codes
    /// fall back to the canonical default for their class).
    static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return code < 400 ? "OK" : "Error"
        }
    }
}