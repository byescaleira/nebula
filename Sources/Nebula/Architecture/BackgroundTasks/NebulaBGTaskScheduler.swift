//
//  NebulaBGTaskScheduler.swift
//  Nebula
//
//  Wave N15b — App-readiness. The concrete adapter over `BGTaskScheduler.shared`:
//  a `final class : Sendable` (NO `NSObject` base — there is no `@objc` protocol
//  to back, unlike ``NebulaUNNotificationCenter``'s `UNUserNotificationCenterDelegate`)
//  that conforms to ``NebulaBackgroundTaskScheduler`` (the scheduling surface) and
//  bridges the system's launch callback to the `@Sendable` ``launch`` handler in
//  ``NebulaBackgroundTaskConfiguration``.
//
//  Platform gate — established N15b precedent: `BackgroundTasks.framework` is
//  physically present on all 5 SDKs but its symbols are
//  `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)`. A `#if canImport(BackgroundTasks)`
//  gate is REJECTED — `canImport` is `true` on macOS/watchOS (the framework is
//  present) so it gates nothing, and the unavailable symbol references then fail.
//  The compile-safe gate is a **type-level** `@available(macOS, unavailable)
//  @available(watchOS, unavailable)` DECLARATION on this Nebula façade (the
//  ``NebulaLogStoreExporter`` precedent): declaring a NEBULA symbol unavailable
//  suppresses body type-checking on macOS/watchOS, so the unavailable
//  `BGTaskScheduler.shared` reference inside isn't validated there. This is the
//  complement to N15a's `#if !os(<platform>)` (which excludes an SDK symbol from
//  a build when a declaration gate can't apply). `@available(macOS 26, unavailable)`
//  is a syntax error — `unavailable` takes no version.
//
//  Sendability — the hard part, empirically resolved (correction from the
//  N15b plan). The non-`Sendable` `BGTask` the system delivers inside the
//  `@Sendable` launch callback CANNOT be moved directly into a `Mutex`
//  (`Mutex<[String: BGTask]>` with `withLock { $0[id] = task }` fails whole-module
//  Swift 6 with `'inout sending' parameter '$0' cannot be task-isolated` — a
//  region-isolation wall: a non-Sendable class arriving as a closure param can't
//  be `sending`-transferred into a Mutex region the compiler can't prove is
//  exclusive). The ``NebulaDefaults`` `Mutex<non-Sendable>` precedent does NOT
//  apply there — `UserDefaults.standard` arrives at a public `sending` API the
//  caller asserts; `BGTask` arrives in a closure where exclusivity is unprovable.
//
//  Resolution — a minimal `final class @unchecked Sendable` ``NebulaBGTaskBox``
//  reference-type wrapper holding the `BGTask` as a **plain `let`** (no Mutex, no
//  `sending` init — the plain stored-property init compiles). This is the
//  documented ``NebulaMemoryLogHandler`` precedent: "the only `@unchecked` type
//  … justified by the lock and safe because it is a reference type, not a
//  Nebula-defined value type." The binding forbids `@unchecked` on VALUE types;
//  a reference type backed by an immutable, once-assigned system class is the
//  permitted exception. The box is `@unchecked Sendable` so it crosses isolation;
//  the façade then holds `Mutex<[String: NebulaBGTaskBox]>` — the box IS Sendable,
//  so storing boxes in the Mutex is a Sendable-in / Sendable-out operation with NO
//  region wall, and the `Mutex` (and thus the façade) is `Sendable` **derived**
//  (no `@unchecked` on the façade). The Sendable ``NebulaBackgroundTask`` handle's
//  closures capture the SENDABLE façade + identifier (NOT the `BGTask`), reach the
//  box via the façade's Mutex, and call the system task's lifecycle methods. So
//  `@unchecked` is isolated to the single reference-type box; the façade and the
//  handle both derive `Sendable`. `BGTaskScheduler.shared` is fetched locally per
//  call, never stored (the shared singleton can't be `sending`-consumed). See
//  vault/03-padroes/nebula-background-tasks.md and <doc:ArchitectureBackgroundTasks>.
//

