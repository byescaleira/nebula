---
tags: [metodologia, architecture, clean-architecture, hexagonal, app-structure, solid, swift-package-manager, nebula, meridian, aurora, cosmos]
aliases: [Nebula app blueprint, 7-layer app blueprint, Nebula implementation guide, Domain Infra Data Presentation UI Main Mock, como estruturar um app com Nebula]
related: [[nebula-seven-layer-app-fit]], [[nebula-clean-architecture-toolkit]], [[nebula-presentation-architecture]], [[nebula-registry-di]], [[nebula-usecase]], [[nebula-repository]], [[nebula-composition-root]], [[nebula-presentation-target-split]], [[nebula-clean-architecture-tdd]]
status: reference
created: "2026-07-22"
---

# Blueprint de implementação de app — 7 camadas com Nebula

Documento de **referência** para implementar um app sobre o ecossistema Nebula seguindo o modelo de **7 camadas** do owner. Use como guia quando for montar um app: cada camada mapeia para tipos concretos do Nebula (e siblings Meridian/Aurora/Cosmos), com exemplos de código em Swift 6, disciplina de visibilidade (SOLID) e estratégia de teste.

> Fonte da verdade: root docs (`ARCHITECTURE.md`/`CLAUDE.md`/`VERSIONING.md`) + código em `Sources/`. Este documento é síntese. Em conflito, o root doc/código vence. Análise de enquadramento em [[nebula-seven-layer-app-fit]]; decisão registrada em [[adr-seven-layer-app]].

## Os 4 pacotes do ecossistema (load-bearing)

| Pacote | Papel | Importa SwiftUI? | Importado pelas camadas |
|---|---|---|---|
| **Nebula** | Toolkit Foundation-only transversal: ports, markers, value models, configs, registry, test doubles, navegação-como-dado | **Não** (binding) | Todas as 7 (como `Foundation`) |
| **Meridian** | Adapter SwiftUI de apresentação: `@Observable Router` + trio de containers (`NavigationStack`/`NavigationSplitView`/`TabView`) | Sim | Presentation, UI |
| **Aurora** | Adapter SwiftData de persistência: `AuroraRepository<Mapping>` `@ModelActor` conformando os ports `NebulaRepository` | Não (SwiftData) | Data (persistência local) |
| **Cosmos** | Design system SwiftUI (Atoms/Molecules/Organisms/Modifiers/Screen + tokens) | Sim | UI |

O Nebula é o **tronco comum** importado por todas as camadas — como `Foundation`, não como uma das 7. A regra de dependência da Clean Architecture (UI → Presentation → Data → Domain, apontando para dentro) é **imposta por compilador** entre pacotes: `import Meridian`/`import Aurora`/`import Cosmos` de dentro do Nebula é um erro de compilação duro (cada sibling depende de Nebula via `path: "../"`, nunca o contrário).

## As 7 camadas — visão geral

```
        ┌─────────────────────────────────────────────────────┐
        │  7. Mock (opcional)  — JSON fixtures + fakes p/ preview │
        ├─────────────────────────────────────────────────────┤
        │  6. Main              — composition root, ambientes, wiring │
        ├─────────────────────────────────────────────────────┤
        │  5. UI                — views/screens/componentes (Cosmos + Meridian) │
        ├─────────────────────────────────────────────────────┤
        │  4. Presentation      — routers + actions + states + viewModels (Meridian) │
        ├─────────────────────────────────────────────────────┤
        │  3. Data              — repositories (implementam o protocolo use case) + DTOs │
        ├─────────────────────────────────────────────────────┤
        │  2. Infra             — abstrações para libs externas (network, keychain, cloudkit, …) │
        ├─────────────────────────────────────────────────────┤
        │  1. Domain            — protocolos (definições): entidades, use cases, erros │
        └─────────────────────────────────────────────────────┘
                                 ▲
                                 │  import Nebula (transversal, todas as camadas)
                                 │  import Meridian (Presentation/UI), Aurora (Data), Cosmos (UI)
```

