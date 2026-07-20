---
tags: [nebula, architecture, di, composition-root, swift, clean-architecture]
aliases: [nebula composition root, NebulaCompositionRoot, NebulaExample, nebula di wiring]
related: [[nebula-app-readiness-research]], [[nebula-registry-di]], [[nebula-clean-architecture-toolkit]], [[nebula-usecase]]
status: shipped
researched: "2026-07-19"
shipped: "0.8.0 (Wave N11, 2026-07-20)"
---

# Nebula — Composition root / DI wiring in Swift 6

> **Shipped as N11 / 0.8.0** — the recipe half lives in the DocC article `ArchitectureCompositionRoot.md` (linked from `Architecture.md` after `ArchitectureRegistry`). The runnable `@MainActor @Observable` vertical is the follow-up **N11b** in a sibling (Meridian). No new Nebula type — the existing `NebulaRegistry` (factories-only) + explicit-parameter constructor injection is the documented best practice.

> Research depth for the composition-root dimension of [[nebula-app-readiness-research]]. Architectural pattern research (não API availability) — o `.swiftinterface` não é load-bearing aqui. Sources: WWDC + Point-Free/TCA/Factory/InnoDI (third-party — aprender o pattern, NÃO o dep).

## Dimension overview

Apple **não tem framework DI oficial** e não endossa primitivo de composition-root; o guidance canônico (WWDC19 Session 415 "Modern Swift API Design", Ben Cohen/Doug Gregor) é **explorar concrete types primeiro, chegar em protocols só para code reuse**, e preferir **generic structs sobre protocols "is-a"** — o que valida diretamente o `NebulaUseCase<I,O>` struct-of-closures e o `NebulaRepository<Element>` PAT. O consenso da comunidade (Point-Free Dependencies, TCA, swift-navigation, Factory, InnoDI): o composition root é **job do app**, built at launch via **explicit constructor injection** de valores `Sendable`, com `@MainActor` confinado ao root que possui UI (viewmodels/coordinators) e serviços `nonisolated Sendable` cruzando o boundary via `await`. Nebula já ship o seam surface certo (`NebulaRegistry` factories-only, async `NebulaRouter` port, `NebulaViewModel` bare marker); o gap é **recipe documentado + runnable example**, não novos tipos Nebula.

## Best-practice pattern (cited)