import Foundation
import BackgroundTasks
import Synchronization

/// A `final class` adapter over `BGTaskScheduler.shared` that conforms to
/// ``NebulaBackgroundTaskScheduler`` (the scheduling surface) and bridges the
/// system's launch callback to the `@Sendable` ``launch`` handler in a
/// ``NebulaBackgroundTaskConfiguration``.
///
/// The façade is **macOS/watchOS-unavailable**: background tasks are an
/// iOS/tvOS/visionOS-only surface (`BGTaskScheduler` is `API_UNAVAILABLE(macos)
/// API_UNAVAILABLE(watchos)`). The type exists on all 5 platforms (so it can be
/// named in shared signatures) but is unavailable on macOS/watchOS — see the
/// header comment for the gating precedent.
///
/// When the system launches the app to perform a registered task, the façade
/// wraps the delivered `BGTask` in a ``NebulaBGTaskBox`` (an `@unchecked Sendable`
/// reference-type wrapper — the ``NebulaMemoryLogHandler`` precedent), stores the
/// box in a `Mutex<[String: NebulaBGTaskBox]>` live-task map, builds a Sendable
/// ``NebulaBackgroundTask`` handle whose completion/expiration closures reach
/// that box through the façade, and forwards the handle to
/// ``NebulaBackgroundTaskConfiguration/launch``. The app signals completion via
/// ``NebulaBackgroundTask/complete(success:)`` and assigns an expiration handler
/// via ``NebulaBackgroundTask/onExpiration(_:)``.
///
/// `Sendable` is **derived** for the façade (the stored properties are a `Sendable`
/// config and a `Mutex<[String: NebulaBGTaskBox]>`; the box is `@unchecked Sendable`
/// so the dictionary — and thus the `Mutex` — is `Sendable`). The `@unchecked` is
/// isolated to the ``NebulaBGTaskBox`` reference type (the only `@unchecked` type
/// in this layer, justified by immutability — the ``NebulaMemoryLogHandler``
/// precedent). `BGTaskScheduler.shared` is fetched locally per call, never stored.
@available(macOS, unavailable)
@available(watchOS, unavailable)
public final class NebulaBGTaskScheduler: NebulaBackgroundTaskScheduler, Sendable {

    /// The launch handler, held immutably (the config is a snapshot taken at
    /// ``init(_:)`` — swap via a new façade, or via the process-wide
    /// ``NebulaBackgroundTaskConfig`` accessor before constructing one).
    private let config: NebulaBackgroundTaskConfiguration

    /// The live system tasks, keyed by identifier. Each non-`Sendable` `BGTask` is
    /// held in an ``NebulaBGTaskBox`` (`@unchecked Sendable` — the
    /// ``NebulaMemoryLogHandler`` reference-type precedent); the box IS Sendable,
    /// so this `Mutex<[String: NebulaBGTaskBox]>` is `Sendable` **derived** and
    /// storing a box via `withLock` is a Sendable-in operation with no
    /// region-isolation wall (a raw `Mutex<[String: BGTask]>` would fail to typecheck
    /// — a non-Sendable class arriving as a launch-closure param can't be
    /// `sending`-transferred into the Mutex region). The Sendable handle's closures
    /// reach a box via `withLock` rather than by holding the `BGTask`, so no
    /// non-`Sendable` value crosses a `@Sendable` boundary.
    private let liveTasks: Mutex<[String: NebulaBGTaskBox]>

    /// Creates the adapter with `config` (`.default` → no-op launch).
    public init(_ config: NebulaBackgroundTaskConfiguration = .default) {
        self.config = config
        self.liveTasks = Mutex([:])
    }

    // MARK: - NebulaBackgroundTaskScheduler