**Direção de dependência** (Clean Architecture): as setas do **concreto do app** apontam para dentro — UI → Presentation → Data → Domain; Infra → Data (via ports); Main → todas (composition root monta o grafo). O Nebula é ortogonal (infraestrutura genérica, sem lógica de domínio), então importá-lo em todas as camadas **não** é violação.

**Regra de visibilidade (SOLID)**: cada módulo do app expõe **protocolos + factories públicos**; implementações concretas são `internal`. (Detalhe Swift: para o módulo Data conformar um protocolo do módulo Domain, o protocolo precisa ser `public` em Domain — então "factory-only público" significa na prática **protocolos + factories públicos, impls `internal`**.) O Nebula em si **não** segue essa disciplina — é uma biblioteca reutilizável e precisa de API pública ampla (ports/markers/models/configs) para que os apps conformem. A disciplina aplica-se aos **módulos do app**, não ao Nebula.

---

## Camada 1 — Domain

**Responsabilidade**: as **definições** (protocolos) das regras de negócio. Entidades, use cases (protocolos), erros de domínio. **Sem I/O, sem framework, sem SwiftUI.** Depende apenas de Nebula.

### O que o Nebula semeia

- `NebulaValue`/`NebulaEntity`/`NebulaAggregate` — markers para value types / entidades / aggregate roots.
- `NebulaID<Entity>` — identidade phantom-tipada (UUID-backed) que distingue `NebulaID<Account>` de `NebulaID<Order>` no tipo.
- `NebulaInputPort` — **marker para um use-case input port** ("the seam an outer adapter calls to invoke an application rule"). É o marker base dos seus protocolos de use case.
- `NebulaOutputPort` — marker para output port (estilo presenter/callback). Opcional quando a viewmodel `@Observable` é o destino direto.
- `NebulaDTO` — marker para Data Transfer Objects (estruturas de dados puras que cruzam fronteiras).
- `NebulaFailure`/`NebulaDomainError`/`NebulaValidationError` — erros por camada (open structs que bridgeiam para o `NebulaError.Kind` fechado via `toNebulaError(kind:)`).
- `NebulaValidator<T>`/`NebulaAsyncValidator<T>` — validadores (regras de domínio / validação de input).

### O que o app constrói (exemplo)

```swift
// Domain/Sources/Domain/Account/Account.swift
import Nebula

public struct Account: NebulaAggregate {
    public let id: NebulaID<Account>
    public var email: String
    public var displayName: String
    public init(id: NebulaID<Account>, email: String, displayName: String) {
        self.id = id; self.email = email; self.displayName = displayName
    }
}

public struct Credentials: NebulaDTO {
    public let email: String
    public let password: String
    public init(email: String, password: String) { self.email = email; self.password = password }
}

// O use case É UM PROTOCOLo (definição) — decisão do owner (hexagonal flat).
// O repository em Data vai implements este port.
public protocol LoginUseCase: NebulaInputPort {
    func login(_ credentials: Credentials) async throws -> Account
}

public protocol SessionUseCase: NebulaInputPort {
    func currentAccount() async throws -> Account?
    func logout() async
}

// Erro de domínio (open struct → bridgeia para NebulaError.Kind fechado).
public struct AccountDomainError: NebulaFailure, Equatable, Hashable {
    public enum Code: Sendable { case invalidCredentials, accountSuspended, notFound }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        NebulaError(code: "Account.\(code)", kind: kind, message: "Account domain error: \(code)")
    }
}
```

**Visibilidade**: `Account`/`Credentials`/`LoginUseCase`/`SessionUseCase`/`AccountDomainError` são `public` (precisam ser visíveis em Data/Presentation). Regras de validação específicas ficam `internal` quando só Domain usa.

### Nota: use case = protocolo, não o struct `NebulaUseCase<I,O>`

O Nebula **também** shippa `NebulaUseCase<I,O>` — um struct genérico que envolve um body `@Sendable (I) async throws -> O` com decoradores `.logged/.measured/.reported/.instrumented`. **No modelo do owner, o use case é um protocolo** (acima), e o concreto é o repository em Data. Portanto `NebulaUseCase<I,O>` **não é usado** neste app — fica como opt-in para apps que queiram o orquestrador genérico com a cadeia de decoradores. Ver [[adr-seven-layer-app]].