- **Sem Apple DI framework.** Apple fornece `Mutex`/`Atomic` (Synchronization), `@MainActor`, typed throws — primitivos, não container. WWDC19 415 "Modern Swift API Design" — "start with a protocol" é **qualificado**: "first explore the use case with concrete types… consider creating a generic type instead of a protocol." Valida struct-of-closures (`NebulaUseCase`) + PAT-com-existenciais (`any NebulaRepository<E>`) sobre protocol-witness DI surface.
- **Protocol witnesses são alternativa, não mandato.** Point-Free Ep 33–35: qualquer protocol → struct of closures; o valor é **multi-conformance + composability**, não DI. Os markers Nebula (`NebulaInputPort`/`NebulaOutputPort`/`NebulaGateway`) são bare `Sendable` — rewrite witness duplicaria o seam sem ganho compile-time.
- **Composition root = app launch, explicit constructor injection, `@MainActor` no root only.** `@MainActor` é raro em library/CLI code; passe valores `Sendable` across o boundary, `await MainActor.run { … }` só para **event boundaries**, nunca como workaround geral; `nonisolated(unsafe)` é escape hatch intencionalmente feio. É precisamente a stance Nebula "no `@MainActor` default isolation; app supplies its own".
- **`@MainActor`-isolated factory closures são hazard Swift 6.** Factory#322: mesmo quando o compiler aceita factory `@MainActor`, resolver de `Task.detached` pode trip `MainActor.assertIsolated()` em runtime — o init não rodou no main actor de fato. **Implicação Nebula:** factory `NebulaRegistry` retornando viewmodel `@MainActor` carregaria o mesmo hazard — mantenha registry factories `nonisolated @Sendable`, deixe o app hop.
- **Task-local scoping (swift-dependencies) precisa single entry point.** `@Dependency`/`withDependencies` "work best with single-entry-point, closed systems" (TCA `reduce`, SwiftUI `body`); em UIKit/AppKit com muitos entry points, scoping é manual. **Implicação:** Nebula é library sem entry point — override task-local seria ergonomicamente mais fraco que o path explicit-parameter que Nebula já championa.
- **TCA composition root = `Store(initialState:) { Feature() }` + `.dependency()` per-scope overrides**; o reducer é o single entry point que faz `@Dependency` capturar em `.run` effect closures automaticamente. **Implicação:** `NebulaUseCase` struct já captura seus ports no body `@Sendable` — equivalente ao effect-closure capture do TCA, sem machinery task-local.
- **swift-navigation hybrid** (tree-based `Optional`/`enum` + `@Presents` para modals + stack-based `StackState`/`StackAction` para drill-down, wired no app feature). **Implicação:** Nebula já ship o análogo Foundation-only (`NebulaNavigationStack<Route>` + `NebulaRouter<Route>` async port); Meridian's `Router` é o concrete `@Observable`. O wiring pattern já está coberto — falta a **vertical completa** (viewmodel ← usecase ← repo ← gateway ← cache), não a metade navigation.
- **InnoDI `@DIContainer(mainActor: true)` + `@Provide(.input)`** — macro-driven, **compile-time-validated** composition root onde `.input` slots são eager values passados como `init(...)` sintetizado — "explicit constructor injection" como `init` gerado, sem `@Injected` property wrapper, sem runtime lookup. **Implicação:** é o shape que o recipe Nebula deve descrever em plain Swift (sem macro — `dependencies: []`), validando que o path explicit-parameter é a best practice moderna.
- **Medium — Composition Root with KeyPaths** (Rozdobudko): `Dependencies` protocol + `Partial<Wrapped>` + `Resolver` (cache-or-create) + `CompositionRoot` impl. **Caveat:** usa `NSRecursiveLock` — **viola a regra no-NSLock do Nebula**; o pattern é instrutivo mas a sync deve ser `Mutex<T>`. KeyPath-keyed overrides ganham compile-time key safety mas perdem a open-struct extensibilidade que `NebulaLogCategory`/`NebulaRegistryKey` espelham.

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| **Composition-root recipe** (DocC `ArchitectureCompositionRoot.md` + vault `nebula-composition-root.md`) | **Ship in Nebula** | Documenta o wiring `viewmodel ← usecase ← repository ← gateway ← cache` com seams existentes; fecha o risk "single-target → convention not compile-time" na camada doc | Nenhuma — pure docs, Foundation-only |
| **`NebulaExample` runnable app module** (vertical completa: `@MainActor @Observable` viewmodel ← `NebulaUseCase` ← `NebulaFakeRepository` + real `NebulaHTTPGateway` + `NebulaURLCache`) | **Ship em sibling (extender Meridian ou novo `NebulaCompositionExample`), NÃO em Nebula** | Viewmodel é `@MainActor @Observable` (território Meridian); Nebula é Foundation-only sem SwiftUI — um runnable *app* demonstrando o hop `@MainActor` não pode viver em Nebula. Variante CLI (à la `AuroraExample`) viveria em Nebula mas não ilustraria o hop `@MainActor` que é o load-bearing Swift 6 wiring concern | `@MainActor` + `@Observable` + SwiftUI `App` todos proibidos em Nebula; o example vive onde esses são legais (sibling). Precedente `MeridianExample`/`AuroraExample` |
| **`NebulaRegistry` scope-extension** (singleton caching, scoped resolution, auto-injection graph) | **Defer (efetivamente Reject)** | Singleton/scoping/graph = DI container — exatamente o scope creep flaggado em `clean-architecture-toolkit-risks.md` #3; `dependencies: []` proíbe Resolver/Factory/Swinject | Tensão direta com "NOT a DI container" + no-third-party |
| **`NebulaCompositionRoot` helper type** | **Doc-only** | Helper trivial (struct holding `NebulaRegistry` — redundante) ou container (proibido). O **pattern** é o valor; o tipo não agrega nada que o app não escreve em 20 linhas no launch | Helper non-trivial derivaria para container; trivial é noise |
| **Protocol-witness alternative** aos markers | **Defer** | WWDC19 415 valida generic structs sobre protocols, mas markers Nebula são bare `Sendable` sem members required — rewrite witness duplica o seam sem ganho | Nenhuma; noise aditivo |
| **Per-scope override** (à la `withDependencies`/`.dependency()`) | **Defer** | Task-local scoping precisa single entry point; Nebula é library sem entry point → ergonomics colapsam para manual `withValue` (explicit injection com passos a mais) | Task-local `DependencyValues` é hidden global — mais perto de `nonisolated(unsafe)` que o accessor `Mutex<NebulaRegistryConfiguration>` |
| **`NebulaAppContainer` / launch-time graph builder** | **App-only** | App (ou Meridian) owns seu container; Nebula ship um seria re-skin do `NebulaRegistry` ou singleton-cache (proibido). `@main`/`App.init` é o lugar natural | Duplicaria `NebulaRegistry` ou violaria no-container |
| **Multi-module template product** (scaffolds Domain/UseCases/Adapters como targets separados) | **Defer** (já deferred em `clean-architecture-open-questions.md` Q10) | Fecha o risk "convention not compile-time" #2, mas template product é surface SPM pesada; o recipe doc pode recomendar o split multi-module sem shippar | Quebraria "single target" a menos que scoped como opt-in product |

