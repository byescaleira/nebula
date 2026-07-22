---
tags: [padroes, architecture, clean-architecture, hexagonal, app-structure, solid, nebula]
aliases: [Nebula 7-layer fit, Nebula app architecture fit, Domain Infra Data Presentation UI Main Mock]
related: [[nebula-clean-architecture-toolkit]], [[nebula-presentation-architecture]], [[nebula-registry-di]], [[nebula-usecase]], [[nebula-repository]], [[nebula-composition-root]], [[nebula-presentation-target-split]]
status: decided
researched: "2026-07-22"
decided: "2026-07-22"
---

# Nebula x modelo de app de 7 camadas — análise de enquadramento

Análise de se o Nebula (e Meridian/Aurora/Cosmos) se enquadra no modelo de **app de 7 camadas** proposto pelo owner:

1. **Domain** — protocolos (definições) das regras.
2. **Infra** — abstrações para tudo que vem de fora (libs/frameworks): network, HealthKit, GameCenter, StoreKit, etc.
3. **Data** — implementa as definições de entidade, use cases etc. do Domain usando abstrações da Infra (obs do owner: "use cases viram repository").
4. **Presentation** — uso do Data + arquitetura de apresentação observável/compartilhável: routers + actions + states + viewModels.
5. **UI** — views, screens, componentes, toolbar items, tab accessories.
6. **Main** — montar todas as dependências para acesso global; montar ambientes.
7. **Mock (opcional)** — dados mocados via JSON para preview.

Disciplina: o app importa `Main` (onde tudo é construído e as dependências injetadas); cada módulo expõe apenas suas **factories** públicas e o resto é `internal` (SOLID + clean architecture).

## Veredito

**O modelo é sólido e se enquadra no Nebula** — é a decomposição clássica Clean/Hexagonal de um app (Domain/Data/Interface Adapters/Composition Root), e o Nebula já é desenhado exatamente para semeá-lo. **Um ponto de divergência real precisa de decisão do owner** (use case × repository — ver §"A divergência"). Os demais 6 pontos mapeiam 1:1.

O enquadramento-chave é: **o Nebula NÃO é uma das 7 camadas** — ele é um toolkit Foundation-only **transversal**, importado por todas as camadas (como `Foundation`/`SwiftStdlib`), que fornece as *costuras* (ports/markers/modelos/configs/registry/test doubles) sobre as quais cada camada do app é construída. O Nebula não contém lógica de domínio de app nenhum, então a regra de dependência (UI → Presentation → Data → Domain, apontando para dentro) é preservada — o Nebula senta **ortogonal** ao vetor de dependência, como infraestrutura genérica reutilizável.

## Mapeamento camada-a-camada (o que o Nebula semeia em cada uma)

