---
tags: [foundation, spm-architecture, package-manifest, swift6]
aliases: [nebula-package, nebula-spm]
related: [[nebula-logging], [nebula-errors], [nebula-date-time-extensions], [nebula-string-extensions], [nebula-number-measurement-extensions], [nebula-primitive-extensions], [nebula-collection-extensions], [nebula-codable-foundation], [nebula-data-url-extensions], [nebula-standardize-measure], [nebula-swift6-concurrency]]
---

# Nebula SPM Package Architecture

Nebula is the codename sibling of Cosmos — a **foundation/architecture** SwiftPM library (no SwiftUI) consumed by apps and other SPM packages. This note fixes the **package manifest shape, platform matrix, target layout, and compile-gating strategy** for the first (foundation) phase: logging, errors, extensions, helpers, and a standardize/measure subsystem.

## Binding constraints (non-negotiable)

Mirrors the Cosmos sibling package, decided with the user:

- **Swift 6.3+ toolchain** — builds on both Xcode 26.4+ (Swift 6.3) and Xcode 27 (Swift 6.4). Installed baseline here is Xcode 27 Beta.3 / Swift 6.4. NOTE: Xcode 26.0-26.3 shipped Swift 6.2 and will NOT parse a `swift-tools-version: 6.3` manifest — the Swift 6.3 path requires Xcode 26.4+ (released March 24, 2026).
- **Platforms**: iOS, macOS, tvOS, watchOS, visionOS — all at `.v26` (OS 26 baseline). Every file must compile on all 5. (Verified: all five `.v26` constants present in the installed PackageDescription module; `.v27` also present.)
- **SINGLE SPM target `Nebula`** with internal folders (Core/Logging/Errors/Extensions/Formatting/Measure/Concurrency); one `import Nebula`. (Mirrors Cosmos' single-target design.)
- **NO third-party runtime dependencies** — Apple frameworks only (Foundation, `os.log`, `Synchronization`, `_Concurrency`, `CryptoKit` only if justified). `os.Logger` is the native logging API (no swift-log).
- **No UIKit symbols** — Foundation/Swift only.
- **All public value types `Sendable`** (derived conformance; avoid `@unchecked`). Handler closures `@Sendable`.
- **No `NSLock`, no `DispatchQueue` for sync, no `nonisolated(unsafe)` mutable globals.** Use `Mutex<T>`/`Atomic<T>` from `import Synchronization` (Swift 6.0+; verified present via typecheck against the SDK) when a mutable flag is unavoidable. One-time idempotent work: the once-token pattern (static-let initializer side-effect via `swift_once`, thread-safe by Swift guarantee).
- **Public API prefix `Nebula`** (mirror Cosmos "Cosmos"): `NebulaLogger`, `NebulaError`, `NebulaLogConfiguration`, `NebulaStandards`, `NebulaMeasure`.
- **Versioning**: major == OS major (Nebula 26 == OS 26). API availability IS versioning: "since Nebula 26" == `@available(iOS 26, *)`. Gate OS-introduced features with `@available`; flag anything above `.v26` (OS 27 = Nebula 27, above-floor).
- **DocC** documentation; every public symbol documented. Deprecation via `@available(*, deprecated, message:)`.
- **Apple-aligned**: prefer modern Swift APIs (`FormatStyle`, `Measurement`, `os.Logger`, `os.signpost`, `Regex`, `AttributedString`, `Duration`/`Clock`/`ContinuousClock`, `Mutex`/`Atomic`) over legacy Cocoa. (Verified: Measurement macOS 10.12/iOS 10/watchOS 3/tvOS 10; AttributedString macOS 12/iOS 15/tvOS 15/watchOS 8; Date/URL FormatStyle macOS 12-13/iOS 15-16 — all below the .v26 floor.)

## Manifest ground truth

The `Package` initializer (verified against the installed `PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface`, lines 359-363) is:

```swift
init(name: String,
     defaultLocalization: Localization? = nil,        // 5.3+
     platforms: [SupportedPlatform]? = nil,            // 5.3+
     products: [Product] = [],
     dependencies: [PackageDependency] = [],
     targets: [Target] = [],
     swiftLanguageVersions: [SwiftVersion]? = nil,
     swiftLanguageModes: [SwiftLanguageMode]? = nil,   // 6.0+  (verified line 361/363)
     traits: Set<Trait> = [],                          // 6.0+  (verified line 363)
     cLanguageStandard: CLanguageStandard? = nil,
     cxxLanguageStandard: CXXLanguageStandard? = nil)
```

- `swiftLanguageModes` and `traits` require **swift-tools-version 6.0+** (verified: the PackageDescription interface marks the older `swiftLanguageVersions` `@available(_PackageDescription, deprecated: 6, renamed: "swiftLanguageModes")`; `SwiftLanguageMode` enum cases are `.v4/.v4_2/.v5/.v6`).
- `defaultLocalization` and `platforms` require **5.3+** ([WWDC20 — Resources and localization](https://developer.apple.com/videos/play/wwdc2020/10169/)).
- `.visionOS(...)` requires **5.9+**; `.visionOS(.v2)` requires **6.0+** ([swift-package-manager commit 6db9761](https://github.com/swiftlang/swift-package-manager/commit/6db9761cd95cba734897ecf88b5f4c2a4bd40b45)). `.visionOS(.v26)` is verified present in the installed PackageDescription module (and `.v27` exists too) — well within the 6.3 envelope.
- `SwiftSetting.swiftLanguageMode(.v6)` is a per-target alternative (6.0+); for a single-target package, package-level `swiftLanguageModes: [.v6]` is cleaner ([Apple PackageDescription module](https://developer.apple.com/documentation/packagedescription)).
- The `platforms:` array declares **minimum deployment targets, not an allowlist** ([Swift Forums](https://forums.swift.org/t/no-visionos-support-for-swift-macros/70950)) — omitting a platform falls back to SwiftPM defaults; declaring all five is explicit and matches Cosmos.
- `Resource.process(_:localization:)` is preferred over `.copy`; `defaultLocalization` is **required** for any package that ships resources ([WWDC20](https://developer.apple.com/videos/play/wwdc2020/10169/), [Apple Resource docs](https://developer.apple.com/documentation/packagedescription/resource)).
- A DocC `.docc` catalog **must live inside the target's source directory** (`Sources/Nebula/Nebula.docc/`) for SwiftPM to auto-associate it ([Swift Forums — flat project structure](https://forums.swift.org/t/use-a-flat-project-structure-for-a-swift-package/70793)).

> Note: the [docs.swift.org PackageDescription page](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) is stale (2021 copyright) and does NOT show `swiftLanguageModes`/`traits`. Use [developer.apple.com/documentation/packagedescription](https://developer.apple.com/documentation/packagedescription) AND the installed `PackageDescription.swiftmodule/*.swiftinterface` as the current source of truth.

## Logging availability (drives the .v26 floor choice)

`os.Logger`/`OSLogStore`/`OSLogEntry`/`OSSignposter` are confirmed available **well below** the `.v26` floor — verified via [Apple's os logging docs](https://developer.apple.com/documentation/os/logging):

| Type | iOS | macOS | tvOS | watchOS | visionOS |
|------|-----|-------|------|---------|----------|
| `Logger` | 14+ | 11+ | 14+ | 7+ | 1+ |
| `OSLogStore` / `OSLogEntry` | 15+ | 12+ | 15+ | 8+ | 1+ |
| `OSSignpostID` | 12+ | 10.14+ | 12+ | 5+ | 1+ |
| `OSSignposter` | 15+ | 12+ | 15+ | 8+ | 1+ |

Consequence: the [[nebula-logging]] subsystem needs **no `@available` gating** at the `.v26` floor. `@available` gating is reserved for symbols introduced **above** `.v26` (Nebula 27 / OS 27). watchOS `OSLogStore` is verified scope-limited to the calling app's own logs (`.currentProcessIdentifier`; system-wide / other-process scope not available on watchOS) — [[nebula-logging]] must design `NebulaLogStore` accordingly.

The OSLog framework is a **clang umbrella module** (verified: modulemap at `/Applications/Xcode-27.0.0-Beta.3.app/.../OSLog.framework/Modules/module.modulemap` reads `framework module OSLog [system] { umbrella header "OSLog.h"; export * }`) — there is no textual `.swiftinterface` to grep; availability comes from Apple docs + the Swift overlay.

## Concurrency / stdlib availability (drives the Synchronization/_Concurrency choice)

`Mutex<T>`/`Atomic<T>` (`import Synchronization`, Swift 6.0+ stdlib) and `Duration`/`ContinuousClock` (`Foundation`/`_Concurrency`) are verified present via typecheck probes against the installed `MacOSX27.0.sdk` targeting `arm64-apple-macos26.0`:

```swift
import Synchronization
let _ = Mutex<Int>(0)      // compiles clean
let _ = Atomic<Int>(0)     // compiles clean

import Foundation
let d: Duration = .seconds(1)        // compiles clean
let c = ContinuousClock()            // compiles clean
```

`Synchronization.swiftinterface` / `_Concurrency.swiftinterface` are NOT present as standalone textual files in the toolchain (only prebuilt binary `.swiftmodule` dirs under `.../lib/swift/*/prebuilt-modules/27.0/`), so availability is verified by compilation + [Apple's Synchronization docs](https://developer.apple.com/documentation/swift/synchronization), not a local `.swiftinterface` grep. `Duration`/`ContinuousClock` live in the stdlib `_Concurrency` module (imported by the Foundation interface) and do not appear as `public struct` in `Foundation.swiftmodule/...swiftinterface` — consistent with the above. This affects [[nebula-swift6-concurrency]], not the `Package.swift`.

## Recommended Package.swift for Nebula

```swift
// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Set to 6.3 so the package builds on Xcode 26.4+ (Swift 6.3) and Xcode 27 (Swift 6.4).
// NOTE: Xcode 26.0-26.3 shipped Swift 6.2 and will NOT parse a 6.3 manifest — require Xcode 26.4+
// for the Swift 6.3 path. Any OS-27-only SDK symbol is compile-gated with `#if swift(>=6.4)`
// so it compiles to a graceful fallback on Swift 6.3 and turns on under Xcode 27 / Swift 6.4.
// Nebula is a FOUNDATION layer (no SwiftUI); consumed by apps and other SPMs.
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
            // Resources are OPTIONAL. A foundation layer emits developer-facing English log/error
            // text and ships no user-facing strings by default, so no catalog is bundled.
            // When a Localizable.xcstrings String Catalog is added under Sources/Nebula/Resources/,
            // uncomment the block below — `.process` compiles the catalog to .lproj/.strings at build
            // time and `Bundle.module` exposes it at runtime (defaultLocalization above is already set).
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
```

## Recommended Sources/Nebula/ folder tree

```
Nebula/
├── Package.swift
├── README.md
├── Sources/
│   └── Nebula/                       # SINGLE SPM target (mirrors Cosmos single-target)
│       ├── Nebula.docc/              # DocC catalog — SwiftPM auto-discovers .docc in target dir
│       │   ├── Nebula.md             # DocC root (/foundation) article
│       │   ├── Logging.md
│       │   ├── Errors.md
│       │   ├── Extensions.md
│       │   ├── Formatting.md
│       │   ├── Measure.md
│       │   └── Concurrency.md
│       ├── Core/                     # Package-wide internals + versioning
│       │   ├── NebulaVersion.swift          # major == OS major (Nebula 26 == OS 26)
│       │   └── NebulaOnce.swift             # once-token idempotent work (swift_once side-effect)
│       ├── Logging/                  # os.Logger façade — see [[nebula-logging]]
│       │   ├── NebulaLogger.swift
│       │   ├── NebulaLogConfiguration.swift # Sendable struct + @Sendable handler + .with*
│       │   ├── NebulaLogLevel.swift
│       │   └── NebulaLogHandler.swift
│       ├── Errors/                   # see [[nebula-errors]]
│       │   ├── NebulaError.swift
│       │   └── NebulaErrorConfiguration.swift
│       ├── Extensions/               # see sibling extension notes
│       │   ├── DateTime/              # Date, DateComponents, DateInterval, Calendar — [[nebula-date-time-extensions]]
│       │   ├── String/               # String, AttributedString, Regex — [[nebula-string-extensions]]
│       │   ├── Number/               # Int, Double, Decimal, Measurement, FormatStyle — [[nebula-number-measurement-extensions]]
│       │   ├── Primitive/            # Bool, UUID, Optional — [[nebula-primitive-extensions]]
│       │   ├── Collection/           # Array, Dictionary, Sequence, Set — [[nebula-collection-extensions]]
│       │   ├── Codable/              # JSONEncoder/Decoder wrappers, CodingKey helpers — [[nebula-codable-foundation]]
│       │   └── DataURL/               # Data, URL, URLComponents — [[nebula-data-url-extensions]]
│       ├── Formatting/                # NebulaStandards + FormatStyle façades — [[nebula-standardize-measure]]
│       │   └── NebulaStandards.swift
│       ├── Measure/                   # NebulaMeasure, ContinuousClock/Duration façades — [[nebula-standardize-measure]]
│       │   ├── NebulaMeasure.swift
│       │   └── NebulaMeasureConfiguration.swift
│       └── Concurrency/              # Mutex<T>/Atomic<T> thin wrappers, @Sendable helpers
│           └── NebulaConcurrency.swift      # see [[nebula-swift6-concurrency]]
└── Tests/
    └── NebulaTests/                  # Swift Testing (@Test) — mirrors source layout
```

## Recommended design for Nebula

### Public API surface (manifest-architecture layer)

| Symbol | Kind | Purpose |
|--------|------|---------|
| `Package(name:defaultLocalization:platforms:products:dependencies:targets:swiftLanguageModes:)` | manifest initializer | Nebula's `Package.swift` — name "Nebula", `defaultLocalization "en"`, platforms `[.iOS/.macOS/.tvOS/.watchOS/.visionOS .v26]`, single `.library` product, empty `dependencies`, single `.target` + single `.testTarget`, `swiftLanguageModes [.v6]`. `swift-tools-version 6.3`. (Verified: PackageDescription.swiftinterface line 361; full signature also includes pkgConfig/providers/cLanguageStandard/cxxLanguageStandard; line 363 adds `traits:`.) |
| `.library(name:"Nebula", targets:["Nebula"])` | product | The single library product consumed by apps and other SPMs via `import Nebula`. |
| `.target(name:"Nebula", dependencies:[], resources:[ /* .process("Resources") opt-in */ ])` | target | The single Nebula target owning Core/Logging/Errors/Extensions/Formatting/Measure/Concurrency folders and the `Nebula.docc` catalog. No external dependencies. |
| `.testTarget(name:"NebulaTests", dependencies:["Nebula"])` | test target | Swift Testing test target mirroring the source layout; depends only on Nebula. |
| `#if swift(>=6.4)` | compile conditional | Gate OS-27-only SDK symbols so they compile to a fallback under Swift 6.3 (Xcode 26.4+) and activate under Swift 6.4 (Xcode 27). Matches Cosmos. |
| `#if os(watchOS)` / `#if os(visionOS)` | compile conditional | Gate platform-specific surfaces (e.g. watchOS `OSLogStore` scope, platform-absent `FormatStyle` cases) across the 5-platform matrix. |
| `Sources/Nebula/Nebula.docc/` | DocC catalog directory | Auto-discovered documentation catalog; must live inside the target's source directory for SwiftPM to associate it with the Nebula target. |
| `.process("Resources")` (opt-in) | resource rule | Compiles a `Localizable.xcstrings` String Catalog to `.lproj/.strings` at build time when Nebula ships user-facing strings; commented out by default. |
| `SwiftLanguageMode.v6` | language mode constant | Package-wide Swift 6 strict concurrency via `swiftLanguageModes: [.v6]`. Verified present (enum cases `.v4/.v4_2/.v5/.v6`). |
| `SupportedPlatform.{iOS,macOS,tvOS,watchOS,visionOS}(.v26)` | platform version constant | Verified: all five `.v26` constants present in the installed PackageDescription module (`.v27` also present for each). |

### Design rationale

1. **Single target, single product, single test target** — mirrors Cosmos and satisfies the binding constraint. Consumers `import Nebula` once; internal folder boundaries are physical, not module, boundaries. No `NebulaLogging`/`NebulaExtensions` sub-products (would fragment the API and break the "one import" rule).
2. **swift-tools-version: 6.3** — minimum toolchain that supports `swiftLanguageModes` (6.0+) and `.visionOS(.v26)` (5.9+/6.0+ for `.v2+`). 6.3 lets the same manifest build on Xcode 26.4+ (Swift 6.3) and Xcode 27 (Swift 6.4). The installed Xcode 27 Beta.3 / Swift 6.4 toolchain parses it (verified). NOTE: Xcode 26.0-26.3 shipped Swift 6.2 and will NOT parse a 6.3 manifest — the Swift 6.3 path requires Xcode 26.4+.
3. **swiftLanguageModes: [.v6]** — package-wide Swift 6 strict concurrency (`Sendable`, zero warnings). Equivalent to per-target `.swiftLanguageMode(.v6)` SwiftSetting but applied at package level (cleaner for a single-target package). Confirmed available since swift-tools 6.0 ([Apple PackageDescription](https://developer.apple.com/documentation/packagedescription)).
4. **Platform matrix all .v26** — declares minimum deployment targets, not an allowlist ([Swift Forums](https://forums.swift.org/t/no-visionos-support-for-swift-macros/70950)); explicit declaration matches Cosmos and Apple's modern multi-platform framework manifests. `.visionOS(.v26)` is verified valid under tools 6.3.
5. **defaultLocalization: "en"** — set unconditionally (matches Cosmos). Required only when resources ship, but harmless and forward-compatible if a String Catalog is added later.
6. **No resources by default** — foundation has no user-facing strings; log/error text is developer-facing English. The `.process("Resources")` line is present but commented so flipping it on is a one-line change when a `Localizable.xcstrings` is introduced ([WWDC20](https://developer.apple.com/videos/play/wwdc2020/10169/)).
7. **No third-party dependencies** — `dependencies: []`. No swift-log, no swift-docc-plugin. DocC catalog builds natively in Xcode 26/27; CLI generation, if ever needed, can use `xcodebuild docbuild` without a plugin dependency.
8. **DocC catalog at `Sources/Nebula/Nebula.docc/`** — SwiftPM only auto-associates a `.docc` directory when it lives inside the target's source directory ([Swift Forums](https://forums.swift.org/t/use-a-flat-project-structure-for-a-swift-package/70793)).
9. **Compile-gating above-floor symbols** — `#if swift(>=6.4)` for OS-27-only SDK symbols (graceful fallback on Swift 6.3, enabled on Swift 6.4), and `#if os(watchOS)` / `#if os(visionOS)` for platform-specific surfaces. The floor is `.v26`; "since Nebula 26" == `@available(iOS 26, *)`; "Nebula 27" features sit above-floor and are gated.
10. **Swift Testing, not XCTest** — `NebulaTests` uses `@Test`/`#expect` (matches Cosmos' `Tests/CosmosTests` and the Swift 6 toolchain).

## Apple patterns adopted

- Single-target SPM package with internal physical folders (not sub-modules) — mirrors Cosmos and Apple's own single-framework design; consumers `import Nebula` once.
- `swift-tools-version: 6.3` + `swiftLanguageModes: [.v6]` — package-wide Swift 6 strict concurrency, the modern Apple-recommended language mode ([WWDC24 — Migrate your app to Swift 6](https://developer.apple.com/videos/play/wwdc2024/10169/)).
- Five-platform `.v26` matrix (`.iOS`/`.macOS`/`.tvOS`/`.watchOS`/`.visionOS`) — minimum deployment targets, not an allowlist; explicit declaration matches Cosmos and Apple's modern multi-platform framework manifests.
- `defaultLocalization: "en"` + conditional `.process("Resources")` — Apple's resource/localization model ([WWDC20](https://developer.apple.com/videos/play/wwdc2020/10169/)): `defaultLocalization` required when resources ship, `.process` preferred over `.copy`, `Bundle.module` for runtime access.
- DocC catalog at `Sources/Nebula/Nebula.docc/` — Apple/SwiftPM convention that the `.docc` directory must sit inside the target's source folder for auto-association ([Swift Forums](https://forums.swift.org/t/use-a-flat-project-structure-for-a-swift-package/70793)).
- `os.Logger` as the native logging API (no swift-log) — `os.Logger`/`OSLogStore`/`OSLogEntry`/`OSSignposter` all available below the `.v26` floor ([os logging](https://developer.apple.com/documentation/os/logging)); no `@available` gating needed for the Logging subsystem.
- `#if swift(>=6.4)` compile-gating for above-floor (OS-27) symbols — graceful fallback under the older toolchain, matching Cosmos' dual-Xcode-26+27 build strategy.
- `#if os(...)` for platform-specific surfaces — Apple's standard conditional-compilation idiom for multi-platform SwiftPM packages.
- No third-party runtime or build dependencies (`dependencies: []`, no swift-docc-plugin) — Apple-frameworks-only constraint; DocC builds natively in Xcode.
- Swift Testing (`@Test`) for `NebulaTests` — Apple/Swift's modern test framework, matching Cosmos' test target.
- `major == OS major` versioning (Nebula 26 == OS 26) and API-availability-as-versioning — `@available(iOS 26, *)` reads as "since Nebula 26"; above-floor features are Nebula 27 and compile-gated.

## Risks & open questions

**Risks**
- `swift-tools-version: 6.3` requires **Xcode 26.4+ (Swift 6.3)** — VERIFIED that Swift 6.3 first shipped in Xcode 26.4 (March 24, 2026, build 17E192). Xcode 26.0-26.3 shipped Swift 6.2 and will NOT parse a `swift-tools-version: 6.3` manifest. The original research's "Xcode 26 (Swift 6.3)" framing was imprecise. Mitigation: document the Xcode 26.4+ / Xcode 27 requirement explicitly in README and CI image pinning (same baseline as Cosmos).
- The [docs.swift.org PackageDescription page](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) is stale (2021 copyright) and does NOT show `swiftLanguageModes`/`traits` — relying on it alone would mislead. Mitigation: use [developer.apple.com/documentation/packagedescription/package](https://developer.apple.com/documentation/packagedescription/package) and the installed `PackageDescription.swiftmodule/*.swiftinterface` as the current source of truth.
- `.visionOS(.v26)` is VERIFIED valid under tools 6.3 — `VisionOSVersion.v26` constant is present in the installed PackageDescription module (alongside `.v27`). The historical "5.9 for `.visionOS`, 6.0 for `.v2`" claim is corroborated by the swift-package-manager commit cited; `.v26`/`.v27` are well within the 6.3 envelope.
- `Synchronization.swiftinterface` / `_Concurrency.swiftinterface` are NOT present as standalone textual files in the toolchain (VERIFIED: only prebuilt binary `.swiftmodule` dirs exist under `.../lib/swift/*/prebuilt-modules/27.0/`). `Mutex<T>`/`Atomic<T>` availability is VERIFIED via a typecheck probe (clean compile against the SDK targeting `arm64-apple-macos26.0`), not a local grep. `Duration`/`ContinuousClock` live in the stdlib `_Concurrency` module (imported by Foundation), not in `Foundation.swiftinterface` as `public struct` — confirmed by grep returning no struct decl; typecheck probe confirms they compile. Affects [[nebula-swift6-concurrency]], not the `Package.swift`.
- OSLog is a clang umbrella module with no textual `.swiftinterface` (VERIFIED via module.modulemap). `os.Logger`/`OSLogStore`/`OSLogEntry`/`OSSignposter` availability VERIFIED via [Apple docs](https://developer.apple.com/documentation/os/logging) (Logger iOS 14/macOS 11/tvOS 14/watchOS 7/visionOS 1; OSLogStore/OSLogEntry/OSSignposter iOS 15/macOS 12/tvOS 15/watchOS 8/visionOS 1 — all below `.v26`). watchOS `OSLogStore` is VERIFIED scope-limited to the calling app's own logs (`.currentProcessIdentifier`; system-wide / other-process scope not available) — design [[nebula-logging]]'s `NebulaLogStore` accordingly.
- Declaring all five platforms at `.v26` does NOT exclude any platform (`platforms:` declares minimums, not an allowlist). If a future platform (e.g. driverKit) is undesirable, SwiftPM offers no exclude API — acceptable for a foundation layer that targets all five Apple platforms anyway.
- Optional `.process("Resources")` left commented: if a String Catalog is later added without uncommenting, `Bundle.module` will not be synthesized and `NSLocalizedString` lookups will fail silently at runtime. Mitigation: a CI check or a `CONTRIBUTING.md` note tying the catalog's presence to the resources block.
- `swiftLanguageModes: [.v6]` is package-wide; if a future sub-target needs v5 mode temporarily, it must override with a per-target `.swiftLanguageMode(.v5)` SwiftSetting (6.0+; verified `SwiftLanguageMode` has a `.v5` case). Not needed for Nebula today.

**Open questions**
- Does Nebula ship a `Localizable.xcstrings` at launch? If yes, uncomment `.process("Resources")` and ensure `Sources/Nebula/Resources/Localizable.xcstrings` exists; if no, leave commented and document the toggle in `CONTRIBUTING.md`.
- Should Nebula expose a `NebulaVersion` / `@available` alias helper so "since Nebula 26" maps cleanly to `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`? Cosmos handles this at the component level; a foundation may centralize it in `Core/NebulaVersion.swift`.
- Is a `swift-docc-plugin` command-plugin dependency acceptable for CI doc generation (build-time only, not runtime)? The binding constraint forbids third-party RUNTIME deps; the plugin is build-time. Recommend avoiding it (use `xcodebuild docbuild`) to keep `dependencies: []` pristine — confirm with the user.
- Should the `Extensions/` subfolders be physical directories (proposed) or a flat `Extensions/` folder? Physical subfolders mirror a foundation's type-grouping; flat mirrors Cosmos' `Atoms/`. Decide based on file count once extensions are enumerated in sibling notes.
- Do any watchOS/visionOS `FormatStyle` cases differ or need `#if os(...)` gating? Flagged for [[nebula-number-measurement-extensions]] and [[nebula-date-time-extensions]] to resolve against the Foundation `.swiftinterface` `@available` lines. (Verified so far: `DiscreteFormatStyle` for Date/Duration is `@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)` — still below the `.v26` floor, so ungated; but platform-specific case availability still needs enumeration.)
- Exact CI Xcode pin for the Swift 6.3 path: must be Xcode 26.4+ (Swift 6.3), not Xcode 26.0-26.3 (Swift 6.2). Confirm the CI image version with the user to avoid a manifest-parse failure.

## Sources

- [Apple Developer Documentation — Package (PackageDescription)](https://developer.apple.com/documentation/packagedescription/package)
- [Apple Developer Documentation — Resource (PackageDescription)](https://developer.apple.com/documentation/packagedescription/resource)
- [Apple Developer Documentation — PackageDescription module root](https://developer.apple.com/documentation/packagedescription)
- [Swift Package Manager — PackageDescription (docs.swift.org, stale snapshot)](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html)
- [Apple Developer Documentation — os Logging](https://developer.apple.com/documentation/os/logging)
- [WWDC20 — Swift packages: Resources and localization](https://developer.apple.com/videos/play/wwdc2020/10169/)
- [WWDC24 — Migrate your app to Swift 6](https://developer.apple.com/videos/play/wwdc2024/10169/)
- [swift-package-manager — Add visionOS as a platform (commit 6db9761, 5.9)](https://github.com/swiftlang/swift-package-manager/commit/6db9761cd95cba734897ecf88b5f4c2a4bd40b45)
- [Swift Forums — Use a flat project structure for a Swift package (DocC catalog placement)](https://forums.swift.org/t/use-a-flat-project-structure-for-a-swift-package/70793)
- [Swift Forums — No visionOS support for Swift Macros? (platforms: are minimums, not allowlist)](https://forums.swift.org/t/no-visionos-support-for-swift-macros/70950)
- [Apple Developer Forums — Xcode always enabling default package traits (real 6.3 manifest example)](https://developer.apple.com/forums/thread/820911)
- [swiftlang/swift-docc-plugin (build-time DocC plugin, NOT adopted by Nebula)](https://github.com/swiftlang/swift-docc-plugin)
- [Apple Developer Documentation — Swift Synchronization (Mutex/Atomic)](https://developer.apple.com/documentation/swift/synchronization)
- [Swift 6.3 RELEASE (first shipped in Xcode 26.4, March 24, 2026)](https://github.com/swiftlang/swift/releases/tag/swift-6.3-RELEASE)
- [Announcing Swift 6.3.1 — Swift Forums](https://forums.swift.org/t/announcing-swift-6-3-1/86080)
- [Local precedent — Cosmos Package.swift](file:///Users/rafael.escaleira/Documents/projects/personal/cosmos/Package.swift)
- [Local precedent — Cosmos ARCHITECTURE.md](file:///Users/rafael.escaleira/Documents/projects/personal/cosmos/ARCHITECTURE.md)
- [Installed SDK — OSLog.framework module.modulemap (Xcode 27 Beta.3)](file:///Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/OSLog.framework/Modules/module.modulemap)
- [Installed SDK — Foundation.swiftmodule/arm64e-apple-macos.swiftinterface (Xcode 27 Beta.3)](file:///Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface)
- [Installed toolchain — PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface (verified Package init + swiftLanguageModes + .v26 constants)](file:///Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface)

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.