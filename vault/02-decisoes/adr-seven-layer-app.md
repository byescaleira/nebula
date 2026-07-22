---
tags: [decisoes, adr, architecture, clean-architecture, hexagonal, app-structure, solid, nebula]
aliases: [ADR 7-layer app, ADR use case protocol repository, Nebula app architecture ADR, hexagonal flat app]
related: [[nebula-seven-layer-app-fit]], [[nebula-app-seven-layer-blueprint]], [[nebula-clean-architecture-toolkit]], [[nebula-presentation-architecture]], [[nebula-registry-di]]
status: accepted
date: "2026-07-22"
---

# ADR — App de 7 camadas sobre o ecossistema Nebula (use case = protocolo, repository = concreto)

## Context

O owner definiu um modelo de **app de 7 camadas** para implementar sobre o Nebula:

1. **Domain** — protocolos (definições) das regras.
2. **Infra** — abstrações para tudo que vem de fora (libs/frameworks).
3. **Data** — implementa as definições do Domain usando abstrações da Infra.
4. **Presentation** — routers + actions + states + viewModels (observável/compartilhável).
5. **UI** — views, screens, componentes.
6. **Main** — composition root; montar dependências e ambientes.
7. **Mock (opcional)** — dados mocados via JSON para preview.

Disciplina: o app importa `Main` onde tudo é construído e as dependências injetadas; cada módulo expõe apenas **factories** públicas e o resto é `internal` (SOLID + clean architecture).

A relação use case × repository foi esclarecida pelo owner: **o use case é uma definição (um protocolo) em Domain; em Data, o repository implementa o protocolo use case do Domain.**

## Decision

Adotar o modelo de 7 camadas como blueprint de implementação de apps sobre o ecossistema Nebula (Nebula + Meridian + Aurora + Cosmos). O Nebula **não** é uma das 7 camadas — é um toolkit Foundation-only **transversal**, importado por todas (como `Foundation`), que semeia as costuras de cada camada. A regra de dependência da Clean Architecture (UI → Presentation → Data → Domain, apontando para dentro) é **imposta por compilador** entre pacotes: `import Meridian`/`import Aurora`/`import Cosmos` de dentro do Nebula é erro de compilação duro.

**Relação use case × repository — hexagonal flat (decidido):**

- **Use case = protocolo (definição) em Domain**, marcado por `NebulaInputPort` (o marker exato do Nebula para "use-case input port — the seam an outer adapter calls to invoke an application rule").
- **Repository = concreto em Data que `implements` o protocolo use case**, usando os gateways da Infra internamente. É o pattern ports & adapters: o port (use case) vive em Domain, o adapter (repository) vive em Data.

**Implicações para a superfície do Nebula:**

1. `NebulaInputPort` — **usado** como marker base dos protocolos de use case. Sem mudança no Nebula.
2. `NebulaUseCase<I,O>` (struct orquestrador + decoradores `.logged/.measured/.reported/.instrumented`) — **opt-in não usado** neste modelo (o use case é um protocolo, não um struct; o concreto é o repository). Fica disponível para apps que queiram o orquestrador genérico com a cadeia de decoradores. Sem conflito — ferramenta fornecida, não exigida.
3. `NebulaRepository` (+ReadOnly/Keyed/Writable/Deletable) — **port genérico de CRUD, situacional, não exigido**. Distinto do "repository" do owner (que é o concreto). O concreto do owner **pode opcionalmente também conforms** a `NebulaKeyedRepository<User>` etc. para features CRUD-ish (uniformiza o shape); para features de ação (`login`) só o protocolo de use case.

**Visibilidade (SOLID):** aplica-se aos **módulos do app** — protocolos + factories públicos, implementações concretas `internal`. Detalhe Swift: protocolos precisam ser `public` para conformança cross-módulo, então "factory-only público" = protocolos + factories públicos, impls `internal`. O Nebula em si **não** segue essa disciplina (biblioteca reutilizável = API pública ampla).

## Consequences

- **Nebula fica inalterado** — nenhuma mudança de código; o modelo é suportado nativamente via `NebulaInputPort` + os ports/gateways/registry existentes. A análise confirmou mapeamento 1:1 camada-a-camada.
- **O app define seus próprios módulos SwiftPM** (Domain/Infra/Data/Presentation/UI/Main/Mock), cada um importando Nebula (+ Meridian/Aurora/Cosmos conforme a camada). A regra de dependência é enforced por quem importa quem.
- **`NebulaUseCase<I,O>` torna-se opt-in não usado** neste app — abre-se mão do orquestrador puro testável com `NebulaFakeRepository` e da cadeia `.instrumented()`. Em troca, menos camadas (hexagonal flat) e o repository é o adapter direto do port.
- **Test doubles**: como o use case é um protocolo feature-specific, `NebulaStubUseCase`/`NebulaSpyUseCase` (genéricos sobre `<I,O>` no shape do struct) **não se aplicam diretamente** — o app escreve pequenos fakes feature-specific conformes a cada protocolo. `NebulaFakeRepository` (genérico, `NebulaKeyedRepository`/`Writable`/`Deletable`) continua valendo para repositories que adotam a capacidade CRUD. `NebulaSpyRouter` continua valendo para routers.
- **Mock de preview já coberto**: os fakes do Nebula são `public` no product target → importáveis em `#Preview`.
- **Main = composition root** que o Nebula já documenta (`ArchitectureCompositionRoot.md`) e **não** shippa um container (guardrail: `NebulaRegistry` é mapa de factories, não container) — alinha com a disciplina SOLID do owner.
- **Trade-off registrado**: hexagonal flat (regra de negócio + acesso a dados juntos no repository concreto) vs. canônico Uncle Bob (use case orquestrador puro chamando um port de repository separado). O owner escolheu flat; testar = testar o repository com um fake da Infra (ex: `NebulaHTTPClient` fake / `URLProtocol`).

## Status

**Accepted** (2026-07-22). Blueprint de implementação em [[nebula-app-seven-layer-blueprint]]; análise de enquadramento em [[nebula-seven-layer-app-fit]]. Nenhuma mudança no Nebula; este ADR governa a estrutura dos **apps** que consomem o ecossistema, não a biblioteca Nebula em si.