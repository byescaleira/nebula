---
tags: [riscos, ci, swift6, build, formatstyle, testing]
aliases: [CI warning masking, inference fragility, swift test incremental masking]
related: [[Home]], [[nebula-spm-architecture]], [[nebula-standardize-measure]], [[webfetch-availability-hallucinations]]
status: open
---

# CI warning masking + FormatStyle inference fragility

Gotcha: two non-obvious traps that bit the Nebula 0.1.0 release — the first CI run went red on the runner while everything passed locally. Source of truth = the build behavior + `CLAUDE.md`; this note is synthesis. (Mirrors the Claude-memory note of the same name; the vault copy is the project-facing record.)

## 1. `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` is NOT honored by SwiftPM

It is an Xcode build-system setting, read by `xcodebuild`, not by `swift build` / `swift test`. The CI host job sets it in `env:`, but `swift test` ignores it — so test-target warnings never fail CI that way. The matrix `xcodebuild build` jobs DO honor it, but they only build the `Nebula` target (not `NebulaTests`), so test-target warnings are entirely unenforced on CI.

**To actually enforce zero-warnings on the test target**, add `swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]` to the `NebulaTests` target (safe — the test target is never a dependency; NEVER put `unsafeFlags` on the main `Nebula` target, it breaks consumers). Not yet done as of 0.1.0.

## 2. Incremental `.build` caches mask whole-module compile errors

`StandardizeTests.measurementProducesNonEmptyString` called `m.formatted(pinned.measurement(usage:))` relying on bidirectional inference to pin `U = UnitLength`. Local `swift test` passed (cached modules + the local type-checker resolved `U = UnitLength`), but a fresh whole-module build on the CI runner (macos-26 / Xcode 27) resolved `U = Dimension` (the bound) → hard compile error.

**Always verify with `rm -rf .build && swift test` before pushing** — incremental success is not evidence.

## Generalized fix pattern

Any generic `FormatStyle` accessor whose type parameter is inferred ONLY from return-type context (e.g. `NebulaStandards.measurement<U: Dimension>` — no parameter pins `U`) needs an **explicit type annotation at the call site** (`let style: Measurement<UnitLength>.FormatStyle = pinned.measurement(usage:)`), mirroring how the `ListFormatStyle` test already annotates. Don't rely on bidirectional inference from `value.formatted(accessor(...))`.

## How to apply

Before any push, run `rm -rf .build && swift test > /tmp/t.log 2>&1` (the `> file 2>&1` order matters — `2>&1 > file` sends stderr to the terminal, not the file) and `grep "warning:"` the log. Treat incremental `swift test` as non-authoritative.

This is the sibling of [[webfetch-availability-hallucinations]] — both are "verify against ground truth, not assumptions": one for the compiler, one for Apple availability.