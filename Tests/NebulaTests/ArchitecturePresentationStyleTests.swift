//
//  ArchitecturePresentationStyleTests.swift
//  NebulaTests
//
//  Wave N20 — Presentation navigation styles. Pure-Swift tests for the
//  per-route presentation style, the navigation-as-data model
//  (``NebulaPresentation``), the presentation-intent port
//  (``NebulaPresentationRouter``), and the extended spy router. No SwiftUI in
//  the test graph (Foundation-only seams). Navigation-as-data: present/
//  dismiss and the modal slot are value assertions, no simulator. See
//  Sources/Nebula/Architecture/Presentation/.
//

import Testing
import Foundation
@testable import Nebula

// MARK: - Test routes

/// A route that overrides `presentationStyle` per case (the Wave N20 dispatch
/// key). `pushRoute` pushes; `sheetRoute` is a sheet; `coverRoute` is a
/// full-screen cover.
private enum StyleRoute: NebulaRoute {
    case pushRoute
    case sheetRoute
    case coverRoute
    case detail(id: UUID)

    var presentationStyle: NebulaPresentationStyle {
        switch self {
        case .sheetRoute: return .sheet
        case .coverRoute: return .fullScreenCover
        default:          return .push
        }
    }
}

/// A route with NO `presentationStyle` override — exercises the additive
/// default (`.push`). Existing conformers keep working (Wave I/II).
private enum DefaultRoute: NebulaRoute {
    case root
    case detail(id: UUID)
}

// MARK: - NebulaPresentationStyle

@Suite("NebulaPresentationStyle")
struct NebulaPresentationStyleTests {

    @Test("cases and isModal")
    func casesAndIsModal() {
        #expect(NebulaPresentationStyle.push.isModal == false)
        #expect(NebulaPresentationStyle.sheet.isModal == true)
        #expect(NebulaPresentationStyle.fullScreenCover.isModal == true)
    }

    @Test("Sendable / Equatable / Hashable")
    func conformance() async {
        #expect(NebulaPresentationStyle.sheet == .sheet)
        #expect(NebulaPresentationStyle.sheet != .fullScreenCover)
        let sheet = NebulaPresentationStyle.sheet
        #expect(sheet.hashValue == NebulaPresentationStyle.sheet.hashValue)
        // Sendable derives (value enum, no state) — capturing the style in a
        // @Sendable closure compiles only if the derived conformance holds.
        let s = NebulaPresentationStyle.sheet
        let copied = await Task { s }.value
        #expect(copied == s)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for style in [NebulaPresentationStyle.push, .sheet, .fullScreenCover] {
            let data = try JSONEncoder().encode(style)
            let restored = try JSONDecoder().decode(NebulaPresentationStyle.self, from: data)
            #expect(restored == style)
        }
    }
}

// MARK: - NebulaRoute.presentationStyle (additive default)

@Suite("NebulaRoute.presentationStyle default")
struct RoutePresentationStyleTests {

    @Test("a route with no override defaults to .push (additive — existing conformers)")
    func defaultIsPush() {
        #expect(DefaultRoute.root.presentationStyle == .push)
        #expect(DefaultRoute.detail(id: UUID()).presentationStyle == .push)
    }

    @Test("an overriding route declares per-case styles")
    func overriddenStyles() {
        #expect(StyleRoute.pushRoute.presentationStyle == .push)
        #expect(StyleRoute.sheetRoute.presentationStyle == .sheet)
        #expect(StyleRoute.coverRoute.presentationStyle == .fullScreenCover)
        #expect(StyleRoute.detail(id: UUID()).presentationStyle == .push)
    }
}

// MARK: - NebulaPresentation (navigation-as-data model)

@Suite("NebulaPresentation")
struct NebulaPresentationTests {

    @Test("present(_:as:) .push appends to path; modal stays nil")
    func presentPushAppends() {
        var p = NebulaPresentation<StyleRoute>()
        let id = UUID()
        p.present(.pushRoute, as: .push)
        p.present(.detail(id: id), as: .push)
        #expect(p.path == [.pushRoute, .detail(id: id)])
        #expect(p.modal == nil)
        #expect(p.modalStyle == nil)
    }

