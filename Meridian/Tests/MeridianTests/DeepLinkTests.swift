//
//  DeepLinkTests.swift
//  MeridianTests
//
//  Wave N21 — external navigation entries conforming to the router. The link
//  router (``NebulaLinkRouter``) drives the Meridian ``Router`` through the
//  additive ``NebulaPresentationRouter/apply(_:)``: a ``NebulaLink`` is resolved
//  by a parser into a ``NebulaLinkDestination``, then applied to the on-actor
//  `Router`. These tests assert the observable `path`/`presented`/
//  `presentedStyle` mutations on a real `Router` (no simulator) — the
//  Foundation-only parser/destination/spy is covered in Nebula's
//  `ArchitectureDeepLinkTests`. The `DestinationTests` suite (below) keeps the
//  Wave III `sheet(item:)` Identifiable pattern as a standalone reference.
//

import Testing
import Foundation
import Nebula
@testable import Meridian

private enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
    case share(id: UUID)   // sheet
    case login            // full-screen cover

    var presentationStyle: NebulaPresentationStyle {
        switch self {
        case .share: return .sheet
        case .login: return .fullScreenCover
        default:    return .push
        }
    }
}

// MARK: - NebulaLinkRouter over the Meridian Router

@MainActor
@Suite("NebulaLinkRouter over Meridian Router")
struct LinkRouterTests {

    @Test(".present pushes a push-style route onto the path")
    func presentPush() async {
        let router = Router<AppRoute>()
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.present(.settings)))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == [.settings])
        #expect(router.presented == nil)
        #expect(router.presentedStyle == nil)
    }

    @Test(".present of a modal route fills the modal slot")
    func presentModal() async {
        let router = Router<AppRoute>()
        let id = UUID()
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.present(.share(id: id))))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == [])
        #expect(router.presented == .share(id: id))
        #expect(router.presentedStyle == .sheet)
    }

    @Test(".present of a full-screen-cover route sets the cover style")
    func presentCover() async {
        let router = Router<AppRoute>()
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.present(.login)))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.presented == .login)
        #expect(router.presentedStyle == .fullScreenCover)
    }

    @Test(".pushStack rebuilds the path (the deep-link primitive)")
    func pushStackRebuilds() async {
        let router = Router<AppRoute>(path: [.settings])
        let stack: [AppRoute] = [.root, .detail(id: UUID())]
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.pushStack(stack)))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == stack)
    }

    @Test(".pushStack clears a stale modal before rebuilding")
    func pushStackClearsStaleModal() async {
        let router = Router<AppRoute>()
        router.present(.share(id: UUID()))   // a stale modal is open
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.pushStack([.root, .settings])))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == [.root, .settings])
        #expect(router.presented == nil)
        #expect(router.presentedStyle == nil)
    }

    @Test(".pushStackAndPresent rebuilds the path then presents the modal")
    func pushStackAndPresent() async {
        let router = Router<AppRoute>()
        let id = UUID()
        let stack: [AppRoute] = [.root, .detail(id: id)]
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.pushStackAndPresent(stack, .share(id: id))))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == stack)
        #expect(router.presented == .share(id: id))
        #expect(router.presentedStyle == .sheet)
    }

    @Test(".dismiss clears the active modal")
    func dismissClearsModal() async {
        let router = Router<AppRoute>()
        router.present(.share(id: UUID()))
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.dismiss))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.presented == nil)
        #expect(router.presentedStyle == nil)
    }

    @Test(".unhandled leaves the router untouched")
    func unhandled() async {
        let router = Router<AppRoute>(path: [.settings])
        let linkRouter = NebulaLinkRouter(
            router: router, parser: NebulaStubLinkParser(.unhandled))
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://x")!))
        #expect(router.path == [.settings])
        #expect(router.presented == nil)
    }

    @Test("a real parser resolves a nebula:// URL into a rebuilt stack")
    func realParser() async {
        struct Parser: NebulaLinkParser {
            typealias Route = AppRoute
            func resolve(_ link: NebulaLink) -> NebulaLinkDestination<AppRoute> {
                guard let url = link.url,
                      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                else { return .unhandled }
                var routes: [AppRoute] = [.root]
                for segment in comps.path.split(separator: "/").map(String.init) {
                    if segment == "settings" { routes.append(.settings) }
                    if let id = UUID(uuidString: segment) { routes.append(.detail(id: id)) }
                }
                return routes.count > 1 ? .pushStack(routes) : .unhandled
            }
        }
        let router = Router<AppRoute>()
        let linkRouter = NebulaLinkRouter(router: router, parser: Parser())
        let id = UUID()
        await linkRouter.open(NebulaLink(url: URL(string: "nebula://app/\(id.uuidString)")!))
        #expect(router.path == [.root, .detail(id: id)])
    }
}

// MARK: - Type-driven destinations (modals) — Wave III reference pattern

@Suite("Type-driven destinations (modals)")
struct DestinationTests {

    // A single optional enum drives sheet(item:) — only one destination active.
    private enum Destination: Identifiable {
        case editItem(UUID)
        case confirmDelete(UUID)
        var id: String {
            switch self {
            case .editItem(let id):       "edit-\(id.uuidString)"
            case .confirmDelete(let id):  "delete-\(id.uuidString)"
            }
        }
    }

    @Test("each case has a stable, distinct id — sheet(item:) identity")
    func identifiable() {
        let id = UUID()
        #expect(Destination.editItem(id).id == "edit-\(id.uuidString)")
        #expect(Destination.confirmDelete(id).id == "delete-\(id.uuidString)")
        #expect(Destination.editItem(id).id != Destination.confirmDelete(id).id)
    }

    @Test("a single optional holds at most one destination — impossible states unrepresentable")
    func singleOptional() {
        var destination: Destination? = nil
        #expect(destination == nil)
        destination = .editItem(UUID())
        // Reassigning to the delete case REPLACES — there is no `editItem && confirmDelete` state.
        destination = .confirmDelete(UUID())
        if case .confirmDelete = destination {} else { Issue.record("expected confirmDelete") }
    }
}