---

## Camada 2 — Infra

**Responsabilidade**: **abstrações para tudo que vem de fora** — wrappers sobre libs/frameworks externos: network, keychain, CloudKit, notificações, background tasks, StoreKit (N18), HealthKit, GameCenter. Expõe ports; os gateways concretos ficam atrás dos ports (a instância só é montada em Main).

### O que o Nebula já shippa (reaproveite)

- **Network**: `NebulaHTTPClient` (port) + `NebulaHTTPGateway` (concreto sobre URLSession), `NebulaHTTPEndpoint`/`NebulaHTTPRequest`/`NebulaHTTPResponse`, `NebulaHTTPInterceptor`/`NebulaAuthInterceptor` (401 refresh single-flight), `NebulaHTTPCache`/`NebulaURLCache`, pinning SSL/TLS (`NebulaSSLPinning`), SSE (`NebulaSSEEventStream`), WebSocket (`NebulaWebSocketClient`), download/multipart.
- **Segurança**: `NebulaSecureStore` (port) + `NebulaKeychain` (concreto Security.framework).
- **CloudKit**: `NebulaCloudKitSync` (port) + `NebulaCloudKitSyncEngine` (concreto), `NebulaCloudKitPreferences`/`NebulaCloudKitFeatureFlags`.
- **Prefs/Flags**: `NebulaPreferences` + `NebulaDefaults`; `NebulaFeatureFlags`/`NebulaLocalFeatureFlags`/`NebulaRemoteFeatureFlags`/`NebulaCompositeFeatureFlags`.
- **Notificações/BG**: `NebulaNotificationCenter` + `NebulaUNNotificationCenter`; `NebulaBackgroundTaskScheduler` + `NebulaBGTaskScheduler`.
- **Observabilidade**: `NebulaMetrics`/`NebulaAnalytics` (+ sinks locais e CloudKit).
- **Server local**: `NebulaHTTPServer` (NWListener).

### O que o app constrói (para libs não cobertas pelo Nebula)

Para libs que o Nebula **não** cobre (HealthKit, GameCenter, ou um SDK próprio), o app define seu próprio port na Infra e um adapter concreto. Para libs cobertas, a Infra do app pode ser **magra** — só wiring do gateway Nebula em Main.

```swift
// Infra/Sources/Infra/Health/HealthKitGateway.swift
import HealthKit  // framework externo
import Nebula

// Port da Infra para HealthKit (Nebula não cobre — o app define).
public protocol HealthGateway: Sendable {
    func authorized() async -> Bool
    func stepsToday() async throws -> Double
}

// Adapter concreto — internal (só Main instancia).
final class HealthKitGatewayImpl: HealthGateway {
    private let store = HKHealthStore()  // HKHealthStore não é Sendable → ver §Concurrency
    // …
}
```

**Visibilidade**: ports da Infra são `public` (Data precisa conformar/usar); adapters concretos são `internal` (Main instancia via factory).

### Importante: a Infra expõe ports, o Data os consome

A Infra NÃO implementa regras de negócio — só abstrai o acesso ao externo. A regra de negócio vive no repository (Data), que chama os ports/gateways da Infra.

---

## Camada 3 — Data

**Responsabilidade**: implementa as definições do Domain usando as abstrações da Infra. **O repository implementa o protocolo use case do Domain** (decisão do owner — hexagonal flat). DTOs, mappers, persistência.

### O mapeamento (decisão do owner)

- **Use case** = protocolo em Domain (ex: `LoginUseCase`).
- **Repository** = concreto em Data que **`implements` o protocolo use case**, usando os gateways da Infra.

Ou seja, o repository É o adapter do port (use case) — pattern ports & adapters. A regra de negócio + o acesso a dados vivem juntos no repository concreto.

### O que o Nebula semeia