    @Test("present(_:as:) .sheet fills the modal slot")
    func presentSheetFillsSlot() {
        var p = NebulaPresentation<StyleRoute>()
        p.present(.sheetRoute, as: .sheet)
        #expect(p.modal == .sheetRoute)
        #expect(p.modalStyle == .sheet)
        #expect(p.path == [])
    }

    @Test("present(_:as:) .fullScreenCover fills the modal slot")
    func presentCoverFillsSlot() {
        var p = NebulaPresentation<StyleRoute>()
        p.present(.coverRoute, as: .fullScreenCover)
        #expect(p.modal == .coverRoute)
        #expect(p.modalStyle == .fullScreenCover)
        #expect(p.path == [])
    }

    @Test("present(_:) dispatches by the route's declared style")
    func presentDispatchesByDeclaredStyle() {
        var p = NebulaPresentation<StyleRoute>()
        p.present(.pushRoute)        // declared .push → appends
        #expect(p.path == [.pushRoute])
        #expect(p.modal == nil)

        p.present(.sheetRoute)       // declared .sheet → modal
        #expect(p.modal == .sheetRoute)
        #expect(p.modalStyle == .sheet)
        #expect(p.path == [.pushRoute])   // path untouched

        p.present(.coverRoute, as: .fullScreenCover)  // override → modal replaces
        #expect(p.modal == .coverRoute)
        #expect(p.modalStyle == .fullScreenCover)
        #expect(p.path == [.pushRoute])
    }

    @Test("present(_:as:) overrides a .push route to a sheet")
    func presentAsOverridesDeclaredStyle() {
        var p = NebulaPresentation<StyleRoute>()
        // pushRoute is declared .push, but override it to a sheet at the call site.
        p.present(.pushRoute, as: .sheet)
        #expect(p.modal == .pushRoute)
        #expect(p.modalStyle == .sheet)
        #expect(p.path == [])
    }

    @Test("dismiss() clears an active modal without touching the path")
    func dismissClearsModal() {
        var p = NebulaPresentation<StyleRoute>(path: [.pushRoute])
        p.present(.sheetRoute, as: .sheet)
        p.dismiss()
        #expect(p.modal == nil)
        #expect(p.modalStyle == nil)
        #expect(p.path == [.pushRoute])   // path untouched
    }

    @Test("dismiss() with no modal pops one from the path")
    func dismissPopsWhenNoModal() {
        var p = NebulaPresentation<StyleRoute>(path: [.pushRoute, .detail(id: UUID())])
        p.dismiss()
        #expect(p.path == [.pushRoute])
        #expect(p.modal == nil)
    }

    @Test("dismiss() with no modal and empty path is a no-op (no underflow)")
    func dismissEmptyIsNoOp() {
        var p = NebulaPresentation<StyleRoute>()
        p.dismiss()
        #expect(p.path == [])
        #expect(p.modal == nil)
    }

    @Test("push/pop/popToRoot/replaceStack delegate to NebulaNavigationStack")
    func pushPathOpsDelegate() {
        var p = NebulaPresentation<StyleRoute>()
        let id = UUID()
        p.push(.detail(id: id))
        p.push(.pushRoute)
        #expect(p.path == [.detail(id: id), .pushRoute])
        #expect(p.top == .pushRoute)
        #expect(p.count == 2)
        #expect(!p.isEmpty)

        p.pop()
        #expect(p.path == [.detail(id: id)])

        p.popToRoot()
        #expect(p.path == [])
        #expect(p.isEmpty)

        p.replaceStack(with: [.pushRoute, .detail(id: id)])
        #expect(p.path == [.pushRoute, .detail(id: id)])
    }

