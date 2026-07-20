---
tags: [riscos, availability, gating, nebula-26-4, swift6]
aliases: [Above-floor 26.4 APIs, above-floor APIs, Nebula 26.4 gating]
related: [[Home]], [[nebula-spm-architecture]], [[nebula-string-extensions]], [[nebula-data-url-extensions]], [[nebula-primitive-extensions]]
status: open
---

# Above-floor 26.4 APIs

Gotcha listing the **above-floor (Nebula 26.4)** APIs that require an explicit `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)` gate — they are NOT available at the Nebula 26 floor and must not be called unguarded. Source of truth = root docs (`ARCHITECTURE.md`, `VERSIONING.md`, `CLAUDE.md`); this note is synthesis.

## The 26.4-gated APIs

- `Data.Base64EncodingOptions.base64URLAlphabet` / `.omitPaddingCharacter`
- `String.Encoding.ianaName` getter AND `init?(ianaName:)`
- `UUID.random(using:)`

## Origin

Surfaced as OS 26.4 via swift-foundation **SF-0031 / FoundationPreview 6.3**. NOTE this is the **parameterized `random(using:)`** (passing a `RandomNumberGenerator`), NOT the parameterless `random()` — `UUID()` remains the default v4 generator. WebFetch has hallucinated both a parameterless `UUID.random()` and wrong availability for it; see [[webfetch-availability-hallucinations]].

## Pattern

Per the versioning contract, "since Nebula 26.4" == `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)`. These gates sit ABOVE the Nebula 26 floor and so must be added explicitly; the floor gate `@available(iOS 26, …)` does not cover them. Defer the base64URL / omitPadding surfaces to Nebula 26.4 where the vault documents them ([[nebula-string-extensions]], [[nebula-data-url-extensions]]).