| Camada do app | Constrói sobre (Nebula) | Dono do app |
|---|---|---|
| **1 Domain** | `NebulaValue`/`NebulaEntity`/`NebulaAggregate`/`NebulaID` (markers), `NebulaInputPort`/`NebulaOutputPort`/`NebulaDTO` (markers), `NebulaRepository` + capacidade (ReadOnly/Keyed/Writable/Deletable), `NebulaFailure`/`NebulaDomainError`/`NebulaValidationError`, `NebulaValidator`/`NebulaAsyncValidator` | O app define seus `Entity`/`Value`/`Aggregate` structs, seus protocolos de use case (`: NebulaInputPort`) e de repository (`: NebulaRepository`), e seus erros de domínio (`: NebulaFailure`). Tudo `internal`-concreto / `public`-protocolo. |
| **2 Infra** | `NebulaGateway` (marker) + gateways concretos: `NebulaHTTPClient`/`NebulaHTTPGateway` (URLSession), `NebulaSecureStore`/`NebulaKeychain` (Security), `NebulaCloudKitSync`/`NebulaCloudKitSyncEngine` (CloudKit), `NebulaBackgroundTaskScheduler`/`NebulaBGTaskScheduler`, `NebulaNotificationCenter`/`NebulaUNNotificationCenter`, `NebulaFeatureFlags`/`NebulaLocalFeatureFlags`, `NebulaPreferences`/`NebulaDefaults`, `NebulaHTTPServer`, pinning/SSE/WebSocket/download/multipart. | O app implementa ports para libs que o Nebula **não** cobre (HealthKit, GameCenter, StoreKit — este último é Wave N18 deferido) atrás de seus próprios ports; para libs cobertas, o app reaproveita o gateway do Nebula ou constrói o seu próprio atrás do port Nebula. A camada Infra do app pode ficar **magra** (só wiring) onde reusa gateways Nebula. |
| **3 Data** | `NebulaUseCase<I,O>` (struct que envolve o body `@Sendable`, com `.logged`/`.measured`/`.reported`/`.instrumented`), `NebulaRepository` impls sobre gateways da Infra, `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase` (**no product target** → importável), `NebulaDTO`, mappers. Aurora (sibling) = adapter SwiftData (`AuroraRepository<Mapping>` `@ModelActor` conformando os 4 ports de repository). | O app implementa seus repositories (conformam `NebulaRepository`) chamando a Infra, e seus use cases (`NebulaUseCase<I,O>` bodies que chamam repositories). DTOs/mappers. |
| **4 Presentation** | `NebulaRouter`/`NebulaPresentationRouter`/`NebulaPresentation`/`NebulaRoute`/`NebulaNavigationStack`/`NebulaViewModel` (Nebula, Foundation-only) + `Router` `@Observable`/`MeridianNavigationStack`/`MeridianNavigationSplitView`/`MeridianTabView` (Meridian). | O app define viewModels (`: NebulaViewModel` + `@MainActor @Observable`), routers (Meridian `Router<Route>`), actions e states (donos do app — o Nebula não impõe um modelo de action/state além do que o viewModel segura). |
| **5 UI** | **Nebula fica de fora** (binding: zero SwiftUI/UIKit no Nebula). Meridian (containers) + Cosmos (design system) são os lares SwiftUI. | O app constrói views/screens/componentes sobre Cosmos + Meridian, importando a Presentation do app. |
| **6 Main** | `NebulaRegistry` (DI como **mapa de factories**, não container) + `NebulaRegistryConfiguration`/`NebulaRegistryConfig` + as 7 config structs (`Log`/`Error`/`Measure`/`Standards`/`Environment`/`Notifications`/`BackgroundTasks` + Metrics/Analytics/CloudKit) com accessores `Mutex` process-wide + `NebulaEnvironment` + `NebulaStandards`. O artigo DocC `ArchitectureCompositionRoot.md` (Wave N11) nomeia explicitamente o composition root como **trabalho do app** em `@main`/`App.init`. | O app monta o grafo em `@main`: `.withFactory(for:_:)`, `NebulaRegistryConfig.set(…)`, resolve adapters, injeta como parâmetro explícito nos use cases, decora com `.instrumented()`, entrega aos viewModels. Monta ambientes via `NebulaEnvironment`/`NebulaEnvironmentConfig`. |
| **7 Mock (opcional)** | `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase`/`NebulaSpyRouter` — **todos `public` no product target** (`Sources/Nebula/Architecture/Testing/`), então importáveis para previews, não só testes. | O app adiciona fixtures JSON + mocks específicos do domínio por cima dos fakes Nebula. |

## Por que "o Nebula é importado por todas as camadas" NÃO viola clean architecture

A objeção natural: clean architecture diz "dependências apontam para dentro" (UI → Presentation → Data → Domain); se todas as camadas importam `Nebula`, não vira uma dependência lateral? **Não**, porque:

