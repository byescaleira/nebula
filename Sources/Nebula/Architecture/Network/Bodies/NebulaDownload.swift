//
//  NebulaDownload.swift
//  Nebula
//
//  Wave N17c — Bodies & downloads. A download façade over
//  `URLSession.download(for:delegate:)` (an async overlay returning a temp-file
//  `URL` that is deleted when the call returns — the caller must move it
//  before returning). ``NebulaDownload/download(for:session:configuration:)``
//  returns a ``NebulaDownloadHandle`` exposing:
//   - `progress: AsyncThrowingStream<Double, any Error>` — fraction 0.0–1.0,
//     bridged from the `URLSessionDownloadDelegate` byte-count callbacks
//     (Foundation has NO async `for await` progress API — verified);
//   - `value() async throws -> URL` — the moved destination file URL.
//
//  Delegate routing: the `delegate:` passed to `download(for:delegate:)` is a
//  per-task delegate that receives the `URLSessionDownloadDelegate` callbacks
//  (didFinishDownloadingTo / didWriteData / didCompleteWithError). SSL/TLS
//  pinning rides the **session** delegate (set at `URLSession(init:)` — the
//  server-trust auth challenge is a session-level `URLSessionDelegate`
//  method, dispatched to the session delegate, not the per-task delegate). So
//  ``NebulaDownloadDelegate`` holds no pinning logic — pinning is the session
//  delegate's concern (the N17a ``NebulaURLSessionDelegate``), wired by
//  ``NebulaDownload/pinned(by:sessionConfiguration:configuration:logger:)``.
//  **Zero N17a source change, zero pinning-logic duplication, no `import Security`.**
//
//  Resume: a failed download's `URLError.downloadTaskResumeData` is read by the
//  retry loop and replayed via `URLSession.download(resumeFrom:)`. There is NO
//  async `cancel(byProducingResumeData:)` (the completion-handler form is the
//  only one), so the explicit cancel-with-resume entry
//  ``NebulaDownloadHandle/cancelByProducingResumeData()`` wraps it in a
//  `withCheckedContinuation` (the N17b `sendPing` precedent); the underlying
//  `URLSessionDownloadTask` is captured in the delegate (Foundation does not
//  expose the task from the async overlay). A caller-supplied resume blob is
//  replayed via ``NebulaDownload/resume(from:session:configuration:)``.
//
//  The retry-with-resume loop is **custom** (NOT ``NebulaRetry/withPolicy``):
//  the resume `Data` mutates the attempt (`download(resumeFrom:)` instead of
//  `download(for:)`), and `withPolicy`'s `operation` is nullary — it cannot
//  carry the resume data between attempts. The loop mirrors `withPolicy`'s
//  cancellation contract — cancellation is honored immediately and **never
//  retried**. The consumer's `for try await` over `progress` ends **normally**
//  on cancellation (an `AsyncThrowingStream` does not throw `CancellationError`
//  to its consumer); `value()` throws `CancellationError`. `onTermination`
//  cancels the internal loop.
//
//  `NebulaDownloadDelegate` is a `final class : NSObject,
//  URLSessionDownloadDelegate, Sendable` — `Sendable` is **derived** (all
//  stored props are immutable `let`s of Sendable type, including the `Mutex`
//  box; `URLSessionDownloadDelegate` is an `@objc` protocol NOT annotated
//  `NS_SWIFT_SENDABLE`, but conformance does NOT block derived `Sendable` on a
//  `final class` with all-`let` Sendable props — the N17b analogy). Probed
//  against the Xcode 27 Beta 3 SDK with
//  `swiftc -typecheck -swift-version 6 -strict-concurrency=complete
//  -warnings-as-errors` → EXIT=0. **No `@unchecked`.**
//
//  All symbols are below the `.v26` floor on every platform
//  (`URLSession.download(for:delegate:)` is macOS 12 / iOS 15 / watchOS 8 /
//  tvOS 15 / visionOS 1.0+; `URLError.downloadTaskResumeData` is macOS 10.15 /
//  iOS 13 / watchOS 6 / tvOS 13; `cancel(byProducingResumeData:)` is macOS
//  10.9 / iOS 7 / watchOS 2 / tvOS 9) — **no `@available` gate**. `import
//  Foundation` + `import Synchronization` only. See
//  vault/03-padroes/nebula-bodies-downloads.md.
//

import Foundation
import Synchronization