## Recommended waves

- **N11 — Composition root recipe + DocC article + vault note.** `ArchitectureCompositionRoot.md` (linkado de `Architecture.md`) + esta vault note documentando: build `NebulaRegistryConfiguration` no launch, `NebulaRegistryConfig.set(…)` once, resolve concrete adapters, passe como explicit params para `NebulaUseCase<I,O>` bodies, hand use cases a `@MainActor @Observable` viewmodels via constructor injection, cruze o actor boundary via async `NebulaRouter` port pattern. Inclui guardrail "não extender `NebulaRegistry` para singleton/scoping" (risk #3) + caveat `@MainActor`-factory runtime-isolation (Factory #322). Deps: nenhum (docs-only).
- **N11b — Runnable `NebulaCompositionExample` em sibling.** Extender `MeridianExample` (ou novo `NebulaCompositionExample` sibling) demonstrando a **vertical completa**: `Account: NebulaEntity` + `AccountRepository` (backed por `NebulaFakeRepository`, swappable para real `NebulaHTTPGateway` + `NebulaURLCache`) + `NebulaUseCase<WithdrawInput, Account>` + `@MainActor @Observable ProfileViewModel: NebulaViewModel` + `Router<AppRoute>`. Compile gate (`swift run`) + test provando o wiring é unit-testable sem simulator. Deps: N11 (recipe), Meridian + Nebula surfaces. **Rationale sibling:** `@MainActor @Observable` viewmodel + SwiftUI `App` proibidos em Nebula; precedente `MeridianExample`/`AuroraExample`.

**Nenhuma wave extende `NebulaRegistry` ou ship um `NebulaCompositionRoot`/`NebulaAppContainer` type** — o `NebulaRegistry` existente (factories-only) + explicit-parameter constructor injection é a best practice documentada; o gap é documentação + runnable example, não novos tipos.

## UNVERIFIED
- "Embrace Swift types" como título de WWDC session — não localizado; o mais próximo verificado é **WWDC22 110352 "Embrace Swift generics"**. Citei só talks verificados.
- "Apple engineers endorse factory composition / explicit constructor injection" como *posição nomeada* Apple — Apple não tem guidance "composition root" publicado; o WWDC19 415 "explore concrete types first, prefer generic structs over protocols" é a corroboração oficial mais próxima, inferida (não declarada) para DI wiring. A stance composition-root-as-app-job é **consenso comunidade**, não posição Apple-publicada.

## Sources
- WWDC19 415 "Modern Swift API Design" — https://developer.apple.com/videos/play/wwdc2019/415/
- WWDC22 110352 "Embrace Swift generics" — https://developer.apple.com/videos/play/wwdc2022/110352/
- Point-Free — Protocol Witnesses Ep 33 — https://www.pointfree.co/collections/protocol-witnesses/alternatives-to-protocols/ep33-protocol-witnesses-part-1
- Point-Free Dependencies API — https://pointfreeco-swift-composable-architecture.mintlify.app/api/dependency
- TCA Dependencies guide — https://www.mintlify.com/pointfreeco/swift-composable-architecture/guides/dependencies
- hmlongco/Factory#322 (Swift 6 @MainActor isolation) — https://github.com/hmlongco/Factory/issues/322
- InnoSquadCorp/InnoDI — https://github.com/InnoSquadCorp/InnoDI
- rules-swift/concurrency.md — https://github.com/mihaelamj/rules-swift/blob/main/concurrency.md