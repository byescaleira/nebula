//
//  ArchitecturePresentationTests.swift
//  NebulaTests
//
//  Wave I — Presentation architecture (Foundation-only seams). Pure-Swift tests
//  for the navigation model, the navigation-intent port, and the spy router.
//  No SwiftUI in the test graph (these are Foundation-only seams). Navigation-
//  as-data: stack ops and deep-link `replaceStack` are value assertions, no
//  simulator. See Sources/Nebula/Architecture/Presentation/.
//

import Testing
import Foundation
@testable import Nebula

// MARK: - Test routes

private enum TestRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
}

// MARK: - NebulaNavigationStack

@Suite("NebulaNavigationStack")
struct NebulaNavigationStackTests {

    @Test("push appends and updates top/count/isEmpty")
    func pushAppends() {
        var stack = NebulaNavigationStack<TestRoute>()
        #expect(stack.isEmpty)
        #expect(stack.count == 0)
        #expect(stack.top == nil)

        let id = UUID()
        stack.push(.detail(id: id))
        #expect(!stack.isEmpty)
        #expect(stack.count == 1)
        #expect(stack.top == .detail(id: id))
        #expect(stack.path == [.detail(id: id)])

        stack.push(.settings)
        #expect(stack.count == 2)
        #expect(stack.top == .settings)
        #expect(stack.path == [.detail(id: id), .settings])
    }

    @Test("pop() removes one via the port-convenience extension")
    func popOne() {
        var stack = NebulaNavigationStack<TestRoute>(path: [.root, .settings])
        stack.pop()
        #expect(stack.path == [.root])
        #expect(stack.top == .root)
    }

    @Test("pop(count:) removes the given count")
    func popCount() {
        var stack = NebulaNavigationStack<TestRoute>(path: [.root, .settings, .detail(id: UUID())])
        stack.pop(2)
        #expect(stack.path == [.root])
    }

    @Test("pop clamps to count and never underflows")
    func popClamps() {
        var stack = NebulaNavigationStack<TestRoute>(path: [.root, .settings])
        stack.pop(5)
        #expect(stack.path == [])
        #expect(stack.isEmpty)

        // Negative count is treated as zero.
        stack.push(.root)
        stack.pop(-3)
        #expect(stack.path == [.root])
    }

    @Test("popToRoot empties the stack")
    func popToRoot() {
        var stack = NebulaNavigationStack<TestRoute>(path: [.root, .settings, .detail(id: UUID())])
        stack.popToRoot()
        #expect(stack.isEmpty)
        #expect(stack.path == [])
    }

    @Test("replaceStack is the deep-link primitive")
    func replaceStack() {
        var stack = NebulaNavigationStack<TestRoute>(path: [.root, .settings])
        let id = UUID()
        stack.replaceStack(with: [.root, .detail(id: id)])
        #expect(stack.path == [.root, .detail(id: id)])
        #expect(stack.top == .detail(id: id))
    }

    @Test("static helpers mutate an inout array — single source of truth")
    func staticHelpers() {
        var path: [TestRoute] = []
        NebulaNavigationStack.push(.root, into: &path)
        NebulaNavigationStack.push(.settings, into: &path)
        #expect(path == [.root, .settings])

        NebulaNavigationStack.pop(1, into: &path)
        #expect(path == [.root])

        NebulaNavigationStack.popToRoot(&path)
        #expect(path == [])

        NebulaNavigationStack.replaceStack([.settings], into: &path)
        #expect(path == [.settings])
    }

