//
//  ArchitectureDownloadTests.swift
//  NebulaTests
//
//  Wave N17c — Bodies & downloads. Unit tests for the ``NebulaDownload``
//  façade + ``NebulaDownloadDelegate`` + ``NebulaDownloadConfiguration`` +
//  ``NebulaDownloadError``:
//  - A. configuration value semantics,
//  - B. error mapping (pure),
//  - C. delegate lifecycle + progress (synthesized callbacks — no live socket),
//  - D. handle + completion-box cancellation (synthesized — no live socket),
//  - E. resume-data extraction from a `URLError` (pure).
//
//  **Testability stance (documented limitation):** a `URLProtocol`-backed live
//  round-trip over the async `URLSession.download(for:delegate:)` temp-file
//  path hangs — `URLProtocol` does not cleanly bridge the async download
//  overlay's temp-file + `didFinishDownloadingTo` dispatch (the overlay never
//  completes). This mirrors the N17a pragmatic stance (a transport seam that
//  is not injectable from a unit test is documented rather than forced). The
//  coverage instead exercises the delegate callbacks directly (C), the
//  race-safe completion box (D), and the error/resume extraction seams (B/E)
//  — the live round-trip is a compile-only guarantee (the façade builds on all
//  5 platforms; the move-to-destination + progress + resume behavior is
//  verified at the delegate/loop seams).
//
//  `@testable import Nebula` exposes the `internal` delegate init + completion
//  box. See vault/03-padroes/nebula-bodies-downloads.md.
//

import Testing
import Foundation
import Synchronization
@testable import Nebula

// MARK: - A Sendable box so a ~Copyable Mutex can be captured in @Sendable
// closures (mirrors ArchitectureSSETests).

private final class SendableBox<T: Sendable>: Sendable {
    private let mutex: Mutex<T>
    init(_ initial: T) { mutex = Mutex<T>(initial) }
    func mutate(_ body: (inout T) -> Void) { mutex.withLock { body(&$0) } }
    var value: T { mutex.withLock { $0 } }
}

@Suite struct ArchitectureDownloadTests {

    // MARK: - A. Configuration value semantics

    @Test func configurationWithBuildersReturnDistinctCopies() {
        let base = NebulaDownloadConfiguration.default
        let noResume = base.withResume(false)
        let three = base.withMaxResumeAttempts(3)
        let fast = base.withResumeDelay(.milliseconds(10))
        // Each builder leaves the others unchanged (value semantics).
        #expect(base.resume == true)
        #expect(noResume.resume == false)
        #expect(noResume.maxResumeAttempts == base.maxResumeAttempts)
        #expect(three.maxResumeAttempts == 3)
        #expect(three.resume == base.resume)
        #expect(fast.resumeDelay == .milliseconds(10))
        #expect(fast.resume == base.resume)
    }

    @Test func defaultDestinationReturnsTemporaryDirectoryURL() throws {
        let url = try NebulaDownloadConfiguration.defaultDestination(
            FileManager.default.temporaryDirectory, URLResponse())
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(url.lastPathComponent.hasPrefix("NebulaDownload-"))
    }

    @Test func configurationIsSendableAcrossTask() async throws {
        let config = NebulaDownloadConfiguration.default.withResumeDelay(.milliseconds(1))
        let back = try await Task { config }.value
        #expect(back.resumeDelay == .milliseconds(1))
    }

    // MARK: - B. Error mapping (pure)

    @Test func downloadErrorFactoryStaticsAndCoarseKind() {
        let dl = NebulaDownloadError.downloadFailed("boom")
        #expect(dl.kind == .downloadFailed)
        #expect(dl.coarseKind == .network)
        #expect(dl.code == "download-failed")

        let move = NebulaDownloadError.moveFailed("no move")
        #expect(move.coarseKind == .network)
        #expect(move.code == "move-failed")

        let resume = NebulaDownloadError.resumeFailed("no resume")
        #expect(resume.coarseKind == .network)
        #expect(resume.code == "resume-failed")
    }

