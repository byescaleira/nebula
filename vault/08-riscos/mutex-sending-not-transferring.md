---
tags: [riscos, swift6, concurrency, synchronization, se-0430, se-0433]
aliases: [Mutex.withLock sending not transferring, SE-0430 sending, Mutex transferring revised]
related: [[Home]], [[nebula-swift6-concurrency]]
status: open
---

# `Mutex.withLock` uses `sending`, not `transferring`

Gotcha: `Mutex.withLock` (from `import Synchronization`) uses **`sending`** (SE-0430, standardized on `sending`) — NOT **`transferring`** (the earlier SE-0433 spelling was revised). Source of truth = the `Synchronization` `.swiftinterface` + `CLAUDE.md`; this note is synthesis.

## Why it bites

Wrapper types that forward `Mutex.withLock` to an inner `Mutex` (e.g. `NebulaLocked`, `NebulaDefaults`, `NebulaKeychainConfig`-style `Mutex`-backed accessors) must declare their forwarding signatures with `sending` to match the stdlib. A signature written with the older `transferring` keyword will not compile under the Swift 6.3 toolchain, and copying an old example will silently introduce the wrong spelling.

## Rule

- `Mutex.withLock` body parameter: `sending` (SE-0430).
- Do NOT use `transferring` (SE-0433 was revised into SE-0430).
- `Mutex<T>` / `Atomic<T>` are `~Copyable` and `@_staticExclusiveOnly` → always declare `let`, never `var`. See [[nebula-swift6-concurrency]] for the full mutex/atomic ground truth.