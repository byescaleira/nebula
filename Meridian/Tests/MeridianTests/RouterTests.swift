//
//  RouterTests.swift
//  MeridianTests
//
//  Wave II — Tests for the `@Observable Router`. Logic is tested as data
//  (push/pop/replaceStack mutate `path`); port-conformance verifies the
//  Foundation-only `NebulaRouter` dispatch reaches the `@Observable` wrapper;
//  deep-link round-trip verifies `replaceStack` + `Codable` restoration. The
//  SwiftUI wiring (`MeridianNavigationStack`) is structural and exercised in
//  the Wave III example; here we assert the navigation model contract.
//

import Testing
import Foundation
import SwiftUI
import Nebula
@testable import Meridian

private enum TestRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
}

@Suite("Router")
@MainActor
struct RouterTests {

    @Test("push/pop/popToRoot mutate the tracked path")
    func pushPopPopToRoot() {
        let router = Router<TestRoute>()
        #expect(router.isEmpty)
        #expect(router.path == [])

        let id = UUID()
        router.push(.detail(id: id))
        router.push(.settings)
        #expect(router.path == [.detail(id: id), .settings])
        #expect(router.top == .settings)
        #expect(router.count == 2)

        router.pop()
        #expect(router.path == [.detail(id: id)])

        router.popToRoot()
        #expect(router.path == [])
        #expect(router.isEmpty)
    }

    @Test("pop(count:) and the port-convenience pop() both work")
    func popCountAndConvenience() {
        let router = Router<TestRoute>(path: [.root, .settings, .detail(id: UUID())])
        router.pop(2)
        #expect(router.path == [.root])
        router.pop()
        #expect(router.path == [])
    }

    @Test("replaceStack is the deep-link primitive")
    func replaceStackDeepLink() {
        let router = Router<TestRoute>(path: [.root, .settings])
        let id = UUID()
        router.replaceStack(with: [.root, .detail(id: id)])
        #expect(router.path == [.root, .detail(id: id)])
        #expect(router.top == .detail(id: id))
    }

    @Test("conforms to NebulaRouter — dispatch reaches the @Observable wrapper")
    func portConformance() async {
        let router = Router<TestRoute>()
        let port: any NebulaRouter<TestRoute> = router
        let id = UUID()

        await port.push(.detail(id: id))
        await port.pop()
        await port.replaceStack(with: [.root, .settings])

        #expect(router.path == [.root, .settings])
    }

    @Test("Router is @MainActor Sendable — cross-isolation use compiles")
    func mainActorSendable() async {
        let router = Router<TestRoute>()
        // Sendable by isolation: a @MainActor @Observable final class can be
        // awaited across tasks on the main actor.
        await Task { @MainActor in router.push(.settings) }.value
        #expect(router.path == [.settings])
    }

    @Test("Codable path round-trip — state restoration")
    func codableRoundTrip() throws {
        let id = UUID()
        let router = Router<TestRoute>(path: [.root, .detail(id: id), .settings])

        let data = try JSONEncoder().encode(router.path)
        let restored = try JSONDecoder().decode([TestRoute].self, from: data)

        #expect(restored == router.path)
    }
}