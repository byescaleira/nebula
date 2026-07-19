// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Set to 6.3 so the package builds on Xcode 26.4+ (Swift 6.3) and Xcode 27 (Swift 6.4).
// NOTE: Xcode 26.0–26.3 shipped Swift 6.2 and will NOT parse a 6.3 manifest — require Xcode 26.4+
// for the Swift 6.3 path. Any OS-27-only SDK symbol is compile-gated with `#if swift(>=6.4)`
// so it compiles to a graceful fallback on Swift 6.3 and turns on under Xcode 27 / Swift 6.4.
// Nebula is a FOUNDATION/architecture layer (no SwiftUI); consumed by apps and other SPMs.
// Mirrors the Cosmos sibling package manifest shape (single target + single test target).

import PackageDescription

let package = Package(
    name: "Nebula",
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
            name: "Nebula",
            targets: ["Nebula"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [],
            // The DocC catalog (`Nebula.docc/`) is NOT Swift source and is not a bundled
            // resource — `swift build` would otherwise warn "found unhandled file(s)". Exclude
            // it from the library target so `swift build` is warning-clean; `xcodebuild docbuild`
            // still discovers the catalog from the target's source directory and builds the
            // documentation archive (verified). This keeps `dependencies: []` pristine — no
            // swift-docc-plugin. See CLAUDE.md "Build & verify". NOTE: `exclude` precedes
            // `resources` to match the `.target` factory's declaration order.
            exclude: ["Nebula.docc"],
            // Resources are OPTIONAL. A foundation layer emits developer-facing English log/error
            // text and ships no user-facing strings by default, so no catalog is bundled.
            // When a Localizable.xcstrings String Catalog is added under Sources/Nebula/Resources/,
            // uncomment the block below — `.process` compiles the catalog to .lproj/.strings at
            // build time and `Bundle.module` exposes it at runtime (defaultLocalization above is
            // already set). This is the deliberate divergence from Cosmos (which ships .xcstrings
            // for UI strings) — Nebula has no UI surface.
            resources: [
                // .process("Resources"),
            ]
        ),
        .testTarget(
            name: "NebulaTests",
            dependencies: ["Nebula"]
        ),
    ],
    swiftLanguageModes: [.v6]
)