- `NebulaRepository` (+ReadOnly/Keyed/Writable/Deletable) — **port genérico de capacidade CRUD**, *distinto* do "repository" do owner. O concreto do owner **pode opcionalmente também conforms** a `NebulaKeyedRepository<User>` etc. quando a feature é CRUD-ish (uniformiza o shape); para features de ação (`login`) não há shape CRUD — só o protocolo de use case. `NebulaRepository` é **situacional, não exigido**.
- `NebulaDTO` — marker para DTOs.
- `NebulaFakeRepository` — fake genérico in-memory (conforma `NebulaKeyedRepository`/`Writable`/`Deletable`); vale para repositories CRUD.
- **Aurora** (sibling) — `AuroraRepository<Mapping>` `@ModelActor` que conforma os 4 ports `NebulaRepository` sobre SwiftData.

### O que o app constrói (exemplo)

```swift
// Data/Sources/Data/Account/AccountRepository.swift
import Domain
import Infra
import Nebula

// O repository IMPLEMENTS o protocolo use case do Domain (hexagonal flat).
// É o adapter do port LoginUseCase; usa o gateway de network da Infra.
final class AccountRepository: LoginUseCase, SessionUseCase {
    private let client: any NebulaHTTPClient
    private let session: any NebulaPreferences       // sessão persistida
    private let mapper: AccountMapper                 // internal

    init(client: any NebulaHTTPClient, session: any NebulaPreferences) {
        self.client = client; self.session = session; self.mapper = AccountMapper()
    }

    func login(_ credentials: Credentials) async throws -> Account {
        let request = NebulaHTTPRequest(
            method: .post,
            baseURL: URL(string: "https://api.example.com")!,
            path: "/v1/login",
            body: .json(try credentials.toJSONData())
        )
        let response = try await client.send(request)
        guard response.status == 200 else {
            throw AccountDomainError(.invalidCredentials)
        }
        let dto = try response.decode(LoginResponseDTO.self)
        try session.setData(dto.token.data(using: .utf8) ?? Data(), forKey: "authToken")
        return mapper.toAccount(dto)
    }

    func currentAccount() async throws -> Account? {
        guard let token = session.data(forKey: "authToken") else { return nil }
        // … GET /me com o token …
        fatalError("exercise")
    }

    func logout() async {
        session.remove(forKey: "authToken")
    }
}

// DTO de transporte (NebulaDTO) — interno ao Data.
struct LoginResponseDTO: NebulaDTO, Codable {
    let id: UUID
    let email: String
    let displayName: String
}

// Mapper — internal.
final class AccountMapper { /* DTO → Entity */ }
```

### Repository CRUD (quando a feature é CRUD-ish)

```swift
// Quando o repository também adota a capacidade CRUD genérica do Nebula.
final class ProductRepository: ProductCatalogUseCase, NebulaKeyedRepository<Product>, NebulaWritableRepository {
    // … implements os métodos do use case (regra de negócio) E os do NebulaKeyedRepository (find/save/delete)
}
```

**Visibilidade**: os repositories são `internal` (Main instancia via factory). Os protocolos de use case que eles implementam são `public` (vêm do Domain).

### Test doubles no modelo do owner

Como o use case é um **protocolo feature-specific** (não o struct `NebulaUseCase<I,O>`), os doubles `NebulaStubUseCase`/`NebulaSpyUseCase` (genéricos sobre `<I,O>` no shape do struct) **não se aplicam diretamente**. O app escreve pequenos fakes feature-specific conformes a cada protocolo:

```swift
// Tests ou Mock
final class FakeLoginUseCase: LoginUseCase {
    let result: Result<Account, Error>
    init(_ result: Result<Account, Error>) { self.result = result }
    func login(_ credentials: Credentials) async throws -> Account {
        switch result { case .success(let a): return a; case .failure(let e): throw e }
    }
}
```

`NebulaFakeRepository` (genérico, conforma `NebulaKeyedRepository`/`Writable`/`Deletable`) **continua valendo** para repositories que adotam a capacidade CRUD.

---

## Camada 4 — Presentation

**Responsabilidade**: uso do Data + arquitetura de apresentação **observável e compartilhável** por todo o app. **Routers + Actions + States + ViewModels.** Não conhece SwiftUI (usa Meridian para a ponte observável) — a viewmodel é `@MainActor @Observable`.

### O que o Nebula semeia (Foundation-only)

