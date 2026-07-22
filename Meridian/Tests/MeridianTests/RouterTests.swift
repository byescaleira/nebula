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
//  Wave N20 — extended for presentation styles: `present(_:)`/`present(_:as:)`/
//  `dismiss()` mutate `path` + the modal slot (`presented`/`presentedStyle`),
//  and `NebulaPresentationRouter` conformance verifies the richer port reaches
//  the wrapper.
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
    case share(id: UUID)   // sheet
    case login             // full-screen cover

    var presentationStyle: NebulaPresentationStyle {
        switch self {
        case .share: return .sheet
        case .login: return .fullScreenCover
        default:    return .push
        }
    }
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

    // MARK: Wave N20 — presentation styles + modal slot

    @Test("present(_:) of a .push route pushes onto path; modal untouched")
    func presentPushRoute() {
        let router = Router<TestRoute>()
        let id = UUID()
        router.present(.detail(id: id))
        #expect(router.path == [.detail(id: id)])
        #expect(router.presented == nil)
        #expect(router.presentedStyle == nil)
    }

    @Test("present(_:) of a .sheet route fills the modal slot; path untouched")
    func presentSheetRoute() {
        let router = Router<TestRoute>()
        router.push(.settings)
        let id = UUID()
        router.present(.share(id: id))
        #expect(router.presented == .share(id: id))
        #expect(router.presentedStyle == .sheet)
        #expect(router.path == [.settings])
    }

    @Test("present(_:) of a .fullScreenCover route fills the modal slot")
    func presentCoverRoute() {
        let router = Router<TestRoute>()
        router.present(.login)
        #expect(router.presented == .login)
        #expect(router.presentedStyle == .fullScreenCover)
        #expect(router.path == [])
    }

    @Test("present(_:as:) overrides the route's declared style at the call site")
    func presentAsOverridesStyle() {
        let router = Router<TestRoute>()
        // .settings is declared .push; override it to a sheet here.
        router.present(.settings, as: .sheet)
        #expect(router.presented == .settings)
        #expect(router.presentedStyle == .sheet)
        #expect(router.path == [])
    }

    @Test("dismiss() clears an active modal without touching the path")
    func dismissClearsModal() {
        let router = Router<TestRoute>()
        router.push(.settings)
        router.present(.share(id: UUID()))
        router.dismiss()
        #expect(router.presented == nil)
        #expect(router.presentedStyle == nil)
        #expect(router.path == [.settings])
    }

    @Test("dismiss() with no modal pops one from the path")
    func dismissPopsWhenNoModal() {
        let router = Router<TestRoute>(path: [.root, .settings])
        router.dismiss()
        #expect(router.path == [.root])
        #expect(router.presented == nil)
    }

    @Test("conforms to NebulaPresentationRouter — dispatch reaches the wrapper")
    func presentationPortConformance() async {
        let router = Router<TestRoute>()
        let port: any NebulaPresentationRouter<TestRoute> = router
        let id = UUID()

        await port.present(.detail(id: id))
        await port.present(.share(id: id), as: .sheet)
        await port.dismiss()

        #expect(router.path == [.detail(id: id)])
        #expect(router.presented == nil)
    }
}