/// Configuration for ``NebulaDownload``.
///
/// `Sendable` but **NOT `Equatable`** — the `destination` closure is a
/// `@Sendable` closure (mirroring ``NebulaSSEConfiguration``'s not-`Equatable`
/// sleeper flavor). This is a **per-call** value (passed to
/// ``NebulaDownload/download(for:session:configuration:)``), not a
/// process-wide accessor — there is no `Mutex<NebulaDownloadConfiguration>`
/// accessor (unlike the process-wide logging/measurement/error configs).
public struct NebulaDownloadConfiguration: Sendable {

    /// Moves the temp-file `URL` to a destination `URL`, returning it. The
    /// façade performs the `FileManager.moveItem`; this closure only computes
    /// the destination (it receives the temp URL + the response — e.g. to read
    /// a `Content-Disposition` filename). The default returns a unique file in
    /// the temporary directory.
    public let destination: @Sendable (URL, URLResponse) throws -> URL

    /// Whether to retry a failed download with resume data when the server/
    /// transport provides it. `true` by default.
    public let resume: Bool

    /// The maximum resume-retry attempts before giving up (`0` = no
    /// resume-retry). Defaults to `3`.
    public let maxResumeAttempts: Int

    /// The delay between resume-retry attempts.
    public let resumeDelay: Duration

    /// The sleeper — injectable for tests (default ``NebulaRetry/defaultSleep``).
    public let sleeper: @Sendable (Duration) async throws -> Void

    /// An optional logger for download diagnostics (`nil` = silent).
    public let logger: NebulaLogger?

    /// Creates the configuration.
    public init(
        destination: @escaping @Sendable (URL, URLResponse) throws -> URL = NebulaDownloadConfiguration.defaultDestination,
        resume: Bool = true,
        maxResumeAttempts: Int = 3,
        resumeDelay: Duration = .milliseconds(500),
        sleeper: @Sendable @escaping (Duration) async throws -> Void = NebulaRetry.defaultSleep,
        logger: NebulaLogger? = nil
    ) {
        self.destination = destination
        self.resume = resume
        self.maxResumeAttempts = maxResumeAttempts
        self.resumeDelay = resumeDelay
        self.sleeper = sleeper
        self.logger = logger
    }

    /// The default configuration.
    public static let `default`: NebulaDownloadConfiguration = .init()

    /// The default destination — a unique `NebulaDownload-<hex>.bin` in the
    /// temporary directory (a safe no-op default so the façade works without a
    /// caller-supplied destination; the app overrides via ``withDestination``).
    public static let defaultDestination: @Sendable (URL, URLResponse) throws -> URL = { _, _ in
        let random = Data((0..<8).map { _ in UInt8.random(in: 0...255) }).nebulaHexEncodedString()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-\(random).bin")
    }

    /// Returns a copy with `destination` replaced.
    public func withDestination(_ destination: @escaping @Sendable (URL, URLResponse) throws -> URL) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }

    /// Returns a copy with `resume` replaced.
    public func withResume(_ resume: Bool) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }

    /// Returns a copy with `maxResumeAttempts` replaced.
    public func withMaxResumeAttempts(_ maxResumeAttempts: Int) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }

    /// Returns a copy with `resumeDelay` replaced.
    public func withResumeDelay(_ resumeDelay: Duration) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }

    /// Returns a copy with `sleeper` replaced.
    public func withSleeper(_ sleeper: @Sendable @escaping (Duration) async throws -> Void) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }

    /// Returns a copy with `logger` replaced.
    public func withLogger(_ logger: NebulaLogger?) -> NebulaDownloadConfiguration {
        .init(destination: destination, resume: resume, maxResumeAttempts: maxResumeAttempts, resumeDelay: resumeDelay, sleeper: sleeper, logger: logger)
    }
}

/// A single-consumer completion box — delivers the moved destination `URL`
/// (or an error) to ``NebulaDownloadHandle/value()``. Race-safe: if the
/// delegate resolves before `value()` registers, the result is stored and
/// delivered to the late registrant; if `value()` registers first, the
/// continuation is resumed on resolve.
internal final class NebulaDownloadCompletion: Sendable {

    private enum State: Sendable {
        case pending
        case awaiting(CheckedContinuation<URL, any Error>)
        case resolved(Result<URL, any Error>)
    }

    private let mutex: Mutex<State>

    init() { mutex = Mutex(.pending) }

