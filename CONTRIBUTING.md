## Contributing

1. Keep contracts and extensions small and single-purpose. Prefer Apple-native primitives (`os.Logger`, `FormatStyle`, `Measurement`, `Regex`, `Mutex`/`Atomic`) over re-implementations; no legacy `Formatter` subclasses in the public surface.
2. Prefer semantic Sendable struct + `@Sendable` handler + fluent `.with*` builder contracts over ad hoc configuration. Mirror `CosmosConfiguration`/`CosmosLogConfiguration`/`CosmosErrorConfiguration` minus the SwiftUI `@Entry`/`@Observable` plumbing.
3. Add `nebula*`-prefixed methods on open `Collection`/`Sequence` to avoid stdlib namespace pollution; use natural names on `Comparable`/`Optional`/`BinaryInteger` gap-fillers (`clamped(to:)`, `or(_:)`, `isEven`).
4. Document public APIs with DocC. Every public symbol gets a DocC comment; the catalog lives at `Sources/Nebula/Nebula.docc/` (auto-discovered by SwiftPM because it is inside the target's source directory).
5. Add Swift Testing unit tests for contracts, extensions, and behavior. Build per-platform to confirm `#if os()` coverage. The `.swiftinterface` (Xcode 27 Beta 3 SDK) is the authoritative ground truth for Apple API availability — not WebFetch (which has hallucinated availability tables).
6. Maintain backward compatibility for a major version after deprecation. Mark `@available(*, deprecated, message:)` with a migration runway before obsoletion.
7. All public value types are `Sendable` by derived conformance — never author `@unchecked Sendable` on a Nebula-defined type. Handlers are `@Sendable`. No `NSLock`, no `DispatchQueue` for synchronization, no `nonisolated(unsafe)` mutable globals. Shared mutable state uses `Mutex<T>` / `Atomic<T>` from `import Synchronization`. One-time idempotent setup uses the once-token `static let` pattern (swift_once).
8. `@available` gates include all 5 platforms: `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`. macOS-only gating uses `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` — NOT `@available(macOS 12, *)` alone (the `*` fallback enables all platforms).

## Vault discipline

Every research task — competitive analysis, API investigation, docs review, verification — must be persisted into the Obsidian knowledge vault at `vault/` (open it in Obsidian: *Open folder as vault* → `vault/`). The vault is the project's long-term memory; it is not acceptable to do research and leave it only in chat.

- Write findings as interlinked markdown notes (frontmatter `tags`/`aliases`/`related` + `[[wikilinks]]`; kebab-case filenames). Add to the appropriate folder: `01-fundamentos/` (foundation subsystems), `03-padroes/` (SPM architecture, Swift 6 concurrency), `07-metodologia/` (workflows/methods), `08-riscos/` (open risks/refuted specs), `02-decisoes/` (new ADRs).
- Link from `[[Home]]` (the MOC) and any related notes so the graph stays connected. Verify new `[[wikilinks]]` resolve (alias or filename).
- The source of truth stays the root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `VERSIONING.md`, `CLAUDE.md`); the vault is a synthesis/navigation layer. On conflict, the root doc wins — update the note.
- Prefer a focused note over appending to an existing wall of text; cross-link instead of duplicating.

## Branching

- `main` — stable releases only
- `develop` — integration branch
- `feature/<name>` — new contracts / extensions / subsystems
- `fix/<name>` — bug fixes

## Per-platform build & verify

```bash
swift build
swift test
swift build -c release
```

Build for **each** target platform to confirm `#if os()` coverage (iOS / macOS / tvOS / watchOS / visionOS). Zero concurrency warnings under Swift 6 mode is mandatory — fix isolation/Sendable; do not silence. CI must pin Xcode 26.4+ (Swift 6.3); Xcode 26.0–26.3 (Swift 6.2) will NOT parse a `swift-tools-version: 6.3` manifest.

## Swift Testing

Tests live in `Tests/NebulaTests/` and use Swift Testing (`@Test`/`#expect`), mirroring the source layout. No XCTest, no UI snapshots, no ViewInspector (Nebula has no UI). Tests for contracts, extensions, and behavior; the `.swiftinterface` is the authoritative ground truth for availability assertions in tests.

## DocC

The DocC catalog lives at `Sources/Nebula/Nebula.docc/` (auto-discovered by SwiftPM because it is inside the target's source directory). Catalog articles: `Nebula.md` (root), `Logging.md`, `Errors.md`, `Extensions.md`, `Formatting.md`, `Measure.md`, `Concurrency.md`. Generate docs via `xcodebuild docbuild` — no `swift-docc-plugin` dependency (keep `dependencies: []` pristine).

## Resources

`.process("Resources")` is commented out in `Package.swift` by default — a foundation layer emits developer-facing English log/error text and ships no user-facing strings. When a `Localizable.xcstrings` String Catalog is added under `Sources/Nebula/Resources/`, uncomment the block (`.process` compiles the catalog to `.lproj/.strings` at build time; `Bundle.module` exposes it at runtime; `defaultLocalization: "en"` is already set). A CI check or a CONTRIBUTING note ties the catalog's presence to the resources block.

## Release Process

1. Bump version in `Package.swift` and `README.md`.
2. Update `CHANGELOG.md` (Keep-a-Changelog sections, Nebula/OS alignment at the top of the entry).
3. Tag release `X.Y.Z`.
4. Merge to `main`.