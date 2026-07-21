//
//  ArchitectureSSETests.swift
//  NebulaTests
//
//  Wave N17b — Streaming. Unit tests for the Server-Sent Events surface:
//  - A. the pure ``NebulaSSEParser`` (canned `[String]` inputs — no URLSession),
//  - B. ``NebulaSSEConfiguration`` value semantics,
//  - C. the live stream via a `URLProtocol`-backed `URLSession` (no real
//    network; `URLProtocol` intercepts `URLSession.bytes(for:)` data tasks),
//  - D. reconnect with `Last-Event-ID` + cancellation,
//  - E. error mapping (``NebulaSSEError``).
//
//  `@testable import Nebula` exposes the `internal` ``NebulaSSEParser``. Suite
//  is serialized where the `URLProtocol` handler (process-wide shared state) is
//  involved. See vault/03-padroes/nebula-streaming.md.
//

import Testing
import Foundation
import Synchronization
@testable import Nebula

// MARK: - A Sendable box so a ~Copyable Mutex can be captured in @Sendable
// closures (mirrors ArchitectureHTTPGatewayTests).

private final class SendableBox<T: Sendable>: Sendable {
    private let mutex: Mutex<T>
    init(_ initial: T) { mutex = Mutex<T>(initial) }
    func mutate(_ body: (inout T) -> Void) { mutex.withLock { body(&$0) } }
    var value: T { mutex.withLock { $0 } }
}

// MARK: - A URLProtocol that serves a canned SSE byte body per a process-wide
// handler (and records the request). Scoped to a session via `protocolClasses`.

private final class NebulaSSETestProtocol: URLProtocol {
    static let handler = Mutex<@Sendable (URLRequest) throws -> Data?>({ _ in nil })
    static let recorded = Mutex<[URLRequest]>([])
    /// When `true`, startLoading sends the response header but never calls
    /// `didLoad`/`finishLoading` — the connection hangs (bytes(for:) blocks),
    /// used to test cancellation.
    static let hang = Mutex<Bool>(false)

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func canInit(with request: URLRequest) -> Bool { true }

