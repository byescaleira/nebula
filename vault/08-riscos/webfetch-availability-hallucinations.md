---
tags: [riscos, research, verification, webfetch, availability]
aliases: [WebFetch availability hallucinations, WebFetch unreliable availability]
related: [[Home]], [[nebula-app-readiness-research]]
status: open
---

# WebFetch hallucinates Apple availability tables

Gotcha: WebFetch on `developer.apple.com` has **repeatedly hallucinated availability tables**. It is not a reliable source for Apple API availability. Source of truth = the Xcode 27 Beta 3 SDK `.swiftinterface`; this note is synthesis.

## Confirmed hallucinations

- `UUID.random` reported as "iOS 13+" — wrong.
- A **parameterless** `UUID.random()` — does not exist (the real API is `UUID.random(using:)`, parameterized; `UUID()` remains the default v4). See [[above-floor-26-4-apis]].
- "UUID is not `Comparable`" — wrong.
- `percentEncodedQueryItems` reported as "iOS 16+".
- `OutputFormatting.fragmentsAllowed` — does not exist as a `JSONEncoder` option (that's `JSONSerialization.WritingOptions`); `ReadingOptions` uses `.allowFragments`.
- `convertFromKebabCase` — reported as a real `JSONDecoder.KeyDecodingStrategy`; it is not.
- `base64Encode` — reported as an existing `Data` API; Foundation has no native hex (Nebula ships `nebulaHexEncodedString`, see [[nebula-data-url-extensions]]).

## Rule

The `.swiftinterface` (Xcode 27 Beta 3 SDK) is **authoritative** for Apple API availability — never rely on WebFetch for availability. When verifying, cite interface line numbers. This is the same "verify against ground truth, not assumptions" theme as [[ci-warning-masking-and-inference-fragility]]. The sibling `apple-docs-mcp-not-working` note lives in the Claude memory store (not the vault) and documents the same theme.