- `NebulaRoute` (marker: `Hashable`/`Sendable`/`Codable` + `presentationStyle` aditivo default `.push`).
- `NebulaPresentationStyle` (`.push`/`.sheet`/`.fullScreenCover`) — **estilo por rota**.
- `NebulaNavigationStack<Route>` — stack tipado `[Route]` (single source of truth via statics).
- `NebulaPresentation<Route>` — navegação-como-dado (path + slot modal único).
- `NebulaRouter`/`NebulaPresentationRouter` — port de intenção de navegação (**async**).
- `NebulaViewModel` — marker `Sendable` para viewmodels.
- `NebulaSpyRouter` — spy para testes.

### O que o Meridian shippa (SwiftUI)

- `Router<Route>: NebulaPresentationRouter` — `@MainActor @Observable final class` (observável `path`/`presented`/`presentedStyle`).
- `MeridianNavigationStack` — `NavigationStack(path:)` + `.sheet(isPresented:)`/`.fullScreenCover(isPresented:)` driven pelo slot modal.
- `MeridianNavigationSplitView` — sidebar + detail (subsumiu o deprecated `NavigationView`).
- `MeridianTabView` — `TabView` com `Tab(value:)`, um `Router` por tab.

### O que o app constrói (exemplo)

```swift
// Presentation/Sources/Presentation/Account/LoginViewModel.swift
import Domain
import Nebula
import Meridian   // Router observável

@MainActor
@Observable
public final class LoginViewModel: NebulaViewModel {
    // State
    public private(set) var state: LoginState = .idle
    public var email = ""
    public var password = ""

    // Actions (intent methods — plain async throws)
    public func loginTapped(router: any NebulaPresentationRouter<AppRoute>) async {
        state = .loading
        do {
            let account = try await login(LoginUseCaseInput(email: email, password: password))
            state = .success(account)
            await router.replaceStack(with: [.home])
        } catch {
            state = .failure(error)
        }
    }

    // Dependências injetadas (constructor injection — nunca @Environment global).
    private let login: any LoginUseCase
    public init(login: any LoginUseCase) { self.login = login }
}

public enum LoginState: Sendable, Equatable {
    case idle, loading, success(Account), failure(any Error)
    // Nota: `failure(any Error)` quebra Equatable — modelar erro como NebulaError ou enum feature-specific.
}
```

```swift
// Rota tipada com estilo por tela (decisão do owner: "escolher qual implementar por tela").
public enum AppRoute: NebulaRoute {
    case login          // root
    case home
    case account(id: NebulaID<Account>)
    case share(id: NebulaID<Account>)   // sheet
    case onboarding                     // fullScreenCover

    public var presentationStyle: NebulaPresentationStyle {
        switch self {
        case .share:     return .sheet
        case .onboarding: return .fullScreenCover
        default:         return .push
        }
    }
}
```

**Visibilidade**: viewmodels e o enum `AppRoute` são `public` (UI precisa). Actions internas / helpers são `internal`. O router concreto (Meridian `Router`) é instanciado em Main/UI.

### Por que o port é async

O Nebula não tem `@MainActor` default (sem SwiftUI). O `Router` Meridian é `@MainActor @Observable` e precisa conformar um port Nebula. A solução: `NebulaRouter`/`NebulaPresentationRouter` são **async**; um método sync `@MainActor` witnesses um requirement async nonisolated (o `await` hopa o actor). Assim um deep-link parser off-actor pode `await router.replaceStack(with:)`. Ver [[nebula-presentation-architecture]].

---

## Camada 5 — UI

**Responsabilidade**: views, screens, componentes, toolbar items (top/bottom), tab accessories. **Nebula fica de fora** (binding: zero SwiftUI no Nebula). Constrói sobre **Cosmos** (design system) + **Meridian** (containers) + a Presentation do app.

### O que o app constrói (exemplo)

