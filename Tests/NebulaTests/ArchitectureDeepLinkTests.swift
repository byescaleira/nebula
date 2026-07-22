//
//  ArchitectureDeepLinkTests.swift
//  NebulaTests
//
//  Wave N21 — External navigation entries conforming to the router. Pure-Swift
//  tests for the normalized external-navigation value (``NebulaLink``), the
//  resolved destination (``NebulaLinkDestination``), the parser port
//  (``NebulaLinkParser``) + composite, the glue (``NebulaLinkRouter``), and the
//  additive ``NebulaPresentationRouter/apply(_:)`` default extension. No
//  SwiftUI in the test graph (Foundation-only seams) — the router is exercised
//  via the ``NebulaSpyRouter``, asserting the recorded intents. See
//  Sources/Nebula/Architecture/Presentation/ + Sources/Nebula/Architecture/Testing/.
//

import Testing
import Foundation
@testable import Nebula

// MARK: - Test routes

/// A route with per-case presentation styles (the dispatch key) + a UUID detail
/// route, used to assert the link router drives the spy with the right intents.
private enum LinkRoute: NebulaRoute {
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

// MARK: - NebulaLink

@Suite("NebulaLink")
struct NebulaLinkTests {

    @Test("init(url:) infers .universalLink for http/https (case-insensitive)")
    func universalLinkInference() {
        #expect(NebulaLink(url: URL(string: "https://example.com/item/1")!).source == .universalLink)
        #expect(NebulaLink(url: URL(string: "http://example.com")!).source == .universalLink)
        #expect(NebulaLink(url: URL(string: "HTTPS://example.com")!).source == .universalLink)
    }

    @Test("init(url:) infers .urlScheme for a custom scheme (case-insensitive)")
    func urlSchemeInference() {
        #expect(NebulaLink(url: URL(string: "myapp://item/1")!).source == .urlScheme)
        #expect(NebulaLink(url: URL(string: "MyApp://item/1")!).source == .urlScheme)
    }

    @Test("init(url:) defaults to .urlScheme when the scheme is nil")
    func nilSchemeDefaultsToURLScheme() {
        // A URL with no scheme (built via URLComponents so it is non-nil with a
        // nil scheme) — robust across Foundation versions.
        var comps = URLComponents()
        comps.path = "/item/1"
        let url = comps.url!
        #expect(url.scheme == nil)
        #expect(NebulaLink(url: url).source == .urlScheme)
    }

    @Test("init(url:) carries the url and empty metadata")
    func urlCarrier() {
        let url = URL(string: "myapp://item/1")!
        let link = NebulaLink(url: url)
        #expect(link.url == url)
        #expect(link.identifier == nil)
        #expect(link.title == nil)
        #expect(link.payload.isEmpty)
    }

    @Test("full init carries every component")
    func fullInit() {
        let url = URL(string: "https://x")!
        let link = NebulaLink(source: .shortcut, url: url, identifier: "OpenSettings",
                               title: "Settings", payload: ["k": "v"])
        #expect(link.source == .shortcut)
        #expect(link.url == url)
        #expect(link.identifier == "OpenSettings")
        #expect(link.title == "Settings")
        #expect(link.payload == ["k": "v"])
    }

    @Test("Sendable / Equatable / Hashable")
    func conformance() async {
        let a = NebulaLink(url: URL(string: "myapp://x")!)
        let b = NebulaLink(url: URL(string: "myapp://x")!)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        // Sendable: capture into a @Sendable Task closure.
        let captured = a
        let same = await Task { captured == NebulaLink(url: URL(string: "myapp://x")!) }.value
        #expect(same)
    }
}

// MARK: - NebulaLinkDestination

@Suite("NebulaLinkDestination")
struct NebulaLinkDestinationTests {

    @Test("the five cases and Equatable")
    func casesAndEquality() {
        let id = UUID()
        #expect(NebulaLinkDestination<LinkRoute>.unhandled == .unhandled)
        #expect(NebulaLinkDestination<LinkRoute>.present(.root) == .present(.root))
        #expect(NebulaLinkDestination<LinkRoute>.pushStack([.root]) == .pushStack([.root]))
        #expect(NebulaLinkDestination<LinkRoute>.pushStackAndPresent([.root], .login)
                == .pushStackAndPresent([.root], .login))
        #expect(NebulaLinkDestination<LinkRoute>.dismiss == .dismiss)
        #expect(NebulaLinkDestination<LinkRoute>.present(.detail(id: id)) != .unhandled)
    }
}

// MARK: - NebulaLinkRouter (drives the spy via the additive apply(_:))

@Suite("NebulaLinkRouter")
struct NebulaLinkRouterTests {