    @Test("Equatable derives from Route + style")
    func equatable() {
        let a = NebulaPresentation<StyleRoute>(path: [.pushRoute], modal: .sheetRoute,
                                               modalStyle: .sheet)
        let b = NebulaPresentation<StyleRoute>(path: [.pushRoute], modal: .sheetRoute,
                                               modalStyle: .sheet)
        let c = NebulaPresentation<StyleRoute>(path: [.pushRoute], modal: .sheetRoute,
                                               modalStyle: .fullScreenCover)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable round-trip restores path + modal + modalStyle")
    func codableRoundTrip() throws {
        let p = NebulaPresentation<StyleRoute>(path: [.pushRoute, .detail(id: UUID())],
                                               modal: .sheetRoute, modalStyle: .sheet)
        let data = try JSONEncoder().encode(p)
        let restored = try JSONDecoder().decode(NebulaPresentation<StyleRoute>.self, from: data)
        #expect(restored == p)
    }

    @Test("Sendable — a presentation can be captured across tasks")
    func sendableAcrossTasks() async {
        let p = NebulaPresentation<StyleRoute>(path: [.pushRoute], modal: .sheetRoute,
                                               modalStyle: .sheet)
        let copied = await Task { p }.value
        #expect(copied == p)
    }

    @Test("statics mutate inout components — single source of truth")
    func staticsMutateInout() {
        var path: [StyleRoute] = [.pushRoute]
        var modal: StyleRoute? = nil
        var style: NebulaPresentationStyle? = nil

        NebulaPresentation.present(.sheetRoute, as: .sheet, into: &path,
                                   modal: &modal, style: &style)
        #expect(path == [.pushRoute])
        #expect(modal == .sheetRoute)
        #expect(style == .sheet)

        NebulaPresentation.dismiss(path: &path, modal: &modal, style: &style)
        #expect(modal == nil)
        #expect(style == nil)
        #expect(path == [.pushRoute])   // modal cleared, path untouched

        NebulaPresentation.dismiss(path: &path, modal: &modal, style: &style)
        #expect(path == [])             // no modal → pop one
    }
}

// MARK: - NebulaSpyRouter (NebulaPresentationRouter extension)

@Suite("NebulaSpyRouter — presentation intents")
struct NebulaSpyRouterPresentationTests {

    @Test("records present / presentAs / dismiss in call order")
    func recordsPresentationIntents() {
        let spy = NebulaSpyRouter<StyleRoute>()
        let id = UUID()

        spy.present(.sheetRoute)
        spy.present(.coverRoute, as: .fullScreenCover)
        spy.present(.detail(id: id), as: .push)
        spy.dismiss()

        #expect(spy.callCount == 4)
        #expect(spy.intents() == [
            .present(.sheetRoute),
            .presentAs(.coverRoute, .fullScreenCover),
            .presentAs(.detail(id: id), .push),
            .dismiss,
        ])
    }

    @Test("conforms to NebulaPresentationRouter — a drop-in for the richer port")
    func presentationPortConformance() async {
        let spy = NebulaSpyRouter<StyleRoute>()
        // Call through the existential async port to verify dynamic dispatch
        // reaches the spy's synchronous implementations.
        let router: any NebulaPresentationRouter<StyleRoute> = spy

        await router.present(.sheetRoute)
        await router.present(.coverRoute, as: .fullScreenCover)
        await router.dismiss()

        #expect(spy.intents() == [
            .present(.sheetRoute),
            .presentAs(.coverRoute, .fullScreenCover),
            .dismiss,
        ])
    }

    @Test("push intents still record alongside presentation intents (additive)")
    func pushIntentsUnchanged() {
        let spy = NebulaSpyRouter<StyleRoute>()
        spy.push(.pushRoute)
        spy.pop()
        spy.present(.sheetRoute)
        #expect(spy.intents() == [.push(.pushRoute), .pop(1), .present(.sheetRoute)])
    }

    @Test("Intent equality derives from Route + style")
    func intentEquality() {
        #expect(NebulaSpyRouter<StyleRoute>.Intent.present(.sheetRoute)
                == .present(.sheetRoute))
        #expect(NebulaSpyRouter<StyleRoute>.Intent.presentAs(.coverRoute, .fullScreenCover)
                == .presentAs(.coverRoute, .fullScreenCover))
        #expect(NebulaSpyRouter<StyleRoute>.Intent.presentAs(.coverRoute, .fullScreenCover)
                != .presentAs(.coverRoute, .sheet))
        #expect(NebulaSpyRouter<StyleRoute>.Intent.dismiss == .dismiss)
    }
}