```swift
// UI/Sources/UI/Login/LoginScreen.swift
import SwiftUI
import Cosmos        // design system (componentes/tokens)
import Meridian      // MeridianNavigationStack, Router
import Presentation  // LoginViewModel, AppRoute

public struct LoginScreen: View {
    @Bindable var viewModel: LoginViewModel
    let router: Router<AppRoute>

    public var body: some View {
        CosmosScreen { // Cosmos container
            CosmosTextField(text: $viewModel.email, label: "Email")
            CosmosSecureField(text: $viewModel.password, label: "Senha")
            CosmosButton("Entrar") {
                Task { await viewModel.loginTapped(router: router) }
            }
        }
    }
}
```

O root do app monta o trio de containers (decisão do owner — pickable por área de tela):

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MeridianTabView(selection: AppTab.items) { tab in
                switch tab {
                case .items:    MeridianNavigationStack(router: itemsRouter, root: { ItemsScreen() }) { destination($0) }
                case .settings: MeridianNavigationStack(router: settingsRouter, root: { SettingsScreen() }) { destination($0) }
                }
            }
        }
    }
}
```

**Visibilidade**: views/screens são `public` (o app `@main` precisa). Helpers de view são `internal`. **Um `Router`/`MeridianNavigationStack` por tab** — nunca compartilhar path entre tabs.

---

## Camada 6 — Main (composition root)

**Responsabilidade**: montar **todas as dependências** para acesso global; montar **ambientes**. É o único lugar que conhece **concretos** (Data repositories, Infra gateways). O app importa `Main` e injeta dependências.

### O que o Nebula semeia

- `NebulaRegistry` — DI como **mapa de factories**, **não container** (guardrail: "não estender para singleton/scoping/auto-injection").
- `NebulaRegistryConfiguration` (`.withFactory(for:_:)`) + `NebulaRegistryConfig` (accessor `Mutex` process-wide: `get()`/`set(_:)`/`resolve(_:as:)`).
- As **config structs** + accessores `Mutex` process-wide: `NebulaLogConfiguration`/`NebulaLogConfig`, `NebulaErrorConfiguration`/`NebulaErrorConfig`, `NebulaMeasureConfiguration`/`NebulaMeasureConfig`, `NebulaStandards`/`NebulaStandardsConfig`, `NebulaEnvironment`/`NebulaEnvironmentConfig`, + Metrics/Analytics/CloudKit/Notifications/BackgroundTasks.
- `NebulaGatewayConfiguration`/`NebulaKeychainConfig` etc. (configs por gateway).

### O que o app constrói (exemplo)

```swift
// Main/Sources/Main/AppCompositionRoot.swift
import Nebula
import Domain
import Infra
import Data
import Presentation

public enum AppCompositionRoot {
    /// Chamado uma vez no `@main`/`App.init`.
    public static func bootstrap() {
        // 1. Ambiente (Info.plist "Configuration" → .development/.staging/.production)
        let env = NebulaEnvironment.fromBundle()
        NebulaEnvironmentConfig.set(.default.with(baseURLs: [
            .development: URL(string: "https://dev.api.example.com")!,
            .production:  URL(string: "https://api.example.com")!,
        ]))

        // 2. Configs transversais (process-wide Mutex accessors)
        NebulaLogConfig.set(.default.withSubsystem("com.example.app").withMinLevel(env == .production ? .info : .debug))
        NebulaErrorConfig.set(.default.withCategory("App"))
        NebulaMeasureConfig.set(.default)

        // 3. Infra gateways (concretos — só Main os instancia)
        let http: any NebulaHTTPClient = NebulaHTTPGateway(
            session: NebulaHTTPSession.default,
            configuration: NebulaGatewayConfiguration.default
        ).intercepted(by: [NebulaAuthInterceptor(provider: TokenProviderImpl())])
        let secure: any NebulaSecureStore = NebulaKeychain(config: .init(service: "com.example.app"))
        let prefs: any NebulaPreferences = NebulaDefaults.standard()

        // 4. Data repositories (implementam os protocolos use case do Domain)
        let login: any LoginUseCase = AccountRepository(client: http, session: prefs)
        let session: any SessionUseCase = AccountRepository(client: http, session: prefs)

        // 5. Registry — mapa de factories (DI sem container). Resolução tipada por chave.
        NebulaRegistryConfig.set(
            NebulaRegistryConfiguration()
                .withFactory(for: "login") { login as Any }
                .withFactory(for: "session") { session as Any }
        )
    }

