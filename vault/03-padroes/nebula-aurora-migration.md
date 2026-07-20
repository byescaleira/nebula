---
tags: [nebula, aurora, swiftdata, architecture, migration, swift]
aliases: [nebula aurora migration, AuroraModelContainer, VersionedSchema, SchemaMigrationPlan, MigrationStage, nebula schema migration]
related: [[nebula-app-readiness-research]], [[nebula-aurora-swiftdata]]
status: researched
researched: "2026-07-19"
---

# Aurora — SwiftData schema migration

> Research depth for the SwiftData-migration dimension of [[nebula-app-readiness-research]]. Lives in the **Aurora** sibling package (SwiftData), NOT Nebula (Foundation-only). Verified against `SwiftData.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27 Beta 3). UNVERIFIED items flagged inline.

## Apple-native APIs + best-practice pattern

Verified contra o `.swiftinterface` (line numbers from that file):
- **`protocol VersionedSchema : SendableMetatype`** (L833–837): `static var models: [any PersistentModel.Type]` + `static var versionIdentifier: Schema.Version`. Convenção: `enum SchemaV1` com `@Model` types aninhados. WWDC23 "Model your schema with SwiftData" (10195).
- **`protocol SchemaMigrationPlan : SendableMetatype`** (L839–842): `static var schemas: [any VersionedSchema.Type]` + `static var stages: [MigrationStage]`. Declare `enum AppMigrationPlan` listando versões + stages ordenados.
- **`enum MigrationStage : Sendable`** (L827–831):
  - `.lightweight(fromVersion:toVersion:)` — SwiftData infere o diff (add optional/defaulted, remove, rename via `@Attribute(originalName:)`, cardinalidade/delete-rule, novas entidades).
  - `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` — `@preconcurrency`; ambos closures `@Sendable (ModelContext) throws -> Void` (L829). `willMigrate` vê o contexto do schema **velho**; `didMigrate` vê o **novo**. Ambos devem `context.save()` se mutarem.
- **`final class Schema : Codable, Hashable`** (L845) — **NÃO declarado Sendable**. `init(versionedSchema:)` (L856); `init(_:version:)` (L854). `Schema.Version` struct `Codable+Comparable+Hashable` `init(_ major:_ minor:_ patch:)` (L869) — derived Sendable.
- **`class ModelContainer : Equatable, @unchecked Sendable`** (L165): `let migrationPlan: (any SchemaMigrationPlan.Type)?` (L167). Factories: `init(for:_:, migrationPlan:, configurations:)` variadic (L176); `init(for: Schema, migrationPlan:, configurations:)` (L177); designated `init(for: Schema, migrationPlan:, configurations: [ModelConfiguration])` (L178).
- **`struct ModelConfiguration : Sendable`** (L13, L76): `init(_:schema:isStoredInMemoryOnly:allowsSave:groupContainer:cloudKitDatabase:)` (L47), `init(_:url:allowsSave:cloudKitDatabase:)` (L48). `GroupContainer`/`CloudKitDatabase` Sendable (L79/L82).
- **`@ModelActor` macro** (L574) → gera `actor` conformando `ModelActor : Actor` (L120) com `nonisolated var modelContainer`/`modelExecutor`. Veículo de concorrência da Aurora.
- **`class ModelContext`** — `extension ModelContext : @unchecked Sendable` (L567); cruza o boundary `@Sendable` via `@preconcurrency`.

**Best-practice pattern** (WWDC23 10189 + 10195; WWDC24 10137 adiciona `#Unique`/`#Index`/history mas **nenhuma mudança na machinery de migration**):
1. Snapshot do schema shipping atual como `SchemaV1: VersionedSchema` (`versionIdentifier: Version(1,0,0)`).
2. Para cada release que muda models, adicione `SchemaV2`, `SchemaV3`, … e append um `MigrationStage`. Usuários podem pular versões — SwiftData caminha stages do on-disk version em diante.
3. **Prefira `.lightweight`** para tudo que SwiftData infere. Ship `VersionedSchema` só para mudanças inter-release — não versione cada dev iteration (causa crash "Duplicate version checksums across stages detected" se os models estão efetivamente unchanged).
4. `.custom` para non-optional-without-default additions, type changes, splits/merges, dedup. Para reshaping que precisa de old+new values, use **bridge version**: keep legacy fields sob `@Attribute(originalName:)` em V2, popule em `didMigrate`, drop em V3 (lightweight).
5. Round-trip test contra um V1 store real; verifique o app velho ainda lança pós-migration; teste o throw path.
6. Coexistência Core Data (WWDC23 10189): persistent history tracking, namespace class names, mantenha schemas em sync.

## Sendability & availability

| API | Sendable? | Floor | Gate em Aurora (.v26)? |
|---|---|---|---|
| `MigrationStage` (enum) | **Sim** (`: Sendable`, L827) | macOS 14/iOS 17/tvOS 17/watchOS 10/visionOS 1+ | Não — abaixo floor |
| `VersionedSchema`/`SchemaMigrationPlan` (protocols) | Metatype only (`: SendableMetatype`) | mesmo | Não |
| `Schema` (class) | **NÃO** (L845; `final class : Codable, Hashable`) | mesmo | Não (trate como non-Sendable) |
| `Schema.Version` (struct) | **Sim** (L869) | mesmo | Não |
| `ModelContainer` (class) | `@unchecked Sendable` (L165) | mesmo | Não |
| `ModelConfiguration` (struct) | **Sim** (L76) | mesmo | Não |
| `ModelContext` (class) | `@unchecked Sendable` (L567) | mesmo | Não |
| `@ModelActor`/`ModelActor` | Actor-isolated → Sendable por ser `actor` | mesmo | Não |