    @Test("Equatable derives from Route")
    func equatable() {
        let id = UUID()
        let a = NebulaNavigationStack<TestRoute>(path: [.root, .detail(id: id)])
        let b = NebulaNavigationStack<TestRoute>(path: [.root, .detail(id: id)])
        let c = NebulaNavigationStack<TestRoute>(path: [.root, .settings])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable round-trip restores the stack — state restoration")
    func codableRoundTrip() throws {
        let id = UUID()
        let stack = NebulaNavigationStack<TestRoute>(path: [.root, .detail(id: id), .settings])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(stack)
        let restored = try decoder.decode(NebulaNavigationStack<TestRoute>.self, from: data)

        #expect(restored == stack)
        #expect(restored.path == [.root, .detail(id: id), .settings])
    }

    @Test("Sendable — a stack can be captured across tasks")
    func sendableAcrossTasks() async {
        let id = UUID()
        let stack = NebulaNavigationStack<TestRoute>(path: [.root, .detail(id: id)])
        // Crossing an actor boundary requires Sendable; this compiles only if the
        // derived conformance holds.
        let copied = await Task { stack }.value
        #expect(copied == stack)
    }
}

// MARK: - NebulaSpyRouter

@Suite("NebulaSpyRouter")
struct NebulaSpyRouterTests {

    @Test("records intents in call order")
    func recordsIntents() {
        let spy = NebulaSpyRouter<TestRoute>()
        let id = UUID()

        spy.push(.detail(id: id))
        spy.pop()
        spy.popToRoot()
        spy.replaceStack(with: [.root, .settings])

        #expect(spy.callCount == 4)
        #expect(spy.intents() == [
            .push(.detail(id: id)),
            .pop(1),
            .popToRoot,
            .replaceStack([.root, .settings]),
        ])
    }

    @Test("pop(_:) records the exact count")
    func popRecordsCount() {
        let spy = NebulaSpyRouter<TestRoute>()
        spy.pop(3)
        #expect(spy.intents() == [.pop(3)])
    }

    @Test("conforms to NebulaRouter — a drop-in substitute for the port")
    func routerPortConformance() async {
        let spy = NebulaSpyRouter<TestRoute>()
        // Call through the existential async port to verify dynamic dispatch
        // reaches the spy's synchronous implementations (sync witnesses async).
        let router: any NebulaRouter<TestRoute> = spy
        let id = UUID()

        await router.push(.detail(id: id))
        await router.pop()
        await router.pop(2)
        await router.popToRoot()
        await router.replaceStack(with: [.root, .settings])

        #expect(spy.intents() == [
            .push(.detail(id: id)),
            .pop(1),
            .pop(2),
            .popToRoot,
            .replaceStack([.root, .settings]),
        ])
    }

    @Test("Sendable — a spy can be shared across tasks")
    func spySendable() async {
        let spy = NebulaSpyRouter<TestRoute>()
        // Sendable derived (final class + let Mutex); sharing across tasks compiles.
        await Task { spy.push(.root) }.value
        #expect(spy.callCount == 1)
        #expect(spy.intents() == [.push(.root)])
    }

    @Test("Intent equality derives from Route")
    func intentEquality() {
        let id = UUID()
        #expect(NebulaSpyRouter<TestRoute>.Intent.push(.detail(id: id))
                == .push(.detail(id: id)))
        #expect(NebulaSpyRouter<TestRoute>.Intent.pop(1) == .pop(1))
        #expect(NebulaSpyRouter<TestRoute>.Intent.popToRoot == .popToRoot)
        #expect(NebulaSpyRouter<TestRoute>.Intent.replaceStack([.root])
                == .replaceStack([.root]))
    }
}

// MARK: - A viewmodel-style consumer (marker only — no @Observable in Nebula)

@Suite("NebulaViewModel marker")
struct NebulaViewModelMarkerTests {

    private struct TestViewModel: NebulaViewModel {
        let router: any NebulaRouter<TestRoute>
        func openSettings() async { await router.push(.settings) }
    }

    @Test("a Sendable struct viewmodel conforms to the marker and drives the port")
    func markerConformance() async {
        let spy = NebulaSpyRouter<TestRoute>()
        let vm = TestViewModel(router: spy)
        await vm.openSettings()
        #expect(spy.intents() == [.push(.settings)])
    }
}