    /// Factory pública — única superfície pública do Main. O resto é internal.
    public static func makeLoginViewModel() -> LoginViewModel {
        let login = NebulaRegistryConfig.resolve("login", as: any LoginUseCase.self)
        return LoginViewModel(login: login)
    }
}
```

**Visibilidade**: o Main expõe **factories públicas** (`makeLoginViewModel()` etc.) e o `bootstrap()`. Tudo o mais é `internal`. A viewmodel nunca resolve do registry por dentro — recebe por constructor injection (testável). O registry é um **mapa de factories**, não um container com auto-injeção.

### Guardrail do Nebula (load-bearing)

- **Não** estender `NebulaRegistry` para singleton/scoping/auto-injection — é um mapa de factories, não container (scope-creep risk #3).
- Mantenha as factories do registry `nonisolated @Sendable`; deixe o app fazer o hop de actor (Factory#322).
- O Nebula deliberadamente **não** shippa um `NebulaCompositionRoot`/`NebulaAppContainer` (trivial = redundante; não-trivial = deriva para container). O composition root é **trabalho do app**. Ver DocC `ArchitectureCompositionRoot.md` e [[nebula-composition-root]].

---

## Camada 7 — Mock (opcional)

**Responsabilidade**: dados mocados via JSON para **previews** (SwiftUI `#Preview`). Cria todas as estruturas mocadas para o preview funcionar sem backend.

### O que o Nebula semeia (já importável para preview)

Os test doubles do Nebula são **`public` no product target** (`Sources/Nebula/Architecture/Testing/` + `Presentation/NebulaSpyRouter`), então **importáveis em previews** (não só em testes):

- `NebulaFakeRepository<Entity>` — fake in-memory genérico (CRUD).
- `NebulaStubUseCase<I,O>` / `NebulaSpyUseCase<I,O>` — para o shape `NebulaUseCase<I,O>` (genérico).
- `NebulaSpyRouter<Route>` — spy de router.

### O que o app constrói

Para use cases feature-specific (protocolos), o app escreve fakes pequenos + fixtures JSON:

```swift
// Mock/Sources/Mock/Account+Mock.swift
import Domain
import Nebula

public enum AccountMock {
    public static let sample = Account(
        id: NebulaID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        email: "rafa@example.com",
        displayName: "Rafael"
    )

    public static func loginUseCase(result: Result<Account, Error> = .success(sample)) -> any LoginUseCase {
        FakeLoginUseCase(result)
    }
}

// Uso em #Preview (UI):
// #Preview { LoginScreen(viewModel: LoginViewModel(login: AccountMock.loginUseCase()), router: ...) }
```

Fixtures JSON ficam em `Mock/Resources/*.json` (lidos via `Bundle.module` no target Mock). O Mock é importado só pelo target de UI para previews (e opcionalmente por testes).

**Visibilidade**: fakes/fixtures são `public` (UI/tests importam). O Mock **não** vira produto — é um target de preview/test.

---

## Concorrência (Swift 6, zero warnings) — regras que atravessam as camadas

- Todos os value types públicos são `Sendable` (conformance derivada; **nunca `@unchecked Sendable` em tipo-valor do app** — o binding do Nebula proíbe em tipos Nebula; aplique o mesmo princípio nos módulos do app).
- Closures de handler em configs são `@Sendable`.
- Estado mutável compartilhado → `Mutex<T>`/`Atomic<T>` de `import Synchronization` (SwiftStdlib 6.0, abaixo de `.v26`). **Sem `NSLock`, sem `DispatchQueue`, sem `nonisolated(unsafe)`.** `Mutex`/`Atomic` são `~Copyable` → declare sempre `let`, nunca `var`.
- **Actors, não global actors.** O app fornece seu próprio isolation (a viewmodel é `@MainActor @Observable`; o Nebula não impõe `@MainActor`).
- Tipos de Apple não-Sendable em gateway próprio (ex: `HKHealthStore`, `URLCache`): envolva em `Mutex` (region-based isolation) ou num `final class @unchecked Sendable` com `let` (o precedente `NebulaMemoryLogHandler`/`NebulaBGTaskBox` — `@unchecked` é permitido em **reference types** auditar, não em value types do app).
- Erros que cruzam actors **precisam** ser `Sendable` — derive. Use `NebulaError` (já `Sendable`) ou seus `NebulaFailure` open structs.
- Region-based isolation (SE-0414) antes de `@unchecked`.