    /// Awaits the result. Safe to call once (the handle is single-consumer).
    func value() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            mutex.withLock { state in
                switch state {
                case .pending:
                    state = .awaiting(continuation)
                case .resolved(let result):
                    continuation.resume(with: result)
                case .awaiting:
                    // A second await — not supported (single-consumer). Fail fast.
                    continuation.resume(throwing: NebulaDownloadError.unknown("value() called more than once"))
                }
            }
        }
    }

    /// Resolves the box with `result`. Idempotent.
    func resolve(_ result: Result<URL, any Error>) {
        mutex.withLock { state in
            switch state {
            case .pending:
                state = .resolved(result)
            case .awaiting(let continuation):
                state = .resolved(result)
                continuation.resume(with: result)
            case .resolved:
                break   // idempotent
            }
        }
    }
}

/// The consumer-facing handle for a download.
///
/// `progress` yields fractions 0.0–1.0 (bridged from
/// `URLSessionDownloadDelegate.didWriteData`) and finishes on completion,
/// failure, or cancellation. ``value()`` awaits the moved destination file URL
/// (the temp-file URL `URLSession.download(for:)` returns is moved to the
/// ``NebulaDownloadConfiguration/destination`` before the call returns, so the
/// façade ignores that returned URL — the delegate is the source of truth).
/// ``cancelByProducingResumeData()`` requests resume data from the underlying
/// `URLSessionDownloadTask` (the explicit cancel-with-resume path; the async
/// `download(for:)` overlay does not expose the task).
///
/// `Sendable` is derived — the stored props are `let`s of Sendable type (the
/// progress stream, the completion box, the delegate which derives
/// `Sendable`). **No `@unchecked`.**
public struct NebulaDownloadHandle: Sendable {

    /// The download progress as a fraction 0.0–1.0. Finishes on completion,
    /// failure, or cancellation (the consumer's `for try await` ends normally
    /// on cancellation — it does not throw `CancellationError`).
    public let progress: AsyncThrowingStream<Double, any Error>

    internal let completion: NebulaDownloadCompletion
    internal let delegate: NebulaDownloadDelegate
    internal let loop: Task<Void, Never>

    /// Awaits the moved destination file URL. Throws `CancellationError` on
    /// consumer cancellation, or a ``NebulaDownloadError`` on failure.
    public func value() async throws -> URL {
        try await completion.value()
    }

    /// Requests resume data from the underlying `URLSessionDownloadTask`,
    /// cancelling the download. Returns the resume blob (or `nil` if no resume
    /// data was produced / the task has already finished). The caller can
    /// replay it later via ``NebulaDownload/resume(from:session:configuration:)``.
    /// There is NO async `cancel(byProducingResumeData:)` — the
    /// completion-handler form is wrapped in a `withCheckedContinuation` (the
    /// N17b `sendPing` precedent).
    public func cancelByProducingResumeData() async throws -> Data? {
        guard let task = delegate.downloadTask else { return nil }
        return await withCheckedContinuation { continuation in
            task.cancel(byProducingResumeData: { resumeData in
                continuation.resume(returning: resumeData)
            })
        }
    }
}

