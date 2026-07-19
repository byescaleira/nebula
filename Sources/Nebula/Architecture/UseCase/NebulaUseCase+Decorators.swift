//
//  NebulaUseCase+Decorators.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. Higher-order decorators that wrap a
//  ``NebulaUseCase`` body with a cross-cutting concern, returning a new use
//  case. Each decorator routes to ONE of the existing process-wide configs (log
//  / measure / error) — NO fifth `NebulaUseCaseConfig` is introduced (decision
//  #7). `.instrumented()` composes the three in the canonical order
//  `reported().measured().logged()`. Mirrors the Cosmos decorator precedent
//  WITHOUT SwiftUI. See vault/03-padroes/nebula-usecase.md.
//

import Foundation

extension NebulaUseCase {

    /// A short `String` label for this use case's `name`, used in log messages.
    private var label: String { String(describing: name) }

    // MARK: - Logged

    /// Returns a use case that logs start/success/error around the body via
    /// `logger` (defaults to the process-wide logging config's logger).
    public func logged(using logger: NebulaLogger = NebulaLogConfig.get().logger()) -> NebulaUseCase<I, O> {
        let original = self
        return NebulaUseCase<I, O>(name: name, role: role) { input in
            logger.debug("\(original.label) start")
            do {
                let output = try await original.body(input)
                logger.info("\(original.label) ok")
                return output
            } catch {
                logger.error("\(original.label) error")
                throw error
            }
        }
    }

    // MARK: - Measured

    /// Returns a use case that times the body under `measure` (defaults to
    /// `.default`), forwarding the `StaticString` ``name`` as the signpost label.
    /// Timing always runs; signpost emission is gated by the measure config.
    public func measured(using measure: NebulaMeasureConfiguration = .default) -> NebulaUseCase<I, O> {
        let original = self
        return NebulaUseCase<I, O>(name: name, role: role) { input in
            // The async `measure` overload is `rethrows` and returns `(T, Duration)`.
            let (output, _) = try await measure.measure(name) { try await original.body(input) }
            return output
        }
    }

    // MARK: - Reported

    /// Returns a use case that reports any thrown error through `errorConfig`
    /// (defaults to `.default`), re-throwing the original error after reporting.
    public func reported(using errorConfig: NebulaErrorConfiguration = .default) -> NebulaUseCase<I, O> {
        let original = self
        return NebulaUseCase<I, O>(name: name, role: role) { input in
            do {
                return try await original.body(input)
            } catch {
                errorConfig.report(NebulaError(error: error))
                throw error
            }
        }
    }

    // MARK: - Instrumented (composite)

    /// Returns a use case composed of `reported().measured().logged()` (canonical
    /// order: logged wraps measured wraps reported wraps the original body).
    ///
    /// Each concern defaults to its process-wide config when `nil` is passed, so
    /// `instrumented()` instruments all three with defaults. Pass an explicit
    /// value to override one concern; to opt OUT of a concern entirely, call the
    /// individual decorator instead.
    public func instrumented(
        using logger: NebulaLogger? = nil,
        measure: NebulaMeasureConfiguration? = nil,
        error errorConfig: NebulaErrorConfiguration? = nil
    ) -> NebulaUseCase<I, O> {
        let log = logger ?? NebulaLogConfig.get().logger()
        let measureCfg = measure ?? .default
        let cfg = errorConfig ?? .default
        return reported(using: cfg).measured(using: measureCfg).logged(using: log)
    }
}