## Estrutura de pacotes (SwiftPM) sugerida

Cada camada = um target (ou package) SwiftPM. Exemplo de `Package.swift` do app:

```swift
// App.Package.swift (esboço)
products: [
    .executable(name: "MyApp", targets: ["Main"]),
],
targets: [
    .target(name: "Domain",    dependencies: ["Nebula"]),
    .target(name: "Infra",     dependencies: ["Domain", "Nebula"]),  // + libs externas
    .target(name: "Data",      dependencies: ["Domain", "Infra", "Nebula", "Aurora"]),
    .target(name: "Presentation", dependencies: ["Domain", "Data", "Nebula", "Meridian"]),
    .target(name: "UI",        dependencies: ["Presentation", "Nebula", "Meridian", "Cosmos"]),
    .target(name: "Main",      dependencies: ["UI", "Presentation", "Data", "Infra", "Domain", "Nebula"]),
    .target(name: "Mock",      dependencies: ["Domain", "Nebula"]),
]
```

- Domain depende só de Nebula (não conhece Infra/Data/UI).
- Data depende de Domain + Infra + Nebula (+ Aurora se SwiftData).
- Presentation depende de Domain + Data + Nebula + Meridian.
- UI depende de Presentation + Nebula + Meridian + Cosmos.
- Main depende de todas (composition root).
- Mock depende de Domain + Nebula.
- **Nenhum módulo do app importa Cosmos/Meridian exceto UI/Presentation** — a regra de dependência é enforced por quem importa quem.

## Checklist de implementação de um app

- [ ] Definir o enum `AppRoute: NebulaRoute` com `presentationStyle` por tela (push/sheet/fullScreenCover).
- [ ] Domain: entidades (`: NebulaAggregate`), DTOs (`: NebulaDTO`), protocolos de use case (`: NebulaInputPort`), erros (`: NebulaFailure`).
- [ ] Infra: para libs não-Nebula, definir ports + adapters `internal`; para libs Nebula, só wiring.
- [ ] Data: repositories `internal` que `implements` os protocolos use case do Domain, chamando a Infra; DTOs/mappers.
- [ ] Presentation: viewmodels `@MainActor @Observable` (`: NebulaViewModel`) com state + actions; constructor injection dos use cases.
- [ ] UI: views sobre Cosmos + Meridian; um `Router` por tab; `destination(for:)` switch no enum `AppRoute`.
- [ ] Main: `bootstrap()` com `NebulaEnvironment` + configs process-wide + gateways Infra + repositories Data + `NebulaRegistry` (mapa de factories); factories públicas, resto `internal`.
- [ ] Mock: fakes feature-specific + fixtures JSON para `#Preview`.
- [ ] Concorrência: zero warnings Swift 6; `Sendable` derivado; `Mutex`/`Atomic` para estado compartilhado; `@MainActor` só na viewmodel.
- [ ] Testes: viewmodels com fakes de use case; repositories com fakes de Infra; routers com `NebulaSpyRouter`; deep-links como dados (`router.path == […]`).

## Referências

- Análise de enquadramento: [[nebula-seven-layer-app-fit]]
- ADR da decisão (use case=protocolo, repository=concreto): [[adr-seven-layer-app]]
- Toolkit Clean Architecture: [[nebula-clean-architecture-toolkit]]
- Presentation (MVVM `@Observable` + Router): [[nebula-presentation-architecture]]
- Registry/DI sem container: [[nebula-registry-di]]
- Use case (struct, opt-in não usado neste modelo): [[nebula-usecase]]
- Repository (port genérico CRUD, situacional): [[nebula-repository]]
- Composition root: [[nebula-composition-root]]
- TDD por camadas: [[nebula-clean-architecture-tdd]]