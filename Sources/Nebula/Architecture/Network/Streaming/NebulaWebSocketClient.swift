//
//  NebulaWebSocketClient.swift
//  Nebula
//
//  Wave N17b — Streaming. The WebSocket port (Clean Architecture
//  ports-and-adapters idiom, mirroring ``NebulaHTTPClient``) + the Nebula-owned
//  ``NebulaWebSocketMessage`` enum. The port is its own axis (no
//  ``NebulaGateway`` inheritance — WebSocket is not request/response); the
//  concrete adapter is ``NebulaURLSessionWebSocket``.
//
//  ``NebulaWebSocketMessage`` mirrors `URLSessionWebSocketTask.Message` but is
//  a Nebula-owned type — the idiom is never to expose Apple's nested enum in a
//  Nebula port. Both cases (`data`/`string`) bridge to the underlying
//  `URLSessionWebSocketTask.Message`.
//
//  All symbols are below the `.v26` floor (`URLSessionWebSocketTask` is macOS
//  10.15 / iOS 13 / watchOS 6 / tvOS 13 / visionOS 1.0+) — **no `@available`
//  gate**. `import Foundation` only.
//

import Foundation

/// A WebSocket message (text or binary), mirroring
/// `URLSessionWebSocketTask.Message` as a Nebula-owned type.
///
/// The idiom is never to expose Apple's nested enum in a Nebula port — this
/// enum is the public surface; ``rawMessage`` bridges to the underlying
/// `URLSessionWebSocketTask.Message` for the adapter. `Sendable`,
/// `Equatable`, and `Hashable` are derived from the value-type cases.
public enum NebulaWebSocketMessage: Sendable, Equatable, Hashable {

    /// A binary message.
    case data(Data)

    /// A text message.
    case string(String)

    /// Creates a Nebula message from the underlying
    /// `URLSessionWebSocketTask.Message`.
    ///
    /// Failable because `URLSessionWebSocketTask.Message` is a non-frozen enum
    /// (only `.data`/`.string` today, but Apple may add cases) — an unknown
    /// future case yields `nil` (the façade surfaces it as a
    /// ``NebulaWebSocketError/unknown``).
    public init?(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let d): self = .data(d)
        case .string(let s): self = .string(s)
        @unknown default: return nil
        }
    }

    /// Bridges to the underlying `URLSessionWebSocketTask.Message`.
    public var rawMessage: URLSessionWebSocketTask.Message {
        switch self {
        case .data(let d): return .data(d)
        case .string(let s): return .string(s)
        }
    }
}

/// The WebSocket client port (Clean Architecture ports-and-adapters, mirroring
/// ``NebulaHTTPClient``).
///
/// The port is `Sendable` (it crosses isolation boundaries) and is its own
/// axis — WebSocket is not request/response, so it does not inherit
/// ``NebulaGateway``. The concrete adapter is ``NebulaURLSessionWebSocket``;
/// a test double can conform for higher-level code.
public protocol NebulaWebSocketClient: Sendable {

    /// Sends a message.
    func send(_ message: NebulaWebSocketMessage) async throws

    /// Receives the next message.
    func receive() async throws -> NebulaWebSocketMessage

    /// Sends a ping (and awaits the pong).
    func sendPing() async throws

    /// Closes the socket with `closeCode` and an optional `reason` (non-throwing
    /// — the underlying `cancel(with:reason:)` is synchronous and non-throwing).
    func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async

    /// The peer's close code (`.invalid` until the socket closes), or `nil`
    /// when unavailable.
    var closeCode: URLSessionWebSocketTask.CloseCode? { get }

    /// The maximum message size (get/set passthrough).
    var maximumMessageSize: Int { get set }
}