- A regra de dependência é sobre as **camadas de domínio do app**. O Nebula **não contém lógica de domínio de nenhum app** — é infraestrutura genérica (ports, value markers, configs, registry), análoga a `Foundation`/`Synchronization`. Ninguém chama `import Foundation` de violação de clean arch.
- Cada costura Nebula é um **port/marker** (abstração). Domain depende de `NebulaEntity`/`NebulaRepository` (abstrações), não de adapters concretos. Data implementa `NebulaRepository` sobre a Infra. A direção seta-se pelas abstrações: o Nebula fornece a abstração; o app decide a direção do concreto.
- Os gateways concretos do Nebula (`NebulaHTTPGateway`, `NebulaKeychain`, `NebulaCloudKitSyncEngine`) ficam **atrás de ports**; Domain/Data só veem o port. O gateway só é instanciado no Main (composition root). Portanto a direção de dependência do concreto aponta para dentro (Main → Infra → port), e Domain continua sem conhecer transporte.

## A relação use case × repository — DECIDIDO (2026-07-22)

O owner esclareceu o modelo: **o use case é uma definição (um protocolo) que fica em Domain; em Data, o repository implementa o protocolo use case do Domain.** Ou seja, o use case = port (contrato da feature) em Domain; o repository = concreto em Data que conforms a esse port, usando os gateways da Infra internamente. É o pattern ports & adapters (hexagonal): o port (use case) vive em Domain, o adapter (repository) vive em Data.

**Isso encaixa no Nebula com ZERO mudança** — o Nebula já shippa o marker exato para isso:

- **`NebulaInputPort`** (`Architecture/Ports/`) — marker `Sendable` para um **use-case input port** ("the seam an outer adapter calls to invoke an application rule", ver `Architecture.md` + Explore map). O use case como protocolo em Domain = `protocol FooUseCase: NebulaInputPort { func login(_:) async throws -> Session }`. **Este é o marker que o owner usa.** ✓
- **`NebulaOutputPort`** — marker para o output port (o seam que o use case chama para emitir resultados — estilo presenter/callback). Opcional no modelo do owner (a viewmodel `@Observable` costuma ser o destino direto); fica disponível se uma feature quiser o estilo callback.
- O **repository concreto em Data** (`final class FooRepository: FooUseCase { /* usa NebulaHTTPClient, etc. */ }`) é **código do app** — o Nebula não impõe nada sobre o concreto. ✓

### O que isso significa para a superfície do Nebula

1. **`NebulaInputPort`** — o marker do protocolo de use case. **Usa.** Sem mudança.
2. **`NebulaUseCase<I,O>`** (o struct orquestrador + decoradores `.logged/.measured/.reported/.instrumented`) — torna-se um **opt-in que o modelo do owner NÃO usa**. No modelo do owner o use case é um *protocolo*, não um struct; o concreto é o repository. `NebulaUseCase<I,O>` fica disponível para apps que queiram o orquestrador genérico com a cadeia de decoradores, mas não é o caminho do owner. **Sem conflito** — é uma ferramenta fornecida, não exigida.
3. **`NebulaRepository` (+ReadOnly/Keyed/Writable/Deletable)** — é um **port genérico de capacidade de acesso a dados**, **distinto** do "repository" do owner. Importante desambiguar a sobreposição de nomes:
   - "repository" do owner = o **concreto** em Data que implementa o protocolo de use case (ex: `FooRepository: FooUseCase`).
   - `NebulaRepository` do Nebula = um **port (protocolo)** genérico de CRUD (`Element`-tipado, `stream`/`count`/`find(id:)`/`save`/`delete`).
   - São papéis diferentes com o mesmo nome. O concreto do owner **pode opcionalmente também conforms** a `NebulaKeyedRepository<User>` etc. quando a feature é CRUD-ish (uniformiza o shape de dados); para features de ação (ex: `LoginUseCase.login`) não há shape CRUD — só o protocolo de use case. `NebulaRepository` é **situacional, não exigido**.

### Trade-off registrado (vs. canônico Uncle Bob)

