//
//  NebulaSpyRouter.swift
//  Nebula
//
//  Wave I — Presentation architecture (Foundation-only seams). A spy router for
//  tests: records every navigation intent it receives as a value, asserting
//  what the system-under-test drove. A `final class` with a `let Mutex<[Intent]>`
//  buffer; `Sendable` is **derived** (a `final class` whose stored properties are
//  all immutable `let` of `Sendable` types synthesizes `Sendable` — no
//  `@unchecked`), so a spy can be shared across tasks. Mirrors the
//  ``NebulaSpyUseCase`` shape (decision #8). The recorded `Intent` enum is
//  `Sendable`/`Equatable` (derived from `Route`), so intents assert with
//  `#expect(spy.intents() == [.push(.detail(id:)), .pop()])`. Conforms to
//  ``NebulaRouter`` so it is a drop-in substitute for the port in a viewmodel's
//  constructor. See vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation
import Synchronization

/// A spy router: records every navigation intent it receives.
///
/// A `final class` with a `let Mutex<[Intent]>` buffer. `Sendable` is
/// **derived** — a `final class` whose stored properties are all immutable `let`
/// of `Sendable` types synthesizes `Sendable` (no `@unchecked`), so a spy can be
/// shared across tasks (mirrors ``NebulaSpyUseCase``). Conforms to
/// ``NebulaRouter`` so it is a drop-in substitute for the port when testing a
/// viewmodel that takes `any NebulaRouter<Route>` via constructor injection.
///
/// ```swift
/// let spy = NebulaSpyRouter<AppRoute>()
/// let vm = ProfileViewModel(useCase: stub, router: spy)
/// vm.openDetail(id)
/// vm.goBack()
/// #expect(spy.intents() == [.push(.detail(id: id)), .pop(1)])
/// #expect(spy.callCount == 2)
/// ```
public final class NebulaSpyRouter<Route: NebulaRoute>: NebulaRouter<Route>, Sendable {

    /// A recorded navigation intent — a value, so intents assert with `==`.
    public enum Intent: Sendable, Equatable {
        case push(Route)
        case pop(Int)
        case popToRoot
        case replaceStack([Route])
    }

    private let invocations = Mutex<[Intent]>([])

    /// Creates a spy router.
    public init() {}

    /// The number of intents recorded so far.
    public var callCount: Int {
        invocations.withLock { $0.count }
    }

    /// A snapshot of the recorded intents, in call order.
    public func intents() -> [Intent] {
        invocations.withLock { $0 }
    }

    public func push(_ route: Route) {
        invocations.withLock { $0.append(.push(route)) }
    }

    public func pop() {
        invocations.withLock { $0.append(.pop(1)) }
    }

    public func pop(_ count: Int) {
        invocations.withLock { $0.append(.pop(count)) }
    }

    public func popToRoot() {
        invocations.withLock { $0.append(.popToRoot) }
    }

    public func replaceStack(with routes: [Route]) {
        invocations.withLock { $0.append(.replaceStack(routes)) }
    }
}