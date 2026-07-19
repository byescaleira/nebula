//
//  DeepLinkTests.swift
//  MeridianTests
//
//  Wave III — deep-link-as-data is a pure function `URL -> [Route]`, fully
//  unit-testable without a simulator. The parser here is self-contained (not
//  imported from the `MeridianExample` executable target, which isn't
//  importable) — it mirrors the example's parser and asserts the navigation
//  stack that `router.replaceStack(with:)` would receive. The async port
//  (`NebulaRouter`) is the cross-actor bridge that hands the parsed stack to the
//  on-actor `Router`.
//

import Testing
import Foundation
import Nebula
@testable import Meridian

private enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
}

private enum DeepLink {
    static func parse(_ url: URL) -> [AppRoute] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [.root]
        }
        var routes: [AppRoute] = [.root]
        for segment in comps.path.split(separator: "/").map(String.init) {
            switch segment {
            case "settings": routes.append(.settings)
            default:
                if let id = UUID(uuidString: segment) { routes.append(.detail(id: id)) }
            }
        }
        return routes
    }
}

@Suite("Deep link parsing")
struct DeepLinkTests {

    @Test("empty/invalid URL stays at root")
    func emptyURL() {
        #expect(DeepLink.parse(URL(string: "nebula://app")!) == [.root])
    }

    @Test("settings segment maps to a route")
    func settings() {
        #expect(DeepLink.parse(URL(string: "nebula://app/settings")!) == [.root, .settings])
    }

    @Test("a uuid segment maps to a detail route")
    func detail() {
        let id = UUID()
        let url = URL(string: "nebula://app/detail/\(id.uuidString)")!
        #expect(DeepLink.parse(url) == [.root, .detail(id: id)])
    }

    @Test("multi-segment deep link builds the whole stack — replaceStack payload")
    func multiSegment() {
        let id = UUID()
        let url = URL(string: "nebula://app/detail/\(id.uuidString)/settings")!
        #expect(DeepLink.parse(url) == [.root, .detail(id: id), .settings])
    }

    @Test("parsed stack round-trips through Router.replaceStack via the async port")
    @MainActor
    func replaceStackViaPort() async {
        let router = Router<AppRoute>(path: [.settings])
        let port: any NebulaRouter<AppRoute> = router
        let id = UUID()
        let url = URL(string: "nebula://app/detail/\(id.uuidString)")!
        await port.replaceStack(with: DeepLink.parse(url))
        #expect(router.path == [.root, .detail(id: id)])
    }
}

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