/// A `final class : NSObject, URLSessionDownloadDelegate, Sendable` that
/// bridges the per-task download delegate callbacks into a progress stream +
/// a completion box.
///
/// This is the **per-task** delegate (passed to `URLSession.download(for:delegate:)`):
/// it receives `URLSessionDownloadDelegate` callbacks. SSL/TLS pinning rides
/// the **session** delegate (a separate `NebulaURLSessionDelegate` set at
/// session init), so this class holds no pinning logic. ONE object per
/// download (fresh per call). `Sendable` is **derived** (all stored props are
/// immutable `let`s of Sendable type, including the `Mutex` box;
/// `URLSessionDownloadDelegate` is an `@objc` protocol NOT annotated
/// `NS_SWIFT_SENDABLE`, but conformance does not block derived `Sendable` on a
/// `final class` with all-`let` Sendable props — probed EXIT=0). **No
/// `@unchecked`.**
public final class NebulaDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

    /// The per-call configuration.
    public let configuration: NebulaDownloadConfiguration

    /// The progress-stream continuation (from `AsyncThrowingStream.makeStream()`).
    internal let progressContinuation: AsyncThrowingStream<Double, any Error>.Continuation

    /// The completion box delivering the moved URL / error to `value()`.
    internal let completion: NebulaDownloadCompletion

    /// The underlying `URLSessionDownloadTask` (captured from the delegate
    /// callbacks, since the async `download(for:)` overlay does not expose it).
    /// Held in a `Mutex` (a `weak var` would break derived `Sendable`); the
    /// task is `NS_SWIFT_SENDABLE` (`NSURLSession.h:928`), so the box is
    /// `Sendable`.
    internal let downloadTaskBox: Mutex<URLSessionDownloadTask?>

    /// Creates the delegate. Internal — constructed by ``NebulaDownload``;
    /// tests construct it via `@testable`.
    init(
        configuration: NebulaDownloadConfiguration,
        progressContinuation: AsyncThrowingStream<Double, any Error>.Continuation,
        completion: NebulaDownloadCompletion
    ) {
        self.configuration = configuration
        self.progressContinuation = progressContinuation
        self.completion = completion
        self.downloadTaskBox = Mutex(nil)
        super.init()
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Capture the task for cancelByProducingResumeData (idempotent set).
        captureTask(downloadTask)
        // Move the temp file to the destination, then resolve the completion.
        do {
            // `response` is `URLResponse?` — provide a fallback if absent.
            let response = downloadTask.response
                ?? URLResponse(url: location, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            let destination = try configuration.destination(location, response)
            // Overwrite-safe: remove an existing file first.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            completion.resolve(.success(destination))
        } catch {
            let box = NebulaError.Box(NebulaError(error: error))
            completion.resolve(.failure(NebulaDownloadError.moveFailed(
                "Move to destination failed: \(error.localizedDescription)", underlying: box)))
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Capture the task for cancelByProducingResumeData (first callback).
        captureTask(downloadTask)
        guard totalBytesExpectedToWrite > 0 else { return }   // unknown total → no fraction
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressContinuation.yield(min(max(fraction, 0), 1))
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        // Resume offset callback — informational only; Nebula does not surface
        // it (the resume blob is opaque). The progress fraction resumes from
        // the resumed byte count on subsequent didWriteData callbacks.
        captureTask(downloadTask)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // The async `download(for:)` overlay throws the error to the loop,
        // which handles resume-retry / final failure. The delegate only needs
        // to capture the download task for cancelByProducingResumeData.
        if let downloadTask = task as? URLSessionDownloadTask {
            captureTask(downloadTask)
        }
    }

    /// The captured download task (for cancelByProducingResumeData).
    internal var downloadTask: URLSessionDownloadTask? {
        downloadTaskBox.withLock { $0 }
    }

    /// Captures the task once (idempotent).
    private func captureTask(_ task: URLSessionDownloadTask) {
        downloadTaskBox.withLock { current in
            if current == nil { current = task }
        }
    }

    /// Finishes the progress stream (called by the loop on terminal paths).
    internal func finishProgress(throwing error: (any Error)? = nil) {
        if let error {
            progressContinuation.finish(throwing: error)
        } else {
            progressContinuation.finish()
        }
    }
}

/// A download façade over `URLSession.download(for:delegate:)`.
///
/// ``download(for:session:configuration:)`` returns a ``NebulaDownloadHandle``
/// (`progress` stream + `value()`); the internal loop drives the download and
/// retries with resume data on failure (custom loop — NOT
/// ``NebulaRetry/withPolicy``, since the resume blob mutates the attempt).
/// Cancellation is honored immediately and never retried; the consumer's
/// `for try await` over `progress` ends normally on cancel, and `value()`
/// throws `CancellationError`. When the consumer stops iterating,
/// `onTermination` cancels the internal loop so the download task is torn down.
public enum NebulaDownload {

    /// Starts a download for `request`, returning a ``NebulaDownloadHandle``.
    ///
    /// - Parameters:
    ///   - request: the download request.
    ///   - session: the `URLSession` (default `.shared`; pass a pinned session
    ///     built via ``pinned(by:sessionConfiguration:configuration:logger:)``
    ///     for SSL/TLS pinning — pinning rides the session's delegate).
    ///   - configuration: the destination + resume behavior (default
    ///     ``NebulaDownloadConfiguration/default``).
    public static func download(
        for request: URLRequest,
        session: URLSession = .shared,
        configuration: NebulaDownloadConfiguration = .default
    ) -> NebulaDownloadHandle {
        let (progress, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        let delegate = NebulaDownloadDelegate(
            configuration: configuration,
            progressContinuation: continuation,
            completion: completion)

        let loop = Task {
            var attemptsLeft = configuration.maxResumeAttempts
            var resumeData: Data? = nil
            while true {
                do {
                    try Task.checkCancellation()
                    // The async overlay returns a temp-file URL that the
                    // delegate has already moved in didFinishDownloadingTo —
                    // ignore the returned URL; value() resolves from the
                    // delegate's completion box.
                    if let resume = resumeData {
                        _ = try await session.download(resumeFrom: resume, delegate: delegate)
                    } else {
                        _ = try await session.download(for: request, delegate: delegate)
                    }
                    // Success: the delegate resolved the completion with the
                    // moved destination; finish the progress stream cleanly.
                    delegate.finishProgress()
                    return
                } catch is CancellationError {
                    delegate.finishProgress()
                    completion.resolve(.failure(CancellationError()))
                    return
                } catch let error as URLError where error.code == .cancelled {
                    // Consumer cancellation surfaces as URLError(.cancelled).
                    delegate.finishProgress()
                    completion.resolve(.failure(CancellationError()))
                    return
                } catch {
                    // Failure: extract resume data for a retry (if configured).
                    let resume = (error as? URLError)?.downloadTaskResumeData
                    guard configuration.resume, let resume,
                          attemptsLeft > 0 else {
                        let box = NebulaError.Box(NebulaError(error: error))
                        let dlError = NebulaDownloadError.downloadFailed(
                            "Download failed: \(error.localizedDescription)", underlying: box)
                        delegate.finishProgress(throwing: dlError)
                        completion.resolve(.failure(dlError))
                        return
                    }
                    attemptsLeft -= 1
                    resumeData = resume
                    do {
                        try Task.checkCancellation()
                        try await configuration.sleeper(configuration.resumeDelay)
                    } catch {
                        delegate.finishProgress()
                        completion.resolve(.failure(CancellationError()))
                        return
                    }
                }
            }
        }

        continuation.onTermination = { @Sendable _ in loop.cancel() }
        return NebulaDownloadHandle(progress: progress, completion: completion, delegate: delegate, loop: loop)
    }

    /// Resumes a download from `resumeData` (a blob previously obtained via
    /// ``NebulaDownloadHandle/cancelByProducingResumeData()`` or a failed
    /// download's `URLError.downloadTaskResumeData`), returning a new handle.
    public static func resume(
        from resumeData: Data,
        session: URLSession = .shared,
        configuration: NebulaDownloadConfiguration = .default
    ) -> NebulaDownloadHandle {
        let (progress, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        let delegate = NebulaDownloadDelegate(
            configuration: configuration,
            progressContinuation: continuation,
            completion: completion)

        let loop = Task {
            do {
                try Task.checkCancellation()
                _ = try await session.download(resumeFrom: resumeData, delegate: delegate)
                delegate.finishProgress()
            } catch is CancellationError {
                delegate.finishProgress()
                completion.resolve(.failure(CancellationError()))
            } catch let error as URLError where error.code == .cancelled {
                delegate.finishProgress()
                completion.resolve(.failure(CancellationError()))
            } catch {
                let box = NebulaError.Box(NebulaError(error: error))
                let dlError = NebulaDownloadError.resumeFailed(
                    "Resume failed: \(error.localizedDescription)", underlying: box)
                delegate.finishProgress(throwing: dlError)
                completion.resolve(.failure(dlError))
            }
        }
        continuation.onTermination = { @Sendable _ in loop.cancel() }
        return NebulaDownloadHandle(progress: progress, completion: completion, delegate: delegate, loop: loop)
    }

    // MARK: - Pinned-session builder

    /// A `URLSession` paired with the N17a ``NebulaURLSessionDelegate`` that
    /// evaluates its server-trust challenges. `URLSession` does NOT strongly
    /// retain its delegate, so the caller must retain the delegate (this pair
    /// does). Pass `session` to ``download(for:session:configuration:)`` — the
    /// per-task download delegate is created fresh per download; pinning rides
    /// this session delegate.
    public struct PinnedDownloadSession: Sendable {
        /// The pinned `URLSession`.
        public let session: URLSession
        /// The pinning session delegate (retain it).
        public let pinningDelegate: NebulaURLSessionDelegate

        /// Creates the pair.
        public init(session: URLSession, pinningDelegate: NebulaURLSessionDelegate) {
            self.session = session
            self.pinningDelegate = pinningDelegate
        }
    }

    /// Creates a `URLSession` whose session delegate evaluates server trust
    /// against `pinning` (via the N17a ``NebulaURLSessionDelegate``). Pass the
    /// returned `session` to ``download(for:session:configuration:)`` — the
    /// per-task download delegate (fresh per download) receives the download
    /// callbacks, while this session delegate handles SSL/TLS pinning.
    /// **Zero N17a source change.**
    public static func pinned(
        by pinning: NebulaSSLPinning,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        configuration: NebulaDownloadConfiguration = .default,
        logger: NebulaLogger? = nil
    ) -> PinnedDownloadSession {
        let pinningDelegate = NebulaURLSessionDelegate(pinning: pinning, logger: logger)
        let session = URLSession(configuration: sessionConfiguration, delegate: pinningDelegate, delegateQueue: nil)
        return PinnedDownloadSession(session: session, pinningDelegate: pinningDelegate)
    }
}