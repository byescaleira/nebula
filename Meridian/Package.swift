// swift-tools-version: 6.3
//
// Meridian — the presentation-architecture sibling of Nebula. Where Nebula is
// Foundation-only (no SwiftUI), Meridian swallows SwiftUI: the `@Observable
// Router` and the `NavigationStack` wiring that render Nebula's Foundation-only
// navigation model (`NebulaRoute` / `NebulaNavigationStack` / `NebulaRouter`).
//
// Meridian is a SEPARATE local SwiftPM package (its own manifest / module graph)
// depending on Nebula via a local path (`../`). The separation is load-bearing:
// it is the ONLY regime where an undeclared cross-layer `import` is an
// unconditional hard compile error — `import Meridian` from inside Nebula fails
// (Nebula declares no such dependency), so the Clean Architecture dependency
// rule ("use cases / domain never import presentation") is compiler-enforced,
// closing the Wave H open risk (SR-1393 only applies within one package's
// shared `.build`). Mirrors pointfreeco/swift-navigation (`SwiftUINavigation`
// → `SwiftNavigation`). See vault/03-padroes/nebula-presentation-target-split.md
// option (d).
//
// Platform / language-mode posture mirrors Nebula exactly: Swift 6.3 toolchain
// (Xcode 26.4+ / Xcode 27 dual-build), language mode v6, all five platforms at
// `.v26`. No third-party dependencies — `dependencies` lists only the local
// Nebula sibling. SwiftUI is a system framework, not an SPM dep, so the
// package stays third-party-free. Versioning: Meridian N ↔ Nebula N ↔ OS N
// (policy finalized in VERSIONING.md, Wave IV).

import PackageDescription

let package = Package(
    name: "Meridian",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Meridian",
            targets: ["Meridian"]
        )
    ],
    dependencies: [
        // The Nebula Foundation-only sibling. Local path keeps one repo / one CI
        // lane building both packages; the cross-package boundary still enforces
        // the dependency rule. Promoting Meridian to its own git repo for public
        // consumption is a documented future step (the path dep becomes a git URL).
        .package(name: "Nebula", path: "../"),
    ],
    targets: [
        .target(
            name: "Meridian",
            dependencies: [
                .product(name: "Nebula", package: "Nebula"),
            ],
            // The DocC catalog (`Meridian.docc/`) is not Swift source — exclude
            // it from the target so `swift build` is warning-clean (mirrors the
            // Nebula manifest). `xcodebuild docbuild` still discovers and builds
            // the catalog. Keeps `dependencies` to only the local Nebula sibling.
            exclude: ["Meridian.docc"]
        ),
        // A runnable example demonstrating the full pattern: `Router` + typed
        // `[Route]` + `MeridianNavigationStack` + a type-driven `Destination`
        // enum driving `sheet(item:)` + a deep-link handler. Compiling it is the
        // Wave III gate; `swift run MeridianExample` launches the macOS app. It
        // is NOT a shipped product (no `.library`/`.executableProduct`) — it
        // exists to prove the pattern composes and to serve as living docs.
        .executableTarget(
            name: "MeridianExample",
            dependencies: ["Meridian"]
        ),
        .testTarget(
            name: "MeridianTests",
            dependencies: ["Meridian"]
        ),
    ],
    swiftLanguageModes: [.v6]
)