    @Test(".present dispatches by the route's style — records .present")
    func present() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.present(.detail(id: UUID()))))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        #expect(spy.callCount == 1)
        guard case .present = spy.intents().first else {
            Issue.record("expected .present"); return
        }
    }

    @Test(".present of a modal route records .present (style is the route's)")
    func presentModal() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let id = UUID()
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.present(.share(id: id))))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        #expect(spy.intents() == [.present(.share(id: id))])
    }

    @Test(".pushStack dismisses first (clears stale modal), then replaces the stack")
    func pushStackDismissesFirst() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let stack: [LinkRoute] = [.root, .detail(id: UUID())]
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.pushStack(stack)))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        // dismiss() is recorded first even when no modal is active — the harmless
        // pop is erased by replaceStack in a real router; the spy records it.
        #expect(spy.intents() == [.dismiss, .replaceStack(stack)])
    }

    @Test(".pushStackAndPresent rebuilds the stack then presents the modal")
    func pushStackAndPresent() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let id = UUID()
        let stack: [LinkRoute] = [.root, .detail(id: id)]
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.pushStackAndPresent(stack, .share(id: id))))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        #expect(spy.intents() == [.dismiss, .replaceStack(stack), .present(.share(id: id))])
    }

    @Test(".dismiss records a single .dismiss")
    func dismiss() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.dismiss))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        #expect(spy.intents() == [.dismiss])
    }

    @Test(".unhandled records nothing")
    func unhandled() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        let router = NebulaLinkRouter(router: spy,
                                      parser: NebulaStubLinkParser(.unhandled))
        await router.open(NebulaLink(url: URL(string: "myapp://x")!))
        #expect(spy.callCount == 0)
        #expect(spy.intents() == [])
    }

    @Test("apply(_:) is inherited by the spy directly (additive default extension)")
    func applyInherited() async {
        let spy = NebulaSpyRouter<LinkRoute>()
        await spy.apply(.present(.settings))
        #expect(spy.intents() == [.present(.settings)])
    }
}

// MARK: - NebulaCompositeLinkParser

@Suite("NebulaCompositeLinkParser")
struct NebulaCompositeLinkParserTests {

    @Test("the first non-`.unhandled` parser wins")
    func firstWins() {
        let composite = NebulaCompositeLinkParser<LinkRoute>([
            NebulaStubLinkParser(.unhandled),
            NebulaStubLinkParser(.present(.settings)),
            NebulaStubLinkParser(.present(.login)),   // never consulted
        ])
        #expect(composite.resolve(NebulaLink(url: URL(string: "myapp://x")!)) == .present(.settings))
    }

    @Test("all `.unhandled` → `.unhandled`")
    func allUnhandled() {
        let composite = NebulaCompositeLinkParser<LinkRoute>([
            NebulaStubLinkParser(.unhandled),
            NebulaStubLinkParser(.unhandled),
        ])
        #expect(composite.resolve(NebulaLink(url: URL(string: "myapp://x")!)) == .unhandled)
    }

    @Test("an empty composite returns `.unhandled`")
    func emptyComposite() {
        let composite = NebulaCompositeLinkParser<LinkRoute>([])
        #expect(composite.resolve(NebulaLink(url: URL(string: "myapp://x")!)) == .unhandled)
    }

    @Test("Sendable")
    func sendable() async {
        let composite = NebulaCompositeLinkParser<LinkRoute>([NebulaStubLinkParser(.present(.root))])
        let captured = composite
        let result = await Task { captured.resolve(NebulaLink(url: URL(string: "myapp://x")!)) }.value
        #expect(result == .present(.root))
    }
}

// MARK: - Test doubles (NebulaStubLinkParser / NebulaSpyLinkParser)

@Suite("Link parser test doubles")
struct LinkParserDoublesTests {

    @Test("NebulaStubLinkParser returns the fixed destination")
    func stubReturnsFixed() {
        let stub = NebulaStubLinkParser<LinkRoute>(.present(.settings))
        #expect(stub.resolve(NebulaLink(url: URL(string: "myapp://x")!)) == .present(.settings))
    }

    @Test("NebulaSpyLinkParser records links and returns the configured destination")
    func spyRecords() {
        let spy = NebulaSpyLinkParser<LinkRoute>(destination: .present(.root))
        let link = NebulaLink(url: URL(string: "myapp://a")!)
        _ = spy.resolve(link)
        _ = spy.resolve(NebulaLink(url: URL(string: "myapp://b")!))
        #expect(spy.callCount == 2)
        #expect(spy.links().count == 2)
        #expect(spy.links().first == link)
    }

    @Test("NebulaSpyLinkParser defaults to `.unhandled`")
    func spyDefaultsUnhandled() {
        let spy = NebulaSpyLinkParser<LinkRoute>()
        #expect(spy.resolve(NebulaLink(url: URL(string: "myapp://x")!)) == .unhandled)
    }

    @Test("NebulaSpyLinkParser is Sendable (shared across a Task)")
    func spySendable() async {
        let spy = NebulaSpyLinkParser<LinkRoute>(destination: .present(.root))
        await Task { _ = spy.resolve(NebulaLink(url: URL(string: "myapp://x")!)) }.value
        #expect(spy.callCount == 1)
    }
}