## Aurora-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| `AuroraSchemaVersion` (wrapper sobre `Schema.Version`) | **Defer** | `Schema.Version` já é Sendable/Codable/Comparable — wrapping não agrega | Nenhuma |
| `AuroraMigrationPlan` builder DSL | **Defer** | `SchemaMigrationPlan` é metatype-only com 2 `static var` — um `enum AppMigrationPlan` por app é o idiom Apple; builder genérico só re-exportaria `static let stages` | App owns o plan (seus `@Model` types); Aurora não pode enumerar sem re-importar → circular |
| `AuroraModelContainer` factory (config-time `ModelContainer(for:migrationPlan:configurations:)`) | **Ship in Aurora** | Aurora já deferra o container factory; este é o seam onde `SchemaMigrationPlan.Type?` é injetado | Factory é `@Sendable` function free (container init é sync, throws); `ModelContainer` `@unchecked Sendable` handado ao `@ModelActor` `AuroraRepository`. Sem conflito de isolamento |
| `AuroraMigrationStage` convenience constructors | **Defer** | `MigrationStage` já é Sendable + API mínima; re-wrap apaga o signal `@preconcurrency` que Apple deliberadamente anexou a `.custom` | Re-wrap de `.custom`'s `@Sendable (ModelContext) -> Void` precisaria forward `ModelContext` — ok, mas `@preconcurrency` é load-bearing |
| `@ModelActor`-isolated custom-migration runner | **Ship in Aurora** | `.custom` closures recebem `ModelContext` bare (não actor-isolated); Aurora deve oferecer helper que roda as closures num `@ModelActor` executor para serializar via isolamento Aurora | **Tensão real**: closures Apple são `@Sendable` + `@preconcurrency` porque `ModelContext` é `@unchecked Sendable` (não data-race-safe). Rodar via `@ModelActor` serializa e restaura a garantia |
| AuroraExample: V1→V2→V3 evolution | **Ship in Aurora** | Único jeito de tornar o factory + plan legível; match o padrão DocC examples | Example não pode `import Nebula` de Aurora (hard error) — vive em `AuroraExample` |
| `@Query` helper | **Defer** | `@Query` é SwiftUI-coupled (`_SwiftData_SwiftUI`); Aurora é Foundation+SwiftData sem SwiftUI | Hard rule: sem SwiftUI em Aurora |
| Relationship-walking helper | **Defer** | `@Relationship` metadata + `ModelContext` fetch já cobrem | Nenhuma |

## Recommended waves (Aurora, não Nebula)

- **A1 — Aurora `ModelContainer` factory + migration-plan injection.** `@Sendable` `AuroraContainer.make(for:migrationPlan:configurations:)` (ou `AuroraModelContainerFactory`) wrapping `ModelContainer(for:migrationPlan:configurations:)` (L176–178), retornando o `@unchecked Sendable` `ModelContainer`. Sem conflito de isolamento (factory é free function). Deps: nenhum (unblocker).
- **A2 — `@ModelActor`-isolated custom-migration runner.** Helper que pega `MigrationStage.custom` e roda `willMigrate`/`didMigrate` num `@ModelActor` `DefaultSerialModelExecutor` (L143–152) para serializar o `ModelContext` bare via isolamento Aurora. Deps: A1.
- **A3 — AuroraExample: V1→V2 (lightweight) →V3 (custom + bridge).** Runnable example target mostrando `VersionedSchema` snapshots, `SchemaMigrationPlan` enum, `.lightweight` + `.custom` + bridge-version pattern. Deps: A1, A2.
- **(Defer) A4** — `@Query` helper, relationship-walking, `AuroraSchemaVersion`/`AuroraMigrationPlan`/`AuroraMigrationStage` wrappers.

## UNVERIFIED (não citar como fato)
- **`Migration` protocol com `perform(on:container:)` NÃO EXISTE** no `.swiftinterface` (grep `protocol Migration` / `perform(on:` → nada). Custom migration é exclusivamente `MigrationStage.custom` closures.
- **`LightweightMigration` protocol NÃO EXISTE** — lightweight = `.lightweight` enum case + inferência automática; sem protocol para conformar.
- **`Schema` Sendability**: `final class : Codable, Hashable` sem `Sendable` (L845) — trate como non-Sendable; construa dentro do container-init call site / actor. Se um SDK futuro marcar Sendable, relaxa.
- visionOS: a `.swiftinterface` iOS `@available` omite visionOS (só `macOS 14, iOS 17, tvOS 17, watchOS 10, *`); a visionOS `.swiftinterface` carrega a mesma linha → `*` fallback habilita visionOS 1.0+. Acima do floor .v26 → sem gate.

## Sources
- WWDC23 10189 "Migrate to SwiftData" — https://developer.apple.com/videos/play/wwdc2023/10189/
- WWDC23 10195 "Model your schema with SwiftData" — https://developer.apple.com/videos/play/wwdc2023/10195/
- WWDC24 10137 "What's new in SwiftData" — https://developer.apple.com/videos/play/wwdc2024/10137/
- Donny Wals — "A Deep Dive into SwiftData migrations" — https://www.donnywals.com/a-deep-dive-into-swiftdata-migrations/
- Hacking with Swift — "How to create a complex migration using VersionedSchema" — https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-complex-migration-using-versionedschema