    @Test func downloadErrorCancelledIsUnknown() {
        #expect(NebulaDownloadError.cancelled().coarseKind == .unknown)
        #expect(NebulaDownloadError.unknown().coarseKind == .unknown)
    }

    @Test func downloadErrorBridgesToNebulaErrorDomain() {
        let err = NebulaDownloadError.downloadFailed("x")
        let bridged = err.toNebulaError(kind: err.coarseKind)
        #expect(bridged.code.domain == "Nebula.NebulaDownloadError")
        #expect(bridged.metadata["NebulaCode"] == "download-failed")
    }

    @Test func downloadErrorCarriesUnderlying() {
        let nsErr = NSError(domain: "Net", code: 42)
        let box = NebulaError.Box(NebulaError(error: nsErr))
        let err = NebulaDownloadError.downloadFailed("io", underlying: box)
        #expect(err.underlying != nil)
    }

    @Test func downloadErrorIsSendableAcrossTask() async throws {
        let err = NebulaDownloadError.moveFailed("x")
        let back = await Task { err }.value
        #expect(back.kind == .moveFailed)
    }

    // MARK: - C. Delegate lifecycle + progress (synthesized callbacks)

    /// A real (unstarted) download task to feed the synthesized callbacks.
    private func makeDownloadTask() -> URLSessionDownloadTask {
        URLSession.shared.downloadTask(with: URL(string: "https://example.invalid/file.bin")!)
    }

    @Test func delegateDidFinishDownloadingToMovesFileAndResolves() async throws {
        let (stream, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        // A destination in the temp dir.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-test-\(UUID().uuidString).bin")
        let config = NebulaDownloadConfiguration(destination: { _, _ in dest })
        let delegate = NebulaDownloadDelegate(
            configuration: config,
            progressContinuation: continuation,
            completion: completion)

        // Write a temp file the delegate will move.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-src-\(UUID().uuidString).bin")
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        try payload.write(to: temp)
        defer {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: dest)
        }

        let task = makeDownloadTask()
        delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: temp)