    override func startLoading() {
        do {
            NebulaSSETestProtocol.recorded.withLock { $0.append(request) }
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                            httpVersion: "HTTP/1.1",
                                            headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if NebulaSSETestProtocol.hang.withLock({ $0 }) {
                // Hang: send the header but never deliver the body / finish.
                return
            }
            let body = try NebulaSSETestProtocol.handler.withLock({ $0 })(request)
            client?.urlProtocol(self, didLoad: body ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [NebulaSSETestProtocol.self]
    return URLSession(configuration: config)
}

/// Installs a handler returning `body` and recording requests into `box`.
private func serve(_ body: Data, into box: SendableBox<[URLRequest]>) {
    NebulaSSETestProtocol.handler.withLock { $0 = { req in
        box.mutate { $0.append(req) }
        return body
    } }
}

/// Installs a handler returning `body` (no recording).
private func serve(_ body: Data) {
    NebulaSSETestProtocol.handler.withLock { $0 = { _ in body } }
}

/// Installs a handler that throws `error` (a transport failure).
private func serveThrow(_ error: @escaping @autoclosure @Sendable () -> Error) {
    NebulaSSETestProtocol.handler.withLock { $0 = { _ in throw error() } }
}

/// An instant sleeper (no delay) for reconnect tests.
private let instantSleeper: @Sendable (Duration) async throws -> Void = { _ in }

@Suite struct ArchitectureSSETests {

    // MARK: - A. Parser (pure)

    @Test func parserDispatchesSimpleDataEvent() {
        var parser = NebulaSSEParser()
        #expect(parser.feed("data: hello") == nil)
        let event = parser.feed("")
        #expect(event == NebulaSSEEvent(id: nil, event: "message", data: "hello", retry: nil))
    }

    @Test func parserJoinsMultiLineData() {
        var parser = NebulaSSEParser()
        #expect(parser.feed("data: a") == nil)
        #expect(parser.feed("data: b") == nil)
        let event = parser.feed("")
        #expect(event?.data == "a\nb")
    }

    @Test func parserStripsOneSpaceAfterColon() {
        var parser = NebulaSSEParser()
        parser.feed("data:  spaced")   // one space stripped → " spaced"
        #expect(parser.feed("")?.data == " spaced")
    }

    @Test func parserHandlesEventField() {
        var parser = NebulaSSEParser()
        parser.feed("event: update")
        parser.feed("data: x")
        let event = parser.feed("")
        #expect(event?.event == "update")
    }

    @Test func parserCarriesIDAndRetryAcrossDispatches() {
        var parser = NebulaSSEParser()
        parser.feed("id: 42")
        parser.feed("retry: 5000")
        parser.feed("data: first")
        let first = parser.feed("")
        #expect(first?.id == "42")
        #expect(first?.retry == 5000)

        // New event with no id/retry fields — lastEventID/retry persist.
        parser.feed("data: second")
        let second = parser.feed("")
        #expect(second?.id == "42")
        #expect(second?.retry == 5000)
        #expect(second?.event == "message")
    }

    @Test func parserIgnoresCommentsAndUnknownFields() {
        var parser = NebulaSSEParser()
        parser.feed(": keepalive")     // comment
        parser.feed("foo: bar")       // unknown field
        parser.feed("data: hi")
        let event = parser.feed("")
        #expect(event?.data == "hi")
        #expect(parser.lastEventID == nil)
    }

    @Test func parserRejectsIDWithNull() {
        var parser = NebulaSSEParser()
        parser.feed("id: bad\u{0000}id")
        #expect(parser.lastEventID == nil)
        parser.feed("id: good")
        #expect(parser.lastEventID == "good")
    }

    @Test func parserIgnoresNonIntRetry() {
        var parser = NebulaSSEParser()
        parser.feed("retry: notanumber")
        #expect(parser.retry == nil)
        parser.feed("retry: 1500")
        #expect(parser.retry == 1500)
    }

    @Test func parserStripsTrailingCR() {
        var parser = NebulaSSEParser()
        parser.feed("data: hello\r")
        #expect(parser.feed("\r")?.data == "hello")
    }

    @Test func parserDoesNotDispatchEmptyData() {
        var parser = NebulaSSEParser()
        parser.feed("event: ping")   // no data field
        #expect(parser.feed("") == nil)   // no spurious empty event
    }

    @Test func parserHandlesLineWithoutColon() {
        var parser = NebulaSSEParser()
        parser.feed("data")   // field "data", empty value → appends "\n"
        #expect(parser.feed("")?.data == "")
    }

    // MARK: - B. Configuration value semantics

    @Test func configurationWithBuildersReturnDistinctCopies() {
        let base = NebulaSSEConfiguration.default
        let noReconnect = base.withReconnect(false)
        #expect(noReconnect.reconnect == false)
        #expect(base.reconnect == true)
        #expect(noReconnect.withMaxReconnectAttempts(3).maxReconnectAttempts == 3)
        #expect(noReconnect.withReconnectDelay(.milliseconds(10)).reconnectDelay == .milliseconds(10))
    }

    // MARK: - C. Live stream via URLProtocol (serialized)

    @Suite(.serialized) struct SSELiveStreamTests {

        @Test func streamYieldsEvents() async throws {
            let box = SendableBox<[URLRequest]>([])
            serve(Data("data: hello\n\nid: 1\ndata: world\n\n".utf8), into: box)
            let request = URLRequest(url: URL(string: "https://test.test/sse")!)
            let stream = NebulaSSEEventStream.events(
                for: request, session: makeSession(),
                configuration: NebulaSSEConfiguration(reconnect: false, sleeper: instantSleeper))
            var events: [NebulaSSEEvent] = []
            for try await event in stream { events.append(event) }
            #expect(events.count == 2)
            #expect(events[0].data == "hello")
            #expect(events[1].data == "world")
            #expect(events[1].id == "1")
        }

        // MARK: - D. Reconnect with Last-Event-ID + cancellation

        @Test func reconnectSendsLastEventIDHeader() async throws {
            // First request (no Last-Event-ID) → id:7 + data:a; second request
            // (Last-Event-ID: 7) → data:b. maxReconnectAttempts: 1 → stops
            // after one reconnect.
            NebulaSSETestProtocol.handler.withLock { $0 = { req in
                if req.value(forHTTPHeaderField: "Last-Event-ID") == "7" {
                    return Data("data: b\n\n".utf8)
                }
                return Data("id: 7\ndata: a\n\n".utf8)
            } }
            let request = URLRequest(url: URL(string: "https://test.test/sse")!)
            let stream = NebulaSSEEventStream.events(
                for: request, session: makeSession(),
                configuration: NebulaSSEConfiguration(reconnect: true,
                                                    maxReconnectAttempts: 1,
                                                    reconnectDelay: .milliseconds(1),
                                                    sleeper: instantSleeper))
            var events: [NebulaSSEEvent] = []
            for try await event in stream { events.append(event) }
            #expect(events.count == 2)
            #expect(events[0].data == "a")
            #expect(events[1].data == "b")
            // The second recorded request must carry the cursor header.
            let recorded = NebulaSSETestProtocol.recorded.withLock { $0 }
            #expect(recorded.count >= 2)
            #expect(recorded.last?.value(forHTTPHeaderField: "Last-Event-ID") == "7")
        }

        @Test func cancellationEndsTheStreamGracefully() async throws {
            // A hanging connection (the test URLProtocol sends the header but
            // never the body) keeps the internal loop blocked in
            // `bytes(for:)`. Cancelling the consumer's Task must end the
            // iteration promptly (no hang, no retry storm): the consumer's
            // `for try await` ends normally — `AsyncThrowingStream.Iterator`
            // returns `nil` on consumer cancellation (it does NOT throw
            // `CancellationError`), and `onTermination` cancels the internal
            // loop so the `bytes(for:)` task is torn down. The internal loop's
            // `finish(throwing: CancellationError())` is a no-op for the
            // consumer, which has already stopped.
            NebulaSSETestProtocol.hang.withLock { $0 = true }
            defer { NebulaSSETestProtocol.hang.withLock { $0 = false } }
            let request = URLRequest(url: URL(string: "https://test.test/sse")!)
            let stream = NebulaSSEEventStream.events(
                for: request, session: makeSession(),
                configuration: NebulaSSEConfiguration(reconnect: true,
                                                    maxReconnectAttempts: 10,
                                                    reconnectDelay: .seconds(10)))
            let task = Task { () -> [NebulaSSEEvent] in
                var events: [NebulaSSEEvent] = []
                for try await event in stream { events.append(event) }
                return events
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            task.cancel()
            // Returns promptly — the consumer's loop ends normally on cancel.
            let events = try await task.value
            #expect(events == [])   // the hanging connection yields no events
        }

        // MARK: - E. Error mapping

        @Test func transportErrorMapsToConnectFailed() async throws {
            serveThrow(URLError(.cannotConnectToHost))
            let request = URLRequest(url: URL(string: "https://test.test/sse")!)
            let stream = NebulaSSEEventStream.events(
                for: request, session: makeSession(),
                configuration: NebulaSSEConfiguration(reconnect: false, sleeper: instantSleeper))
            await #expect(throws: NebulaSSEError.self) {
                for try await _ in stream {}
            }
        }
    }

    // MARK: - Error type checks (no live network)

    @Test func sseErrorCoarseKindAndBridge() {
        let err = NebulaSSEError.connectFailed("boom")
        #expect(err.coarseKind == .network)
        #expect(err.kind == .connectFailed)
        let bridged = err.toNebulaError(kind: err.coarseKind)
        #expect(bridged.code.domain == "Nebula.NebulaSSEError")
        #expect(bridged.metadata["NebulaCode"] == "connect-failed")
    }

    @Test func sseErrorCancelledIsUnknown() {
        #expect(NebulaSSEError.cancelled().coarseKind == .unknown)
    }
}