    public func register(_ identifier: String) async -> Bool {
        // `using: nil` is explicit — the param has no default (the header: "Pass
        // `nil` to use a default background queue"). The launchHandler captures the
        // Sendable façade; it is stored by the system for the app's lifetime.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [self] task in
            self.bridgeLaunch(task)
        }
    }

    // MARK: - Launch bridge

    /// Wraps the system-delivered `BGTask` in an ``NebulaBGTaskBox``, stores the
    /// box in the live-task map, builds the Sendable handle, and forwards it to
    /// the config's `launch` handler. Called from the system's launch callback.
    private func bridgeLaunch(_ task: BGTask) {
        let identifier = task.identifier
        let kind: NebulaBackgroundTaskKind = (task is BGProcessingTask) ? .processing : .appRefresh
        // Wrap the non-Sendable BGTask in the @unchecked Sendable box (the plain
        // `let task` init compiles where a `Mutex(task)` `sending` init does not),
        // then store the SENDABLE box — no region-isolation wall.
        let box = NebulaBGTaskBox(task)
        liveTasks.withLock { $0[identifier] = box }
        let handle = NebulaBackgroundTask(
            identifier: identifier,
            kind: kind,
            finish: { [self] success in self.finishTask(identifier, success: success) },
            setExpiration: { [self] handler in self.setExpiration(identifier, handler) }
        )
        config.launch(handle)
    }

    /// Reaches `BGTask.setTaskCompleted(success:)` via the live-task map, then
    /// drops the entry (the system nils `expirationHandler` after completion).
    func finishTask(_ identifier: String, success: Bool) {
        let box: NebulaBGTaskBox? = liveTasks.withLock { tasks in
            let box = tasks[identifier]
            tasks.removeValue(forKey: identifier)
            return box
        }
        box?.task.setTaskCompleted(success: success)
    }

    /// Reaches `BGTask.expirationHandler` assignment via the live-task map.
    func setExpiration(_ identifier: String, _ handler: @escaping @Sendable () -> Void) {
        let box: NebulaBGTaskBox? = liveTasks.withLock { $0[identifier] }
        box?.task.expirationHandler = handler
    }

    public func submit(_ request: NebulaBackgroundTaskRequest) async throws {
        let bg = Self.makeBGRequest(request)
        do {
            // iOS-27 async path (OS-27 symbol → `#if swift(>=6.4)` + runtime
            // `if #available`). Under Swift 6.3 the block is absent.
            #if swift(>=6.4)
            if #available(iOS 27, tvOS 27, visionOS 27, *) {
                try await BGTaskScheduler.shared.submitTaskRequest(bg)
                return
            }
            #endif
            // iOS-26 fallback: the deprecated sync `submit(_:)` (renamed from
            // `submitTaskRequest:error:`, deprecated iOS 27). Warning-clean under
            // the `.v26` floor — deprecation warnings fire only at a deployment
            // target ≥ the obsoleted version (27 > 26).
            try BGTaskScheduler.shared.submit(bg)
        } catch {
            throw Self.mapSubmitError(error)
        }
    }

    public func cancel(_ identifier: String) async {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    public func cancelAll() async {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }

    public func pendingRequests() async -> [NebulaBackgroundTaskRequest] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[NebulaBackgroundTaskRequest], Never>) in
            // Map to Sendable Nebula values INSIDE the SDK completion (where the
            // non-Sendable `BGTaskRequest` array is delivered), then resume with
            // the Sendable result — resuming with the non-Sendable array directly
            // is a region-isolation error (the ``NebulaUNNotificationCenter``
            // precedent).
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests.map(Self.makeNebulaRequest))
            }
        }
    }

    // MARK: - Mapping (Nebula value <-> BG SDK)
    //
    // The mapping helpers are `internal` (not `private`) so the test module can
    // round-trip through them with constructible `BGAppRefreshTaskRequest` /
    // `BGProcessingTaskRequest` — covering the SDK-mapping logic WITHOUT calling
    // `BGTaskScheduler.shared`, which is non-functional in a headless test bundle
    // (no app context). Pure functions; no risk exposing them internally. They
    // are macOS/watchOS-unavailable (the façade is), so the round-trip tests
    // gate them `#if !os(macOS) && !os(watchOS)` and compile-verify on
    // iOS/tvOS/visionOS.

    /// Builds a `BGTaskRequest` subclass from a Nebula request. The
    /// processing-only conditions apply only for `.processing`.
    static func makeBGRequest(_ request: NebulaBackgroundTaskRequest) -> BGTaskRequest {
        let bg: BGTaskRequest
        switch request.kind {
        case .appRefresh:
            bg = BGAppRefreshTaskRequest(identifier: request.identifier)
        case .processing:
            let processing = BGProcessingTaskRequest(identifier: request.identifier)
            processing.requiresNetworkConnectivity = request.requiresNetworkConnectivity
            processing.requiresExternalPower = request.requiresExternalPower
            bg = processing
        }
        bg.earliestBeginDate = request.earliestBeginDate
        return bg
    }

    /// Maps a `BGTaskRequest` to a Nebula request (cast to the processing
    /// subclass for kind + conditions; anything else is treated as app refresh).
    static func makeNebulaRequest(_ request: BGTaskRequest) -> NebulaBackgroundTaskRequest {
        if let processing = request as? BGProcessingTaskRequest {
            return NebulaBackgroundTaskRequest(
                identifier: request.identifier,
                kind: .processing,
                earliestBeginDate: request.earliestBeginDate,
                requiresNetworkConnectivity: processing.requiresNetworkConnectivity,
                requiresExternalPower: processing.requiresExternalPower
            )
        }
        return NebulaBackgroundTaskRequest(
            identifier: request.identifier,
            kind: .appRefresh,
            earliestBeginDate: request.earliestBeginDate
        )
    }

    /// Maps a `BGTaskScheduler` submission error to a typed
    /// ``NebulaBackgroundTaskError`` (boxing the underlying SDK error for
    /// diagnostics).
    static func mapSubmitError(_ error: Error) -> NebulaBackgroundTaskError {
        let underlying = NebulaError.Box(NebulaError(error: error))
        if let bg = error as? BGTaskScheduler.Error {
            switch bg.code {
            case .notPermitted:
                return .notPermitted(underlying: underlying)
            case .tooManyPendingTaskRequests:
                return .tooManyPending(underlying: underlying)
            case .unavailable:
                return .unavailable(underlying: underlying)
            case .immediateRunIneligible:
                return .immediateRunIneligible(underlying: underlying)
            @unknown default:
                return .schedulingFailed(underlying: underlying)
            }
        }
        return .schedulingFailed(underlying: underlying)
    }
}