- **Modelo do owner (decidido):** use case = protocolo em Domain; repository = concreto em Data que o implementa, com a regra de negócio + acesso a dados juntos. Menos camadas, hexagonal. Testar = testar o repository com um fake da Infra (ex: `NebulaHTTPClient` fake / `URLProtocol`).
- **Canônico (`NebulaUseCase<I,O>` chamando um port de repository separado):** use case = orquestrador puro, função de (input, repository-port); testar com `NebulaFakeRepository`. Mais indireção, mais isolado, mas mais camadas e perde-se a cadeia `.instrumented()`.

O owner escolheu o modelo hexagonal flat. O Nebula o suporta nativamente via `NebulaInputPort`. `NebulaUseCase<I,O>` fica como opt-in não usado neste app.

### Nota sobre test doubles no modelo do owner

Como o use case é um **protocolo feature-specific** (não o struct genérico `NebulaUseCase<I,O>`), os doubles `NebulaStubUseCase`/`NebulaSpyUseCase` (genéricos sobre `<I,O>` no shape do struct) **não se aplicam diretamente** — o app escreve pequenos fakes feature-specific conformes a cada protocolo de use case (trivial). `NebulaFakeRepository` (genérico, conforms a `NebulaKeyedRepository`/`Writable`/`Deletable`) **continua valendo** para qualquer repository do owner que também adote a capacidade CRUD.

## Pontos secundários a confirmar

- **"Factories públicas, resto interno"**: aplica-se aos **módulos do app**, não ao Nebula. O Nebula é uma biblioteca reutilizável — precisa de uma superfície pública ampla (ports/markers/models/configs) para que os apps conformem. Mas há um detalhe Swift: para o módulo Domain expor um protocolo que o módulo Data conforma, o protocolo **precisa ser `public`** em Domain. Então "factory-only público" na prática significa **protocolos + factories públicos, implementações concretas `internal`** — que é a interpretação padrão e compatível. O Nebula em si não vira factory-only (continua com API pública ampla); os módulos do app sim.
- **Mock para preview**: os fakes do Nebula já são `public` no product target → importáveis em previews. O Mock do app adiciona JSON fixtures. Sem gap.
- **Main como composition root**: o Nebula já documenta isso (`ArchitectureCompositionRoot.md`, Wave N11) e **não** shippa um `NebulaAppContainer`/`NebulaCompositionRoot` (deliberadamente — "trivial = redundante; não-trivial = deriva para container"). Então o "Main" do app é exatamente o composition root que o Nebula espera que o app monte. Match perfeito. Guardrail do Nebula: "não estender o `NebulaRegistry` para singleton/scoping/auto-injection — é um mapa de factories, não container" — alinha com a disciplina SOLID do owner.
- **Siblings mapeiam**: Meridian (SwiftUI) = Presentation/UI; Aurora (SwiftData) = Data (persistência); Cosmos (design system) = UI. O Nebula é o tronco Foundation-only comum. O split é o que torna a regra de dependência **compilador-imposta** entre pacotes (`import Meridian`/`import Aurora` de dentro do Nebula = erro de compilação duro).

## Conclusão

O modelo de 7 camadas faz sentido, é aderente a Clean/Hexagonal e o Nebula já é a biblioteca que o semeia. Não há reescrever o Nebula. A relação use case × repository foi decidida (2026-07-22): use case = protocolo em Domain marcado por `NebulaInputPort`; repository = concreto em Data que o implementa usando a Infra (hexagonal flat). `NebulaUseCase<I,O>` fica como opt-in não usado neste app; `NebulaRepository` é um port genérico de CRUD situacional. Tudo o mais é mapeamento direto + disciplina de visibilidade (protocolos + factories públicos, impls `internal`) nos módulos do app. Ver [[nebula-clean-architecture-toolkit]] para o toolkit completo e [[nebula-composition-root]] para o composition root.