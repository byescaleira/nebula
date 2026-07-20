// swift-tools-version: 6.3
//
// Aurora — the persistence-architecture sibling of Nebula. Where Nebula is
// Foundation-only (no SwiftUI, no SwiftData), Aurora swallows SwiftData: the
// `@ModelActor`-backed repository adapter that conforms to Nebula's
// Foundation-only `NebulaRepository` ports, plus the `@Model`↔Sendable entity
// mapping that bridges SwiftData's non-`Sendable` `@Model`/`ModelContext` to
// Nebula's `Sendable` `NebulaEntity` DTOs.
//
// Aurora is a SEPARATE local SwiftPM package (its own manifest / module graph)
// depending on Nebula via a local path (`../`). The separation is load-bearing:
// it is the regime where an undeclared cross-layer `import` is an unconditional
// hard compile error — `import Aurora` from inside Nebula fails (Nebula declares
// no such dependency), so the Clean Architecture dependency rule ("domain / use
// cases never import persistence") is compiler-enforced across packages, closing
// the SwiftData placement risk (Q1 = (c), mirroring the Meridian (d) precedent).
// SwiftData is a system framework, not an SPM dep, so the package stays
// third-party-free. See vault/03-padroes/nebula-data-network-architecture.md and
// vault/08-riscos/data-network-open-questions.md.
//
// Platform / language-mode posture mirrors Nebula exactly: Swift 6.3 toolchain
// (Xcode 26.4+ / Xcode 27 dual-build), language mode v6, all five platforms at
// `.v26`. No third-party dependencies — `dependencies` lists only the local
// Nebula sibling. Versioning: Aurora N ↔ Nebula N ↔ OS N (policy finalized in
// VERSIONING.md at N4, mirroring the Meridian N ↔ Nebula N ↔ OS N policy).

import PackageDescription

let package = Package(
    name: "Aurora",
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
            name: "Aurora",
            targets: ["Aurora"]
        )
    ],
    dependencies: [
        // The Nebula Foundation-only sibling. Local path keeps one repo / one CI
        // lane building both packages; the cross-package boundary still enforces
        // the dependency rule. Promoting Aurora to its own git repo for public
        // consumption is a documented future step (the path dep becomes a git URL).
        .package(name: "Nebula", path: "../"),
    ],
    targets: [
        .target(
            name: "Aurora",
            dependencies: [
                .product(name: "Nebula", package: "Nebula"),
            ],
            // The DocC catalog (`Aurora.docc/`) is not Swift source — exclude
            // it from the target so `swift build` is warning-clean (mirrors the
            // Nebula / Meridian manifests). `xcodebuild docbuild` still
            // discovers and builds the catalog. Keeps `dependencies` to only
            // the local Nebula sibling.
            exclude: ["Aurora.docc"]
        ),
        // A runnable example demonstrating the full pattern: a `@Model`, an
        // `AuroraEntityMapping`, an `AuroraRepository` wired to an in-memory
        // `ModelContainer`, and a CRUD round-trip. Compiling it is the N3 gate;
        // `swift run AuroraExample` runs the macOS example. It is NOT a shipped
        // product (no `.library`/`.executableProduct`) — it exists to prove the
        // pattern composes and to serve as living docs.
        .executableTarget(
            name: "AuroraExample",
            dependencies: ["Aurora"]
        ),
        .testTarget(
            name: "AuroraTests",
            dependencies: ["Aurora"]
        ),
    ],
    swiftLanguageModes: [.v6]
)