// MARK: - NebulaBGTaskBox

/// An `@unchecked Sendable` reference-type wrapper holding the system-delivered,
/// non-`Sendable` `BGTask`.
///
/// This is the **only `@unchecked` type in the background-tasks layer**, justified
/// the same way ``NebulaMemoryLogHandler`` is (the documented exception to the
/// "no `@unchecked` on a Nebula-defined type" rule): it is a **reference type**,
/// not a Nebula-defined value type, and the held `BGTask` is assigned exactly
/// once at construction (an immutable `let`) and never mutated. The box lets a
/// non-`Sendable` `BGTask` — which arrives as a parameter of the system's
/// `@Sendable` launch callback and therefore can't be `sending`-transferred
/// directly into a `Mutex` region (a whole-module Swift 6 region-isolation wall)
/// — cross isolation behind a single, audited `@unchecked` boundary. The
/// `Mutex<[String: NebulaBGTaskBox]>` on the façade then stores Sendable boxes
/// (no region wall), and the façade's `Sendable` conformance is **derived**.
///
/// Thread-safety of the `BGTask` itself: the box is built once per launch, the
/// `let task` is never reassigned, and the façade serializes per-identifier
/// access through its `Mutex` (one `finishTask`/`setExpiration` per identifier at
/// a time). `BGTask.setTaskCompleted(success:)` / `expirationHandler` are the
/// system's documented lifecycle entry points, called once per task.
@available(macOS, unavailable)
@available(watchOS, unavailable)
final class NebulaBGTaskBox: @unchecked Sendable {
    /// The wrapped system task. Immutable after init.
    let task: BGTask

    /// Wraps a system-delivered `BGTask`.
    init(_ task: BGTask) { self.task = task }
}