        let moved = try await completion.value()
        #expect(moved == dest)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(try Data(contentsOf: dest) == payload)
        // The source temp file is gone (moved, not copied).
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        _ = stream   // keep alive
    }

    @Test func delegateDidFinishDownloadingToMoveFailureResolvesMoveFailed() async throws {
        let (_, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        // A destination whose parent directory does not exist → moveItem throws.
        let dest = URL(fileURLWithPath: "/nonexistent-nebula-dir/\(UUID().uuidString).bin")
        let config = NebulaDownloadConfiguration(destination: { _, _ in dest })
        let delegate = NebulaDownloadDelegate(
            configuration: config, progressContinuation: continuation, completion: completion)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-src-\(UUID().uuidString).bin")
        try Data([0x09]).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        delegate.urlSession(URLSession.shared, downloadTask: makeDownloadTask(),
                            didFinishDownloadingTo: temp)

        do {
            _ = try await completion.value()
            Issue.record("expected moveFailed")
        } catch let err as NebulaDownloadError {
            #expect(err.kind == .moveFailed)
            #expect(err.coarseKind == .network)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func delegateDidWriteDataYieldsFraction() async throws {
        let (stream, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        let delegate = NebulaDownloadDelegate(
            configuration: .default, progressContinuation: continuation, completion: completion)
        let task = makeDownloadTask()

        // Collect the yielded fractions.
        let collected = SendableBox<[Double]>([])
        let observer = Task {
            for try await fraction in stream { collected.mutate { $0.append(fraction) } }
        }

        delegate.urlSession(URLSession.shared, downloadTask: task,
                            didWriteData: 50, totalBytesWritten: 50,
                            totalBytesExpectedToWrite: 200)
        delegate.urlSession(URLSession.shared, downloadTask: task,
                            didWriteData: 150, totalBytesWritten: 200,
                            totalBytesExpectedToWrite: 200)
        // Unknown total → no fraction yielded.
        delegate.urlSession(URLSession.shared, downloadTask: task,
                            didWriteData: 10, totalBytesWritten: 10,
                            totalBytesExpectedToWrite: -1)
        delegate.finishProgress()

        try await Task.sleep(nanoseconds: 50_000_000)
        observer.cancel()
        let fractions = collected.value
        #expect(fractions.count == 2)
        #expect(fractions.first.map { abs($0 - 0.25) < 0.001 } ?? false)
        #expect(fractions.last.map { abs($0 - 1.0) < 0.001 } ?? false)
    }

    @Test func delegateCapturesDownloadTaskForResumeCancel() async throws {
        let (_, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        let delegate = NebulaDownloadDelegate(
            configuration: .default, progressContinuation: continuation, completion: completion)
        let task = makeDownloadTask()
        // The didCompleteWithError path captures the download task.
        delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        #expect(delegate.downloadTask === task)
    }

    // MARK: - D. Handle + completion-box seam (synthesized — no live socket).
    // The live URLProtocol round-trip is a documented limitation (see header).
    // Consumer cancellation surfaces via the loop's cancellation handling (it
    // resumes the completion box with CancellationError from `Task.checkCancellation` /
    // the `URLError(.cancelled)` branch) — NOT via the `withCheckedThrowingContinuation`
    // auto-cancellation, which does not throw on Task cancel without a
    // `withTaskCancellationHandler` bridge. So the box is exercised at its
    // race-safe resolve/register seam.

    @Test func completionBoxResolvesBeforeValueRegistersDeliversLate() async throws {
        // The race-safe state machine: resolve() before value() registers must
        // still deliver the result to the late registrant (the delegate can
        // finish before the consumer calls value()).
        let completion = NebulaDownloadCompletion()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-race-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        completion.resolve(.success(dest))
        let resolved = try await completion.value()
        #expect(resolved == dest)
    }

    @Test func completionBoxResolvesFailureDeliversError() async throws {
        let completion = NebulaDownloadCompletion()
        completion.resolve(.failure(NebulaDownloadError.downloadFailed("boom")))
        do {
            _ = try await completion.value()
            Issue.record("expected downloadFailed")
        } catch let err as NebulaDownloadError {
            #expect(err.kind == .downloadFailed)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func completionBoxResolveIsIdempotent() async throws {
        // A second resolve() must not double-resume (it's a no-op).
        let completion = NebulaDownloadCompletion()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("NebulaDownload-idem-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        completion.resolve(.success(dest))
        completion.resolve(.failure(NebulaDownloadError.moveFailed("late")))   // ignored
        let resolved = try await completion.value()
        #expect(resolved == dest)
    }

    @Test func cancelByProducingResumeDataReturnsNilWhenTaskAbsent() async throws {
        // No task captured yet → returns nil cleanly (no crash).
        let (_, continuation) = AsyncThrowingStream<Double, any Error>.makeStream()
        let completion = NebulaDownloadCompletion()
        let delegate = NebulaDownloadDelegate(
            configuration: .default, progressContinuation: continuation, completion: completion)
        let handle = NebulaDownloadHandle(
            progress: AsyncThrowingStream { _ in }, completion: completion,
            delegate: delegate, loop: Task { })
        let resume = try await handle.cancelByProducingResumeData()
        #expect(resume == nil)
    }

    // MARK: - E. Resume-data extraction (pure — the seam the retry loop uses)

    @Test func urlErrorDownloadTaskResumeDataIsExtractable() {
        // The retry loop reads URLError.downloadTaskResumeData from the caught
        // error. Verify the seam: a URLError constructed with userInfo
        // resume-data (key `NSURLSessionDownloadTaskResumeData`) yields it —
        // the loop's `(error as? URLError)?.downloadTaskResumeData`.
        let resumeBlob = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let error = URLError(.networkConnectionLost, userInfo: [
            NSURLSessionDownloadTaskResumeData: resumeBlob
        ])
        #expect(error.downloadTaskResumeData == resumeBlob)
    }

    @Test func urlErrorWithoutResumeDataYieldsNil() {
        let error = URLError(.notConnectedToInternet)
        #expect(error.downloadTaskResumeData == nil)
    }
}