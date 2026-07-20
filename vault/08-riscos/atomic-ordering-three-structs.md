---
tags: [riscos, swift6, concurrency, synchronization, atomic, ordering]
aliases: [Atomic ordering three structs, AtomicLoadOrdering, no single Ordering enum]
related: [[Home]], [[nebula-swift6-concurrency]]
status: open
---

# Atomic ordering: three structs, no single `Ordering` enum

Gotcha: there is **NO single `Ordering` enum** for `Atomic<T>` (from `import Synchronization`). There are three frozen `Sendable` structs, each valid for a different operation. Source of truth = the `Synchronization` `.swiftinterface` + `CLAUDE.md`; this note is synthesis.

## The three structs

- **`AtomicLoadOrdering`** — `.relaxed` / `.acquiring` / `.sequentiallyConsistent`. **`.acquiringAndReleasing` is INVALID for `load`.**
- **`AtomicStoreOrdering`** — for stores.
- **`AtomicUpdateOrdering`** — `.acquiringAndReleasing` is valid here; used by `compareExchange` / `exchange`.

A common mistake is reaching for a single `Ordering` enum (the C++ mental model) and passing `.acquiringAndReleasing` to `load` — that does not compile.

## Nebula usage

`NebulaFlag` (the `Atomic<Raw.Value>` wrapper) uses:

- `NebulaFlag.load` → `.acquiring`
- `NebulaFlag.set` → `.releasing`
- `NebulaFlag.compareExchange` → `.acquiringAndReleasing`

See [[nebula-swift6-concurrency]] for the broader concurrency ground truth, and [[mutex-sending-not-transferring]] for the sibling `Mutex.withLock` spelling gotcha.