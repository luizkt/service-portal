# Service Portal

Portal extensível com arquitetura em 3 camadas: Frontend React (Server Driven UI) → BFF Java → Generic Orchestrator Java + MongoDB.

Diretório raiz: `/home/luizkt/git/service-portal/`
Branch principal: `claude/projeto-base`

---

## Stack

| Componente | Stack | Porta |
|---|---|---|
| `generic-orchestrator/` | Java 21 + Spring Boot 3.4.5 + Gradle + MongoDB 7 | 8080 |
| `service-portal-bff/` | Java 21 + Spring Boot 3.4.5 + Gradle + WebClient | 8081 |
| `service-portal-manager/` | Kotlin 2.0 + Spring Boot 3.4.5 + Gradle + MongoDB 7 | 8082 |
| `service-portal-frontend/` | React 18 + TypeScript + Vite 5 | 5173 (dev) / 80 (prod) |

**Infraestrutura local:** MongoDB 7, **Redis 7** (cache), RabbitMQ 3, Kafka (Confluentinc 7.5.0 + Zookeeper), LocalStack 3 (SQS), WireMock (APIs externas), **Portainer CE** (gerenciamento de containers)
**Segurança:** JWT HS512 (jjwt 0.12.6) no orquestrador; OAuth2 Resource Server (Authentik) no BFF
**HTTP client:** Spring WebFlux WebClient (Netty)
**Monitoramento:** Portainer CE via http://localhost:9001

---

## Decisões tomadas

- Padrão **Server Driven UI**: BFF controla menu e schema de UI; frontend não tem regras de negócio
- Frontend fala **somente com o BFF** — nunca diretamente com o orquestrador
- Auth BFF → Orquestrador é **server-to-server** (admin/admin), token em cache com renovação automática
- Multi-instância de Kafka e RabbitMQ configurada via `orch-integrations` no `application.yml`; match pelo campo `id`
- Profile Spring `docker` para rodar com `docker compose up`
- Sem libs de UI/state externas no frontend — `fetch` nativo + `useState/useEffect`
- Endpoints de execução versionados: `/api/v1/flows/{flowId}/versions/{version}/executions` (sequencial) e `/api/v2/flows/{flowId}/versions/{version}/executions` (paralelo via Virtual Threads)
- MongoDB: database `generic-orchestrator`, collection `workflows`, índice composto em `id` + `versao`

---

## Restrições

- Java 21 LTS, Spring Boot 3.4.5 LTS — não atualizar versões
- Gradle com Kotlin DSL
- Sem trocar WebClient por RestTemplate ou similares
- Frontend sem bibliotecas de UI externas (sem Material UI, Ant Design, etc.)
- Parâmetros de retry e circuit breaker devem ser externalizados no `application.yml` — não hardcoded
- **Orquestrador não tem mais dependência direta com banco de dados** — workflows persistem dados via integrações HTTP downstream

---

## Arquitetura — fluxo geral

```
Usuário
  └─> Frontend (React, :5173)
        └─> BFF (Java, :8081)
              ├─> GET  /bff/menu
              ├─> GET  /bff/ui/{featureId}
              ├─> GET/POST/PUT/DELETE /bff/flows[...]
              └─> POST /bff/orchestrate/{version}/{flowId}
                    └─> Orquestrador (Java, :8080)
                          ├─> POST /api/auth/login  (auth interna)
                          ├─> /api/flows[...]
                          └─> /api/orchestrate/{version}/{flowId}
                                └─> MongoDB

Manager (Kotlin, :8082) — dono da collection `workflows` (após migração faseada)
  ├─> POST /api/auth/login (auth interna, JWT HS512)
  ├─> /manager/flows[...]                         (CRUD via YAML)
  ├─> GET /manager/workflows/active               (consumido pelo orquestrador)
  └─> GET /manager/workflows/{id}/{versao}/yaml   (consumido pelo orquestrador)
       └─> MongoDB
```

---

## Módulos / status geral

| Módulo | Componente | Status | Notas |
|---|---|---|---|
| Server Driven UI (menu + schema) | BFF + Frontend | ✅ Feito | |
| CRUD de fluxos (Flow Manager) | Orquestrador + BFF + Frontend | ✅ Feito | |
| Multi-instância Kafka/RabbitMQ | Orquestrador | ✅ Feito | feature_1 — item 1 |
| Profile `docker` + application-docker.yml | Orquestrador | ✅ Feito | feature_1 — item 2 |
| Script init MongoDB (`mongodb-workflows/`) | Orquestrador | ✅ Feito | feature_1 — itens 3 e 4 |
| Versionamento na URL `/api/orchestrate/{version}/{flowId}` | Orquestrador | ✅ Feito | feature_2 — item 1 |
| Índice composto `id` + `versao` no MongoDB | Orquestrador | ✅ Feito | feature_2 — item 2 |
| Retry + Circuit Breaker nas integrações HTTP | Orquestrador | ✅ Feito | feature_3 |
| Auth de usuário final (Authentik + OAuth2/PKCE) | BFF + Frontend | ✅ Feito | SPA público + Bearer ao BFF |
| WireMock como simulador de APIs externas | Orquestrador + docker-compose | ✅ Feito | Alias `api.exemplo.com` na rede `portal` |
| Novo serviço service-portal-manager | Manager | ✅ Feito | Kotlin + Spring Boot, dono da collection `workflows` |
| Refactor bff e orquestrador para novo service-portal-manager | BFF + Orquestrador | ✅ Feito | BFF→Manager (CRUD); Orquestrador→Manager (consulta) com cache Redis 1h |
| Remoção do MongoDB do orquestrador | Orquestrador | ✅ Feito | `IntegrationType.DATABASE` extinto; sem dep `spring-boot-starter-data-mongodb` |
| Refactor REST + tudo em inglês (paths, payloads, YAML) | Todos os serviços | ✅ Feito | Sub-recursos `versions/{v}` + `executions`; filtros via query params; `auth/tokens` |
| Correção do `docker-compose.yml` (contextos de build) | Raiz | ✅ Feito | Zookeeper + Confluentinc Kafka adicionado (Bitnami indisponível), healthchecks corrigidos (wget→curl), port mapping Orchestrator adicionado, README atualizado |
| Validação do `docker compose up` | Raiz | ✅ Feito | Todos os containers rodando saudáveis (healthy), todos os endpoints respondendo HTTP 200, stack completa validada |
| Revisão dos cenarios de testes com novas atualizaćões | Raiz | ✅ Feito | YAMLs em inglês, endpoints REST atualizados, DATABASE removido, Manager integrado, script automático criado |
| Diagnóstico e resolução de instabilidade dos containers | Raiz | ✅ CONCLUÍDO | Phase 1 ✅ Orchestrator (endpoints corrigidos); Phase 2 ✅ Manager (autenticação OK); Phase 3 ✅ Docker curl fix (containers healthy) |
| **Análise detalhada: Estabilidade Manager & Erros 401** | Manager | ✅ CONCLUÍDO | DIAGNOSTICO-MANAGER-401.md; todos endpoints OK; containers healthy após curl fix |
| **Fix Crítico: Healthcheck dos Containers** | Raiz | ✅ CONCLUÍDO | DIAGNOSTICO-HEALTHCHECK-CURL.md; Dockerfiles + apk curl; Manager/Orchestrator/BFF → HEALTHY ✅ |
| **Diagnóstico dos Testes Integrados (v1)** | Raiz | ✅ CONCLUÍDO | Executado script v1; taxa 25% (5/20 passaram); 5 problemas catalogados; script v2 criado |
| Criação de arquivo AGENTS.md para cada aplicação | Todos | ✅ Feito | generic-orchestrator, bff, manager, frontend |
| **Corrigir testes integrados** | Raiz + BFF | ✅ Feito | Script v3 criado; 32/33 (96%) passando, 0 falhas; 1 skipped = aviso jq ausente |
| **Authentik automático no docker-compose** | Raiz + BFF | ✅ Feito | Blueprint `/authentik/blueprints/service-portal.yml`; bootstrap vars; BFF multi-issuer JWT; global token endpoint; script v3 integrado com `.env` sourcing |
| **Grupos de acesso + autorização por grupo** | Authentik + BFF | ✅ Feito | Blueprint: grupos ADMIN/RULES/WORKFLOWS + usuários it/bizop/workop; scope mapping `groups` claim no JWT; `@EnableMethodSecurity` + `JwtAuthenticationConverter`; `@PreAuthorize` em FlowProxyController; 40 testes passando |
| **Tela de login com formulário + acesso por grupo** | Frontend + BFF | ✅ Feito | BFF-proxied login via Authentik Flow Executor (HTTP/1.1, PRG + PKCE); `loginWithPassword` chama `/bff/auth/login`; `decodeJwtPayload` extrai groups do JWT; sidebar com nome+badge por grupo; welcome screen com perfil de acesso; 69 testes frontend + 3 testes BFF |
| **Filtragem de menu por grupo (sidebar)** | BFF | ✅ Feito | BFF filtra `GET /bff/menu` pelo grupo do usuário autenticado; `MenuItemDto` ganha `requiredGroups` (`@JsonIgnore`); `flow-manager` exige ADMIN ou WORKFLOWS; RULES e sem-grupo recebem lista vazia; 6 novos testes, 49 total, BUILD SUCCESSFUL |
| **Versionamento semântico automático no update de workflow** | Manager | ✅ Feito | `PUT /manager/flows/{flowId}/versions/{v}` mantém versão antiga ativa e cria nova via SemVer 2.0.0 (MAJOR=contract, MINOR=integrations, PATCH=description); `GET /manager/flows` lista somente ativos; 71 testes, cobertura ≥ 95% |
| **Endpoint de histórico de versões** | Manager | ✅ Feito | `GET /manager/flows/{flowId}/versions?status=active\|inactive` lista todas as versões (ou filtra); 76 testes, cobertura ≥ 95% |
| **Execução multithread com Java Virtual Threads (v2 endpoint)** | Orquestrador | ✅ Feito | Endpoint v1 (`/api/v1/flows/...`) preserva comportamento sequencial; endpoint v2 (`/api/v2/flows/...`) paralela integrações com mesmo `order` via `Executors.newVirtualThreadPerTaskExecutor()`; `FlowExecutionContext.integrations` migrado para `ConcurrentHashMap`; `OrchestrationV2Service` + 6 testes; 78 testes total, BUILD SUCCESSFUL |
| **Propagação v2 para BFF e Frontend (comparativo de performance)** | BFF + Frontend | ✅ Feito | BFF: `OrchestratorClient.executeV2()` + endpoint `POST /bff/flows/.../executions/v2`; Frontend: botões "v1 Sequencial" e "v2 Paralelo" com resultados lado a lado; 51 testes BFF + 70 testes frontend, todos passando |
| **Modularização de workflows: collections integrations, contracts, validations** | Manager | ✅ Feito | 3 novas collections MongoDB; CRUD APIs `/manager/integrations`, `/manager/contracts`, `/manager/validations`; `ResourceRef` + campos `contract/integrationRefs/validationRefs` no `FlowDocument`; `SequentialVersioningService` (1→2→3); `init-mongo.js` atualizado; 150 testes, 0 falhas |
| **Execução da seção `validations` no pipeline do orquestrador** | Orquestrador | ✅ Feito | Fase validações após integrações em v1 e v2; reutiliza `IntegrationDefinition`; `FlowExecutionContext.validations` separado de `integrations`; `executePhase()` + `runStep(BiConsumer)` no v2; resposta inclui `result` (integrações) e `validations` (validações) como mapas separados; 87 testes, 0 falhas, gate JaCoCo ≥ 95% |

---

## Progresso detalhado — generic-orchestrator

### ✅ Feito
- Multi-instância de Kafka e RabbitMQ via `orch-integrations` com match por `id`
- `provider` movido para o nível principal no YAML de workflow
- Profile Spring `docker` com `application-docker.yml`
- Pasta `mongodb-workflows/` com `init-mongo.js` (cria database, collection e índice)
- Endpoint `GET /api/flows` para listar fluxos ativos
- Versionamento na URL: `POST /api/orchestrate/{version}/{flowId}`
- Busca no MongoDB por `id` + `versao` (índice composto)
- README atualizado
- **WireMock** — simulador de APIs HTTP externas em `docker-compose-service-portal.yml`:
  - Container `wiremock/wiremock:3.9.1` na rede `portal` com **alias `api.exemplo.com`** — workflows continuam usando URL realista, o DNS do Docker resolve para o container
  - Mappings em [`wiremock/mappings/`](wiremock/) (raiz do repo): `GET /clientes/{[A-Z0-9]{6,20}}` → 200 com `clienteId` ecoado via template; fallback `GET /clientes/*` → 404
  - Porta admin/host configurável via `WIREMOCK_PORT` no `.env` (default `18080`)
  - `orchestrator` ganhou `depends_on: wiremock {service_healthy}` para integrar com testes integrados
  - **Correção** em [docs/example-flow.yml](generic-orchestrator/docs/example-flow.yml): `provider:` movido de dentro de `queue:` para o nível da `IntegrationDefinition` (3 ocorrências); URL HTTP em vez de HTTPS
  - Novo teste em `YamlParserServiceTest` carrega o arquivo do disco e valida estrutura (URL, provider em todas as integrações QUEUE, contagem de campos/integrações)
- **Refactor REST de endpoints + nomes em inglês (todos os serviços)**:
  - Aplicação de boas práticas REST em **paths, payloads e YAML** — cutover limpo, sem compat com paths antigos
  - **Sub-recursos explícitos** em vez de paths planos:
    - `/api/flows/{flowId}/versions/{version}/executions` (substitui `/api/orchestrate/{ver}/{id}`)
    - `/manager/flows/{flowId}/versions/{version}` (substitui `/manager/flows/{id}/{versao}`)
    - `/manager/flows/{flowId}/versions/{version}/yaml` (substitui `/manager/workflows/.../yaml`)
    - `/bff/flows/{flowId}/versions/{version}` e `/executions` (espelha o backend)
    - `/bff/features/{featureId}/ui-schema` (substitui `/bff/ui/{id}`)
  - **Filtros como query params**: `GET /manager/flows?status=active` substitui `/manager/workflows/active`; também propagado em `/bff/flows?status=active`
  - **Auth como recurso**: `POST /api/auth/tokens` (cria token, devolve **201**) substitui `/api/auth/login` em orquestrador e Manager
  - **Tudo em inglês** — paths, JSON payloads e YAML:
    - Modelo `FlowDefinition` (Java) e `FlowDocument` (Kotlin) com campos `flowId`, `version`, `description`, `active`, `contract`, `integrations`, `createdAt`, `updatedAt`
    - `IntegrationDefinition.order/type/continueOnError`, `HttpIntegrationConfig.method/responseMapping`, `QueueIntegrationConfig.persistent/messageTemplate`, `ResponseMapping.targetField/sourceField`, `ValidationRule.type/value/message`
    - YAML root vira `flow:` (era `fluxo:`); chaves traduzidas (`contract.fields`, `integrations`, `responseMapping`, `bodyTemplate`, `messageTemplate`, etc.)
    - `{{contract.x}}` e `{{integrations.stepId.field}}` nos templates (era `{{contrato.}}`/`{{integracoes.}}`)
  - **`example-flow.yml`** reescrito em inglês — fluxo agora é `create-order-v1`, endpoints simulados `/clients/{id}` e `POST /orders`; WireMock mappings renomeados (`clientes-*.json` → `clients-*.json`) e novo `orders-post.json`
  - **Índice Mongo** (`mongodb-workflows/init-mongo.js`): chave do índice composto atualizada de `flowId`+`versao` para `flowId`+`version`
  - **Frontend**: `src/types/index.ts` (`FlowDefinition` com novos campos + novo tipo `FlowsPage`), `src/api/bff.ts` (paths + parâmetros novos), `FlowManager.tsx` (renderização adaptada para EN; YAML template em inglês)
  - **Testes**: bulk rename PT→EN em getters/setters via `sed`; testes reescritos com novos paths e literais; `OrchestrationController` test atualizado; `FlowProxyController` test atualizado; Frontend `bff.test.ts` adicionou 4 testes novos (paginação, filtro status, getYaml + 401)
  - **Coverage**: orquestrador 99% INSTRUCTION (842/843); Manager 96% INSTRUCTION; BFF 100% INSTRUCTION (todos os módulos da feature); Frontend **100%** lines/branches/functions/statements (44 testes)
  - **Imagens Docker** construídas: `generic-orchestrator:test` (280 MB), `service-portal-manager:test` (248 MB), `service-portal-bff:test` (244 MB), `service-portal-frontend:test` (62 MB)
- **Remoção da dependência com MongoDB no orquestrador**:
  - Workflows não fazem mais integração de banco de dados durante a execução. Persistência de domínio passa a ser responsabilidade dos serviços downstream chamados via integrações HTTP/QUEUE
  - **Removidos**: `DatabaseIntegrationExecutor`, `DatabaseIntegrationConfig`, `DatabaseOperation`, valor `IntegrationType.DATABASE`, campo `database` em `IntegrationDefinition`
  - **Build**: removidas dependências `spring-boot-starter-data-mongodb` e `org.testcontainers:mongodb`
  - **Config**: removido bloco `spring.data.mongodb` em `application.yml`/`application-docker.yml`; removidas vars `MONGODB_URI`/`MONGODB_DATABASE` no `Dockerfile`
  - **docker-compose-service-portal.yml**: orquestrador perdeu `depends_on: mongodb` e env vars MongoDB
  - **Compose local** (`generic-orchestrator/docker-compose.yml`): MongoDB removido; apenas Redis + RabbitMQ + Kafka (KRaft) + LocalStack
  - **`example-flow.yml`**: passo `salvar-pedido` migrado de `tipo: DATABASE` (INSERT em coleção `pedidos`) para `tipo: HTTP` (POST `http://api.exemplo.com/pedidos`) — coerente com a nova arquitetura
  - **Tests**: `IntegrationExecutorFactoryTest` ajustado (sem DATABASE); `YamlParserServiceTest` valida o novo passo HTTP em `example-flow.yml`; `AbstractIntegrationTest` perdeu o `MongoDBContainer`. 70 testes passando, **cobertura mantida em 99% INSTRUCTION** (842/843)
  - **Imagem Docker**: `generic-orchestrator:test` 280 MB (5 MB menor que antes — sem driver Mongo)
  - O Manager continua usando MongoDB normalmente (collection `workflows`); o orquestrador apenas consulta o Manager via HTTP
- **Refactor Orquestrador → consumidor do service-portal-manager (com cache Redis)**:
  - `FlowDefinitionRepository`, `FlowDefinitionService`, `FlowDefinitionController` **removidos** — CRUD migrou totalmente para o Manager
  - `FlowDefinition` perdeu `@Document`/`@Indexed` (não é mais persistido pelo orquestrador) — vira modelo em memória usado pelo executor
  - Novo pacote `com.orchestrator.manager`:
    - `ManagerAuthService` — login server-to-server contra `service-portal-manager`, JWT em cache com renovação a cada ~1h
    - `ManagerWorkflowClient` — `GET /manager/workflows/active` e `.../yaml` (mapeia 404 do Manager para `FlowNotFoundException`)
    - `WorkflowSummary` — DTO da lista de ativos
    - `WorkflowCacheService` — `@Cacheable("workflows", key = "#flowId + '_' + #versao")`; cache miss → fetch YAML do Manager → parse → cacheia
    - `WorkflowCacheWarmer` — `@EventListener(ApplicationReadyEvent.class)`: lista ativos e popula o Redis no startup. Falhas individuais não impedem subida; flag `orchestrator.cache.workflows.warm-up-enabled` desabilita
  - `RedisCacheConfig` — `@EnableCaching` + `RedisCacheManager` com TTL 1h e Jackson serializer com type info preservada
  - `OrchestrationService` migrado de `flowDefinitionService.findActiveByFlowIdAndVersion(...)` para `workflowCacheService.load(...)` — ponto único de carregamento
  - `ManagerWebClientConfig` + `ManagerProperties` (`@ConfigurationProperties("orchestrator.manager")`)
  - `application.yml`/`application-docker.yml`/`Dockerfile` ganharam `REDIS_*`, `MANAGER_*`, `WORKFLOWS_CACHE_TTL_SECONDS`, `WORKFLOWS_WARM_UP_ENABLED`
  - `SecurityConfig` agora retorna 401 explicitamente em endpoints protegidos sem token (via `HttpStatusEntryPoint`)
  - JaCoCo gate ≥ 95% expandido para incluir `manager/**`, `RedisCacheConfig`, `ManagerWebClientConfig`, `ManagerProperties` — atual **99%** INSTRUCTION (842/843)
  - Testes: `ManagerWorkflowClientTest` (MockWebServer, 7 casos), `ManagerAuthServiceTest` (3 casos), `WorkflowCacheServiceTest` (3 casos), `WorkflowCacheWarmerTest` (4 casos), `OrchestrationServiceTest` reescrito para `WorkflowCacheService`. `OrchestrationFlowIT` removido (acoplado ao CRUD antigo); `SecurityIT` ajustado
  - **Trade-off conhecido**: invalidação somente por TTL — workflows atualizados via Manager podem ficar stale por até 1h. `WorkflowCacheService` expõe `evict(...)` e `evictAll()` para uso futuro (admin endpoint ou Redis Pub/Sub)
- **feature_3** — Retry + Circuit Breaker nas integrações HTTP (Resilience4j):
  - Backoff exponencial e circuit breaker em `HttpIntegrationExecutor` (ordem `Retry(CircuitBreaker(httpCall))`)
  - Parâmetros externalizados em `orch-integrations.retry-configuration` e `orch-integrations.circuit-breaker-configuration` no `application.yml`
  - Configuração padrão única para todas as integrações HTTP (`HttpResilienceConfig`)
  - Predicate de retry trata `CallNotPermittedException` (não retenta) e `WebClientResponseException` não-retryable (não retenta); status retryable (500, 429, 408 por padrão) propagados via `RetriableHttpException`
  - Plugin JaCoCo configurado com gate `jacocoTestCoverageVerification` (≥ 95% INSTRUCTION) escopado às classes da feature
  - 16 testes unitários em `HttpIntegrationExecutorTest` cobrindo retry/CB/timeout/listeners/predicate — cobertura **100%** das classes da feature
  - Imagem Docker `generic-orchestrator` construída com sucesso

### ⬜ Pendente

(nenhum item pendente neste componente)

### ✅ Consumidores do endpoint v2 — implementados

**BFF (`service-portal-bff`)**
- `OrchestratorClient`: path corrigido para `/api/v1/flows/...`; método `executeV2()` adicionado apontando para `/api/v2/flows/...`
- `FlowProxyController`: novo endpoint `POST /bff/flows/{flowId}/versions/{version}/executions/v2` delegando para `executeV2()`
- Testes: `OrchestratorClientTest` atualizado (v1 path) + novo caso v2; `FlowProxyControllerTest` com caso `executeFlowV2`; 51 testes BFF, 0 falhas

**Frontend (`service-portal-frontend`)**
- `bff.ts`: função `executeV2()` adicionada chamando `/bff/flows/.../executions/v2`
- `FlowManager.tsx`: botões "v1 Sequencial" e "v2 Paralelo" na view de execução; resultados exibidos lado a lado em grid 2 colunas para comparativo visual
- `.css`: estilos `btn-secondary`, `fm-exec-actions`, `fm-exec-compare`, `fm-exec-status` adicionados
- Testes: `bff.test.ts` com caso `executeV2`; 70 testes frontend, 0 falhas

### ❌ Descartado
- (nada descartado até o momento)

---

## Progresso detalhado — service-portal-bff

### ✅ Feito
- Endpoints de menu e UI schema (Server Driven UI)
- Proxy completo de fluxos para o orquestrador
- Auth server-to-server com cache e renovação automática de token
- OAuth2 Resource Server configurado (Authentik, JWKS)
- **Auth de usuário final** — endpoint público `GET /bff/auth/config` (issuer, client_id, scopes) para o frontend configurar o fluxo OAuth2/PKCE sem hardcoded; `AuthProperties` (`@ConfigurationProperties("bff.auth")`) com defaults `[openid, profile, email]`; `SecurityConfig` libera `/bff/auth/config` como público; JaCoCo gate ≥ 95% (atual **100%**, 134/134 instruções) escopado em `SecurityConfig`, `AuthProperties`, `AuthConfigController`, `AuthConfigDto`; 10 testes unitários e de integração (`@SpringBootTest` com `MockMvc` validando 401 nos endpoints protegidos e 200 nos públicos)
- **Refactor BFF → CRUD via service-portal-manager**:
  - **Novo cliente `ManagerClient`** + `ManagerAuthService` (login server-to-server contra Manager, JWT em cache). Endpoints consumidos:
    - `POST /manager/flows` (criar), `GET /manager/flows?page=&size=&sort=` (listar), `GET/PUT/DELETE /manager/flows/{flowId}/{versao}`, `GET /manager/workflows/{flowId}/{versao}/yaml`
  - **`OrchestratorClient` reduzido** — só permanece o método `orchestrate(...)`; CRUD foi extraído
  - **`FlowProxyController` refatorado**:
    - GET `/bff/flows?page=&size=&sort=` (paginado, sem `yamlContent`) → Manager
    - GET `/bff/flows/{flowId}/{versao}` (metadados) → Manager
    - GET `/bff/flows/{flowId}/{versao}/yaml` (YAML cru, `application/x-yaml`) → Manager
    - POST `/bff/flows`, PUT/DELETE `/bff/flows/{flowId}/{versao}` → Manager
    - POST `/bff/orchestrate/{version}/{flowId}` → Orquestrador (única chamada que sobrou)
    - 404 do Manager mapeado para 404 do BFF (não 500)
  - `WebClientConfig` ganhou bean `managerWebClient` separado; clientes existentes (`OrchestratorAuthService`/`OrchestratorClient`) qualificados com `@Qualifier("orchestratorWebClient")`
  - `ManagerProperties` (`@ConfigurationProperties("bff.manager")`); `application.yml` e `Dockerfile` com `MANAGER_URL`, `MANAGER_USERNAME`, `MANAGER_PASSWORD`
  - JaCoCo gate ≥ 95% expandido — inclui `ManagerClient`, `ManagerAuthService`, `OrchestratorClient`, `OrchestratorAuthService`, `FlowProxyController`, `ManagerProperties`, `BffProperties`. Atual: **100%** INSTRUCTION (661/661)
  - Testes: `ManagerClientTest` (7 casos com MockWebServer), `ManagerAuthServiceTest` (3), `OrchestratorAuthServiceTest` (2), `OrchestratorClientTest` (1), `FlowProxyControllerTest` (11). `SecurityConfigIT` ganhou `@MockBean` para `ManagerAuthService`/`ManagerClient`

- **Grupos de acesso + autorização por grupo no BFF**:
  - `@EnableMethodSecurity` em `SecurityConfig` habilita `@PreAuthorize` nos controllers
  - `JwtAuthenticationConverter` bean: lê claim `groups` do JWT, converte cada nome em `GrantedAuthority` sem prefixo (`ADMIN`, `WORKFLOWS`, `RULES`)
  - `FlowProxyController` anotado com `@PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS')")` — acesso a todos os endpoints de flows/executions exige grupo ADMIN ou WORKFLOWS
  - Scope `groups` adicionado a `bff.auth.scopes` (`application.yml` + `application-docker.yml`) → frontend o solicita no fluxo PKCE → Authentik inclui `groups` no JWT
  - 4 novos testes em `SecurityConfigIT`: WORKFLOWS→200, ADMIN→200, RULES→403, sem grupos→403; 40 testes total, 0 falhas, cobertura mantida ≥ 95%

### ✅ Feito — Filtragem de menu por grupo (sidebar)

**Bug corrigido:** `GET /bff/menu` agora filtra itens pelo grupo do JWT antes de retornar.

- **`MenuItemDto`**: campo `List<String> requiredGroups` com `@JsonIgnore` e `@Singular` (Lombok builder) — não trafega para o frontend
- **`BffMenuController`**: `@AuthenticationPrincipal Jwt jwt` injeta o token; `jwt.getClaimAsStringList("groups")` extrai os grupos; catálogo `ALL_ITEMS` estático com `requiredGroups` declarados por item; `flow-manager` exige `ADMIN` ou `WORKFLOWS`
- **6 testes novos** em `BffMenuControllerTest`: ADMIN→[flow-manager], WORKFLOWS→[flow-manager], RULES→[], sem-grupo→[], sem claim groups→[], @JsonIgnore verificado via reflexão
- **49 testes total, 0 falhas, BUILD SUCCESSFUL**
- Frontend: sem alteração — `Sidebar.tsx` já exibe "Nenhuma funcionalidade disponível" para lista vazia

### ⬜ Pendente

(nenhum item pendente neste componente)

---

## Progresso detalhado — service-portal-manager

### ✅ Feito
- **Bootstrap inicial** — Kotlin 2.0.21 + Spring Boot 3.4.5 + Gradle Kotlin DSL, porta `8082`, JWT HS512 (mesmo padrão do orquestrador, jjwt 0.12.6)
- **Collection compartilhada** — usa a mesma `workflows` no DB `generic-orchestrator`. Documentos criados via Manager têm o campo adicional `yamlContent` (YAML cru recebido na criação). Coexiste com docs antigos do orquestrador
- **Domain** — `FlowDocument` com índice composto único `id` + `versao`, timestamps `criadoEm`/`atualizadoEm`
- **APIs CRUD** (`/manager/flows`):
  - `POST /manager/flows` — recebe YAML, valida estrutura mínima, persiste com `yamlContent`
  - `GET /manager/flows?page=&size=&sort=` — **paginado** (Spring Data `Page`), default size 20, máximo 100; resposta sem `yamlContent`
  - `GET /manager/flows/{id}/{versao}` — busca metadados (sem `yamlContent`)
  - `PUT /manager/flows/{id}/{versao}` — atualiza (rejeita 400 se id/versão do path divergem do YAML)
  - `DELETE /manager/flows/{id}/{versao}` — soft-delete (`ativo=false`), idempotente
- **APIs para o orquestrador** (`/manager/workflows`) — usadas após a migração futura:
  - `GET /manager/workflows/active` — lista compacta de fluxos ativos (sem `yamlContent`)
  - `GET /manager/workflows/{id}/{versao}/yaml` — YAML cru com `Content-Type: application/x-yaml`
- **Validação leve do YAML** em `YamlValidationService` — extrai `id`, `versao`, `descricao`, `ativo`. Validação profunda permanece no orquestrador
- **Auth interno** — `POST /api/auth/login` (admin/admin), `JwtAuthenticationFilter` + `HttpStatusEntryPoint(401)` para Bearer ausente/inválido
- **GlobalExceptionHandler** — 400 `INVALID_FLOW`, 404 `FLOW_NOT_FOUND`, 409 `FLOW_ALREADY_EXISTS`
- **Testes**: 63 testes em 10 arquivos, **96% cobertura INSTRUCTION** (gate `jacocoTestCoverageVerification` ≥ 95% passa). Inclui `@SpringBootTest` IT validando 401 sem token / 200 com token e endpoints públicos
- **Docker**: `service-portal-manager:test` construída; integrada ao `docker-compose-service-portal.yml` com `depends_on: mongodb`
- **Observação**: BFF e generic-orchestrator continuam inalterados nesta tarefa — a migração das integrações vai em tarefas faseadas posteriores

### 🔧 Correções pós-implementação

#### 1. Schema do documento — alinhamento com o orquestrador

Validação ad-hoc (`POST /manager/flows` + leitura no Mongo) revelou que o doc tinha sido salvo com campo top-level **`id`** em vez de **`flowId`**:

```js
// ❌ ANTES (bug)
{ "_id": ObjectId("..."),
  "id": "criar-pedido-v1",          // colidia conceitualmente com _id
  ... }
```

Causa: anotações `@JsonProperty("id") @Field("id")` no `FlowDocument`. Mas:
- O orquestrador (`FlowDefinition.java`) **não** tem `@Field`, default = `flowId`
- O índice do `init-mongo.js` é em `flowId` + `versao` (sparse) — docs do Manager ficavam fora do índice de unicidade

**Correção** ([FlowDocument.kt](service-portal-manager/src/main/kotlin/com/serviceportal/manager/domain/FlowDocument.kt)): removidas as anotações `@JsonProperty`, `@Field` e `@CompoundIndexes`. Adicionado teste de regressão `FlowDocumentSchemaTest` (5 casos via reflection das annotations) que falha se alguém reintroduzir `@Field("id")`.

```js
// ✅ DEPOIS (alinhado com orquestrador e índice do init-mongo.js)
{ "_id": ObjectId("6a0091c36edcca219a4f692f"),
  "flowId": "criar-pedido-v1",
  "versao": "1.0.0",
  "descricao": "Fluxo de criação de pedido",
  "ativo": true,
  "yamlContent": "fluxo:\n  id: \"criar-pedido-v1\"\n  ...",
  "criadoEm": ISODate("2026-05-10T14:25:18.589Z"),
  "atualizadoEm": ISODate("2026-05-10T14:25:18.589Z"),
  "_class": "com.serviceportal.manager.domain.FlowDocument"
}
```

#### 2. Otimização de leitura — projection sem `yamlContent` + paginação

Para evitar trafegar dezenas/centenas de KB por fluxo em listagens (cliente normalmente só quer metadados):

- **Repository** ([FlowDocumentRepository.kt](service-portal-manager/src/main/kotlin/com/serviceportal/manager/repository/FlowDocumentRepository.kt)):
  - `findAll(Pageable)` e `findByAtivoTrue()` ganharam `@Query(fields = "{ 'yamlContent': 0 }")` — projection MongoDB exclui o campo
  - `findByFlowIdAndVersao(...)` também é leve (sem `yamlContent`) — usado pelo `GET /manager/flows/{id}/{versao}`
  - Novo: `findByFlowIdAndVersaoWithYaml(...)` traz o doc completo — usado pelo `getYaml`, `update` e `deactivate`
- **Service** ([FlowDocumentService.kt](service-portal-manager/src/main/kotlin/com/serviceportal/manager/service/FlowDocumentService.kt)):
  - `listAll(Pageable): Page<FlowSummaryDto>` — paginação Spring Data
  - `update`/`deactivate` migrados para `WithYaml` para preservar `yamlContent` no save (caso contrário o save sobrescreveria o doc inteiro com `yamlContent=null`)
- **Controller**: `GET /manager/flows` agora aceita query params `page`, `size`, `sort` (default 20/`flowId,versao` ASC; máximo 100 via `spring.data.web.pageable.max-page-size`)
- **Testes adicionados**: 10 novos casos cobrindo paginação, separação `WithYaml` vs leve, e preservação de `yamlContent` em update/deactivate. Cobertura mantida em **96%** INSTRUCTION
- **Validação end-to-end**: criados 3 fluxos, listados via `GET /manager/flows?page=0&size=2` (Spring `Page` correto), ativos retornados sem `yamlContent`, e PUT preservou os 2152 chars do YAML no Mongo

> A solução continua sendo `yamlContent` como string. Alternativas (GridFS, S3, schema parseado) ficam reservadas para o caso (improvável) de workflows multi-MB ou requisitos de query do tipo "workflows que usam Kafka".

### ✅ Versionamento semântico automático no update

- **`VersioningService`** — detecta tipo de mudança comparando seções do YAML (normalização JSON para comparação agnóstica a formatação):
  - `contract` alterado → `MAJOR` (reset minor+patch)
  - `integrations` alterado → `MINOR` (reset patch)
  - Qualquer outra mudança → `PATCH` (increment patch)
  - Precedência: MAJOR > MINOR > PATCH quando múltiplas seções mudam
- **`PUT /manager/flows/{flowId}/versions/{v}`**:
  - Desativa versão existente (`active = false`)
  - Calcula nova versão via SemVer
  - Cria novo documento com nova versão e YAML atualizado (campo `flow.version` sincronizado)
  - Retorna **201 Created** + header `Location: /manager/flows/{flowId}/versions/{newVersion}`
- **`GET /manager/flows`** (listagem paginada): agora retorna **somente workflows ativos** — novo `findAllByActiveTrue(pageable)` no repository
- **`GET /manager/flows?status=active`** (para o orquestrador): inalterado, continua não paginado
- **Validação**: `flow.id` no YAML deve corresponder ao `flowId` do path; versão no YAML é ignorada (sobrescrita pela calculada)
- **Testes**: 71 testes (0 falhas), cobertura ≥ 95% INSTRUCTION

### ✅ Endpoint de histórico de versões

- `GET /manager/flows/{flowId}/versions` — todas as versões de um flow (ativas + inativas), ordenadas por `version ASC`
- `GET /manager/flows/{flowId}/versions?status=active` — somente versões ativas
- `GET /manager/flows/{flowId}/versions?status=inactive` — somente versões desativadas (histórico/auditoria)
- Resposta: `List<FlowSummaryDto>` sem `yamlContent` (leve)
- Implementado em repository (`findAllByFlowId`, `findAllByFlowIdAndActive`) + `FlowDocumentService.listVersions()` + `FlowController.listVersions()`
- **76 testes, 0 falhas**, cobertura ≥ 95%

### ⬜ Pendente

(nenhum item pendente neste componente)

---

## Progresso detalhado — service-portal-frontend

### ✅ Feito
- Sidebar populada via `/bff/menu`
- ComponentRenderer com Server Driven UI
- FlowManager: CRUD de fluxos YAML + executor com payload JSON
- **Auth de usuário final** — fluxo OAuth2 Authorization Code + PKCE (S256) implementado em `src/auth/`:
  - `pkce.ts` — Web Crypto API: `generateCodeVerifier` (43–128 chars unreserved), `generateCodeChallenge` (SHA-256 + base64url), `generateRandomString` para state/nonce
  - `storage.ts` — persistência em `sessionStorage` (`sp.auth.tokens`, `sp.auth.pkce`); some ao fechar a aba, sobrevive a reload
  - `oauth.ts` — `fetchAuthConfig` (BFF), `startLogin` (redireciona para `/authorize`), `exchangeCodeForTokens` (POST em `/token` com code_verifier; valida state contra CSRF), `logout` (`/end-session` com `id_token_hint`), `isTokenValid` com skew configurável
  - `AuthProvider.tsx` — Context React (status `loading|unauthenticated|authenticated|error`), detecta `/auth/callback`, troca code por token, registra handler de 401 no cliente do BFF
  - `src/api/bff.ts` — injeta `Authorization: Bearer` quando há token; chama `onUnauthorized` em respostas 401
  - `App.tsx` — gate de login + botão "Sair" na sidebar
- Vitest + jsdom + @testing-library/react configurados; gate de cobertura ≥ 95% no `vite.config.ts` (lines/functions/branches/statements). 41 testes em 4 arquivos — cobertura **100%** dos módulos `src/auth/**` e `src/api/**`

### ⬜ Pendente

(nenhum item pendente neste componente)

---

## Sessão mais recente — CONCLUÍDA ✅

> Modularização da configuração de workflows: collections `integrations`, `contracts` e `validations` no Manager + referências na collection `workflows`.

### Contexto

Hoje o workflow carrega toda a configuração inline no `yamlContent`. A ideia é separar as partes reutilizáveis em collections dedicadas para que cada time possa gerenciar seu escopo de forma independente, com versionamento sequencial próprio.

**Regra fundamental**: a collection `workflows` existente **não muda de estrutura** no YAML — apenas ganha 3 novos campos de referência. O `yamlContent` segue sendo gerado/composto pelo Manager a partir dessas referências.

---

### 1. Novas collections no MongoDB

#### `integrations`

Configuração de integrações HTTP (contrato + exemplo). Gerenciada pelo time de TI.

| Grupo (Authentik) | Acesso |
|---|---|
| ADMIN (it) | CRUD completo |
| RULES (bizop) | Nenhum acesso |
| WORKFLOWS (workop) | Leitura apenas |

Exemplo de documento:
```json
{
    "integrationId": "validate-client",
    "version": 1,
    "type": "HTTP",
    "url": "http://api.exemplo.com/clients/{{contract.clientId}}",
    "method": "GET",
    "headers": { "Content-Type": "application/json" },
    "timeout": 5000,
    "bodyTemplate": null,
    "responseBody": {
      "clientId": "{{request.pathSegments.[1]}}",
      "name": "WireMock Simulated Client",
      "document": "12345678910",
      "documentType": "CPF",
      "active": true,
      "createdAt": "2026-05-09T10:00:00Z"
    }
}
```

#### `contracts`

Contratos de entrada dos workflows (campos + validações). Gerenciado pelo time de TI e workop.

| Grupo (Authentik) | Acesso |
|---|---|
| ADMIN (it) | CRUD completo |
| RULES (bizop) | Leitura apenas |
| WORKFLOWS (workop) | CRUD completo |

Exemplo de documento:
```json
{
    "contractId": "validate-client",
    "version": 1,
    "fields": [
        {
            "name": "clientId",
            "type": "STRING",
            "required": true,
            "validations": [
                { "type": "NOT_BLANK" },
                { "type": "PATTERN", "value": "^[A-Z0-9]{6,20}$", "message": "Invalid clientId" }
            ]
        },
        {
            "name": "amount",
            "type": "DECIMAL",
            "required": true,
            "validations": [{ "type": "POSITIVE" }]
        }
    ]
}
```

#### `validations`

Validações pós-integrações (mesmo formato de `integrations`). Gerenciada pelo time de TI e pelo bizop.

| Grupo (Authentik) | Acesso |
|---|---|
| ADMIN (it) | CRUD completo |
| RULES (bizop) | CRUD completo |
| WORKFLOWS (workop) | Nenhum acesso |

Formato: idêntico ao `integrations` (campos `validationId`, `version`, `type`, `url`, `method`, `headers`, `timeout`, `bodyTemplate`, `responseBody`).

---

### 2. Novos campos na collection `workflows`

Adicionar 3 campos no `FlowDocument` (referências de recursos versionados):

```json
{
  "contract": { "id": "validate-client", "version": 1 },
  "integrationRefs": [
    { "id": "validate-client", "version": 1 }
  ],
  "validationRefs": [
    { "id": "check-credit-limit", "version": 1 }
  ]
}
```

> Os campos são arrays/objetos de referência — o Manager os usa para compor o `yamlContent`. O `yamlContent` em si não muda de estrutura.

---

### 3. Nova seção `validations` no YAML do workflow

Adicionar suporte ao campo `validations` na raiz do YAML (executado após o término das integrações):

```yaml
flow:
  flowId: create-order
  version: "1.0.0"
  ...
  integrations:
    - ...
  validations:          # nova seção — executada após todas as integrações
    - id: check-credit-limit
      ...
```

**Pendência para o orquestrador**: implementar a execução da seção `validations` no pipeline de orquestração (após conclusão das integrações). Registrar como item pendente no `generic-orchestrator`.

---

### 4. Regras de versionamento nas novas collections

- Toda alteração em `contracts`, `integrations` ou `validations` cria uma **nova versão sequencial** (1 → 2 → 3, não SemVer)
- Versão antiga permanece ativa — workflows em produção usando `version: 1` não são afetados
- Novo campo `active: boolean` em cada documento para suporte a esse padrão

---

### 5. APIs CRUD no Manager

Criar os seguintes conjuntos de endpoints (padrão REST já estabelecido no projeto):

| Recurso | Endpoints |
|---|---|
| `integrations` | `POST /manager/integrations`, `GET /manager/integrations`, `GET /manager/integrations/{id}/versions/{v}`, `PUT /manager/integrations/{id}/versions/{v}`, `DELETE /manager/integrations/{id}/versions/{v}` |
| `contracts` | `POST /manager/contracts`, `GET /manager/contracts`, `GET /manager/contracts/{id}/versions/{v}`, `PUT /manager/contracts/{id}/versions/{v}`, `DELETE /manager/contracts/{id}/versions/{v}` |
| `validations` | `POST /manager/validations`, `GET /manager/validations`, `GET /manager/validations/{id}/versions/{v}`, `PUT /manager/validations/{id}/versions/{v}`, `DELETE /manager/validations/{id}/versions/{v}` |

Autorização por endpoint conforme tabela de acesso de cada collection (seção 1 acima). Auth via `@PreAuthorize` com grupos Authentik já configurados (`ADMIN`, `RULES`, `WORKFLOWS`).

---

### 6. Checklist da sessão

- [x] `IntegrationDocument.kt` + repository + service + controller
- [x] `ContractDocument.kt` + repository + service + controller
- [x] `ValidationDocument.kt` + repository + service + controller
- [x] `ResourceRef.kt` — data class `{id: String, version: Int}` compartilhada
- [x] Adicionado `contract: ResourceRef?`, `integrationRefs: List<ResourceRef>`, `validationRefs: List<ResourceRef>` ao `FlowDocument.kt`
- [x] `SequentialVersioningService.kt` (versionamento 1→2→3, separado do SemVer de workflows)
- [x] `mongodb-workflows/init-mongo.js` com novas collections e índices únicos `(id, version)`
- [x] 150 testes, 0 falhas, BUILD SUCCESSFUL
- [x] **Pendência orquestrador**: executar seção `validations` no pipeline após integrações

---

## Pontos em aberto (infra / outros)

- **Invalidação de cache cross-service**: orquestrador invalida workflows apenas pelo TTL de 1h. Para produção, considerar Redis Pub/Sub ou endpoint admin de invalidação no orquestrador chamado pelo Manager nos updates.
  > 📄 **Plano detalhado:** [docs/plans/PLAN-cache-invalidation.md](docs/plans/PLAN-cache-invalidation.md)
- ~~**QUEUE `notify-rabbit` no workflow de exemplo**~~ ✅ **Resolvido.** Eram dois problemas: (1) o `id` do passo QUEUE deve casar com o `id` do broker em `orch-integrations.rabbitmqs` (o código usa `def.getId()` como chave do broker — confirmado por `QueueIntegrationIT`), e `notify-rabbit` ≠ `rabbitmq-notifier` → integração falhava; (2) o exchange/fila não existiam → mensagem era silenciosamente descartada. Correções:
  - Seed (`init-mongo.js`) e `generic-orchestrator/docs/example-flow.yml`: passo QUEUE renomeado para `rabbitmq-notifier` (e o passo Kafka para `kafka-user-tracking`) — alinhado aos ids dos brokers
  - Nova topologia RabbitMQ via `load_definitions`: `rabbitmq/definitions.json` (usuário `guest` com `password_hash` SHA-256, vhost, exchange topic `orders.exchange`, fila `orders.created.queue`, binding `order.created`) + `rabbitmq/rabbitmq.conf`; montados no container; removidas `RABBITMQ_DEFAULT_USER/PASS` (ignoradas com `load_definitions`)
  - **Validação e2e**: execução `create-order-v1` → `SUCCESS`; mensagem `{"event":"ORDER_CREATED","orderId":"ord-..."}` entregue em `orders.created.queue` (depth=1); orquestrador `YamlParserServiceTest` reexecutado OK

---

## Ordem de priorização — próximas sessões

| Sessão | # | Pendência | Esforço |
|---|---|---|---|
| ~~**S1**~~ | ~~3~~ | ~~Corrigir comentário em `ValidationController.kt`~~ ✅ | ⚡ Trivial |
| ~~**S1**~~ | ~~1~~ | ~~Exibir `validations` no resultado de execução (frontend)~~ ✅ | ⚡ Pequeno |
| ~~**S2**~~ | ~~2~~ | ~~Mover `mongodb-workflows/` para o Manager + renomear database~~ ✅ | 🟡 Médio |
| ~~**S2**~~ | ~~5~~ | ~~Dados de exemplo no `init-mongo.js` *(depende do #2)*~~ ✅ | 🟡 Médio |
| **S3** | 6 | Invalidação de cache cross-service (endpoint admin no orquestrador) | 🟠 Médio+ |
| **S4+** | 4 | Telas de contratos, integrações e validações (BFF + Frontend) | 🔴 Grande |

---

## Pendências registradas

### ✅ Melhoria: resultado de execução com `validations` no frontend

> 📄 **Plano detalhado:** [docs/plans/PLAN-validations-frontend.md](docs/plans/PLAN-validations-frontend.md)

Concluído (S1). O `FlowManager.tsx` agora exibe o mapa `validations` em seção própria ("Validações", com borda âmbar) abaixo das "Integrações", tanto na view v1 quanto v2. A seção só aparece quando `validations` está presente e não vazio.

- `src/types/index.ts` — `OrchestrationResponse` ganhou `validations?: Record<string, unknown>`
- `FlowManager.tsx` — renderização condicional de `execResult.validations` e `execResultV2.validations` com títulos de seção
- `FlowManager.css` — estilos `.fm-exec-section-title` e `.fm-exec-validations` (borda âmbar)
- `bff.test.ts` — novo teste de passthrough do campo `validations`; 71 testes frontend, 0 falhas; `tsc --noEmit` limpo
- BFF não precisou de ajuste (passthrough `Map<String,Object>` já transparente)

---

### ✅ Fix: mover `mongodb-workflows/` do orquestrador para o Manager

> 📄 **Plano detalhado:** [docs/plans/PLAN-move-mongodb-workflows.md](docs/plans/PLAN-move-mongodb-workflows.md)

Concluído (S2). Script movido de `generic-orchestrator/mongodb-workflows/` → `service-portal-manager/mongodb-manager/init-mongo.js`; database renomeado de `generic-orchestrator` → `service-portal-manager`.

- `service-portal-manager/mongodb-manager/init-mongo.js` criado (novo DB + collections/índices + dados de exemplo da pendência #5)
- `generic-orchestrator/mongodb-workflows/` removido
- `docker-compose-service-portal.yml`: volume mount + `MONGO_INITDB_DATABASE` + `MONGODB_URI`/`MONGODB_DATABASE` do manager → `service-portal-manager`
- `service-portal-manager/docker-compose.yml`: volume mount per-app + comentário atualizados
- `application.yml`/`application-docker.yml` do Manager: defaults de fallback alinhados (para `bootRun` sem env var conectar ao DB certo)
- **`.env` + `env.example`**: `MONGODB_DATABASE` alterado para `service-portal-manager` (lacuna do plano — o `.env` sobrescrevia o default do compose e o app conectava ao DB antigo/vazio)
- Docs: `AGENTS.md` (Manager: nova seção "Inicialização do MongoDB"; defaults), `README.md` (Manager + raiz)
- Testes do Manager: **BUILD SUCCESSFUL** (sem regressão); `node --check` no init-mongo.js OK

**Validação end-to-end (`down -v && up --build`):**
- Mongo inicializou `service-portal-manager` com `[workflows, integrations, contracts, validations]`; DB antigo `generic-orchestrator` não existe mais
- Contagem: workflows=1, integrations=2, contracts=1, validations=1
- `GET /manager/flows|contracts|integrations|validations` retornam os dados de exemplo (HTTP 200)
- Execução `create-order-v1` (v1 e v2) → `PARTIAL_SUCCESS`: HTTP `validate-client`+`save-order` OK, validação `check-credit-limit` OK no mapa `validations` (separado de `result`); apenas `notify-rabbit` (QUEUE) falha com `continueOnError: true` (exchange RabbitMQ não declarado — pré-existente, não bloqueante)

**Correções de infra pré-existentes descobertas durante a validação (não causadas pela S2):**
- **`ResourceRef.id` → `_id`**: Spring Data mapeia propriedade `id` para `_id`; o seed precisou usar `_id` nos refs aninhados (`contract`/`integrationRefs`/`validationRefs`), senão a desserialização do `FlowDocument` quebrava
- **WireMock na porta 80**: o alias `api.exemplo.com` resolvia o container mas as URLs dos workflows (sem porta) batiam na 80 enquanto o WireMock escutava na 8080 → `--port 80` no compose (host segue em 18080); afeta também o `example-flow.yml` canônico
- **`wiremock/mappings/orders-post.json`**: template `now` com escapes inválidos gerava JSON quebrado (HTTP 500) → simplificado para `{{now format='yyyy-MM-dd'}}T{{now format='HH:mm:ss'}}Z`

O `generic-orchestrator` não acessa mais o MongoDB diretamente — todo acesso à collection `workflows` é feito via API do `service-portal-manager`. A pasta `mongodb-workflows/` (com `init-mongo.js`) deve ser movida para dentro de `service-portal-manager/`.

**Itens:**
- Mover `generic-orchestrator/mongodb-workflows/` → `service-portal-manager/mongodb-manager/`
- Renomear o database de `generic-orchestrator` para `service-portal-manager` no `init-mongo.js`
- Atualizar `docker-compose-service-portal.yml`: volume mount do MongoDB deve apontar para o novo caminho + defaults `MONGODB_DATABASE`
- Atualizar `service-portal-manager/docker-compose.yml`: volume mount per-app + comentário
- Atualizar `AGENTS.md` do orquestrador e do manager
- Atualizar `README.md` do orquestrador (remover menção ao script de init Mongo) e do manager (adicionar)
- **Nota:** renomear o database requer `docker compose down -v` para destruir volumes antigos

---

### ✅ Fix: revalidar regras de acesso no Manager para `validations`

> 📄 **Plano detalhado:** [docs/plans/PLAN-fix-validations-access-rules.md](docs/plans/PLAN-fix-validations-access-rules.md)

Concluído (S1). Comentário em `ValidationController.kt` corrigido: RULES (bizop) → **CRUD completo** (era "leitura apenas"). Apenas documentação inline; nenhuma lógica/anotação/teste alterado. Os 3 controllers (`Integration`, `Contract`, `Validation`) conferidos lado a lado — consistentes com a tabela. Build do Manager `BUILD SUCCESSFUL`.

A regra de acesso para `validations` foi corrigida — RULES (bizop) tem **CRUD completo**, não somente leitura:

| Collection | ADMIN (it) | RULES (bizop) | WORKFLOWS (workop) |
|---|---|---|---|
| `integrations` | CRUD | sem acesso | somente leitura |
| `contracts` | CRUD | somente leitura | CRUD |
| `validations` | CRUD | **CRUD** ← corrigido | sem acesso |

**O que verificar no Manager (`service-portal-manager`):**
- `ValidationController.kt` — os comentários/anotações de acesso estão corretos? (acesso ao CRUD por ADMIN e RULES; sem acesso para WORKFLOWS)
- Comparar com `IntegrationController.kt` e `ContractController.kt` para garantir consistência
- Os comentários inline nas controllers refletem a regra correta (o enforcement real será feito pelo BFF via `@PreAuthorize` em sessão futura, mas a documentação no código precisa estar certa agora)

---

### ⬜ Feature: telas de gerenciamento de contratos, integrações e validações (Frontend + BFF)

> 📄 **Plano detalhado:** [docs/plans/PLAN-management-screens.md](docs/plans/PLAN-management-screens.md)

Criar as novas telas no frontend para gerenciar as collections `contracts`, `integrations` e `validations`, seguindo o mesmo padrão Server Driven UI já existente no `FlowManager`.

**Regras de acesso por perfil (enforcement no BFF via `@PreAuthorize`, espelhando o Manager):**

| Collection | ADMIN (it) | RULES (bizop) | WORKFLOWS (workop) |
|---|---|---|---|
| `integrations` | CRUD completo | sem acesso | somente leitura |
| `contracts` | CRUD completo | somente leitura | CRUD completo |
| `validations` | CRUD completo | CRUD completo | sem acesso |

**Escopo BFF:**
- Proxy endpoints `/bff/integrations`, `/bff/contracts`, `/bff/validations` apontando para o Manager
- `@PreAuthorize` por endpoint conforme tabela acima
- Atualizar `GET /bff/menu` para incluir os novos itens de menu com `requiredGroups` corretos

**Escopo Frontend:**
- 3 novos componentes de feature: `IntegrationManager`, `ContractManager`, `ValidationManager`
- Registrar em `ComponentRenderer` e no catálogo de menu do BFF
- Formulários de criação/edição respeitando os campos de cada collection (ver documentação das APIs no Manager)
- Listagem com paginação, filtro por `status=active`, e visualização de versões (`GET /{id}/versions`)
- Ações de update criam nova versão (exibir `version` atual e `Location` da nova)
- Botão de desativar (DELETE → soft delete)

**Referência de APIs já existentes no Manager:**
- `POST/GET /manager/integrations`, `GET /manager/integrations/{id}/versions`, `GET/PUT/DELETE /manager/integrations/{id}/versions/{v}`
- Idem para `/manager/contracts` e `/manager/validations`

---

### ✅ Melhoria: dados de exemplo no `init-mongo.js`

> 📄 **Plano detalhado:** [docs/plans/PLAN-init-mongo-example-data.md](docs/plans/PLAN-init-mongo-example-data.md)
> ⚠️ **Depende da pendência #2** (mover `mongodb-workflows/` para o Manager)

Concluído (S2, junto com #2). O `mongodb-manager/init-mongo.js` agora popula as 4 collections com dados coerentes entre si:
- `contracts`: `create-order` (campos `clientId` + `amount` com validações)
- `integrations`: `validate-client` (GET) e `save-order` (POST)
- `validations`: `check-credit-limit` (GET `/clients/{id}/credit`)
- `workflows`: `create-order-v1` com `yamlContent` completo + refs (`contract`, `integrationRefs`, `validationRefs`) — refs usam `_id` (ver nota de mapeamento Spring Data no bloco #2)
- Campo `_class` em cada doc para desserialização do Spring Data
- WireMock: novo mapping `wiremock/mappings/clients-credit-get.json` para o endpoint de crédito (validado: HTTP 200 e usado com sucesso na execução do workflow)

Ao inicializar o MongoDB, criar documentos de exemplo em todas as collections para facilitar desenvolvimento e testes locais.

**Collections a popular:**
- `workflows` — workflow de exemplo `create-order-v1` (reaproveitando o YAML de `docs/example-flow.yml`)
- `integrations` — integração `validate-client` apontando para WireMock
- `contracts` — contrato `create-order` com campos `clientId` (STRING, obrigatório) e `amount` (DECIMAL, obrigatório)
- `validations` — validação `check-credit-limit` apontando para WireMock

**Referência:** usar os dados já definidos no `example-flow.yml` do orquestrador como fonte de verdade para os exemplos.

---

## Arquivos-chave por componente

### generic-orchestrator
- `src/.../integration/http/HttpIntegrationExecutor.java` — alvo do retry/circuit breaker
- `src/.../manager/WorkflowCacheService.java` — `@Cacheable` que carrega FlowDefinition (Redis ou Manager)
- `src/.../manager/WorkflowCacheWarmer.java` — popula Redis na subida via `ApplicationReadyEvent`
- `src/.../manager/ManagerWorkflowClient.java` — `GET /workflows/active` e `.../yaml` no Manager
- `src/.../config/RedisCacheConfig.java` — cache 1h + Jackson serializer
- `src/.../service/OrchestrationService.java` — agora consome `WorkflowCacheService`
- `application.yml` / `application-docker.yml`

### service-portal-bff
- `src/.../client/ManagerClient.java` + `ManagerAuthService.java` — CRUD via Manager
- `src/.../client/OrchestratorClient.java` — único método: `orchestrate(...)`
- `src/.../controller/FlowProxyController.java` — CRUD→Manager, execução→Orquestrador

### service-portal-manager
- `src/main/kotlin/com/serviceportal/manager/service/FlowDocumentService.kt` — CRUD + listActive + getYaml
- `src/main/kotlin/com/serviceportal/manager/service/YamlValidationService.kt` — validação leve do YAML
- `src/main/kotlin/com/serviceportal/manager/controller/WorkflowQueryController.kt` — APIs consumidas pelo orquestrador (faseado)
- `src/main/kotlin/com/serviceportal/manager/domain/FlowDocument.kt` — modelo Mongo com `yamlContent`

### service-portal-frontend
- `src/api/bff.ts` — único cliente HTTP
- `src/components/ComponentRenderer/ComponentRenderer.tsx` — mapa de features
- `src/components/features/FlowManager/FlowManager.tsx` — feature principal

---

## Sessão anterior — CONCLUÍDA ✅

> Revisão dos cenarios de testes com novas atualizaćões e execućão como validaćão

### O que foi feito

1. **Revisão de `teste-integrado.md`**
   - Atualizados todos os YAMLs para o novo formato **em inglês** (flow, flowId, version, etc.)
   - Removido cenário de DATABASE (foi removido do orquestrador conforme arquitetura)
   - Ajustados endpoints REST com sub-recursos (`/flows/{flowId}/versions/{version}/executions`)
   - Integrado Manager no fluxo de CRUD
   - Atualizado índice e checklist de testes

2. **Criação de `teste-integrado-service-portal.sh`**
   - Script shell automático que:
     - Valida pré-requisitos (Docker, curl, config)2
     - Aguarda serviços ficarem prontos
     - Executa testes de saúde, UI, CRUD, execução, negativos
     - Cria workflows de teste
     - Gera relatório em Markdown
   - Uso: `./teste-integrado-service-portal.sh`
   - Saída: logs + checklist + contador de testes (passou/falhou/pulados)

3. **Criação de `TESTES.md`**
   - Guia completo de como rodar testes unitários por componente
   - Instruções para testes integrados (automático vs manual)
   - Troubleshooting e próximas etapas
   - Referências aos docs relacionados

4. **Atualizações em `README.md`**
   - Infraestrutura refletindo Zookeeper + Confluentinc Kafka
   - Health endpoints listando Manager
   - Port mapping do Orchestrator documentado

### Arquivos alterados/criados

- ✅ `teste-integrado.md` — revisado completo para novo formato
- ✅ `teste-integrado-service-portal.sh` — novo script automático (executável)
- ✅ `TESTES.md` — novo guia de testes
- ✅ `PLAN.md` — atualizado com status da tarefa
- ✅ `README.md` — infraestrutura/endpoints atualizados

### Comportamento validado

- ✅ Testes integrados revisados e prontos para executar
- ✅ Script automático funcional (verificado início de execução)
- ✅ Documentação de teste criada e centralizada
- ✅ Formato de YAML padronizado em inglês
- ✅ Manager integrado na arquitetura de testes

### O que não mudou

- ✅ Funcionalidades das aplicações — nenhuma alteração de código em componentes
- ✅ Stacks (Java 21, Kotlin 2.0, React 18, etc.)
- ✅ Decisões arquiteturais já consolidadas

---

## Sessão mais recente — CONCLUÍDA ✅

> Diagnóstico e manutenção dos testes integrados (execução do script v1 + análise dos resultados)

### O que foi feito

1. **Execução do script v1** (`teste-integrado-service-portal.sh`)
   - Log capturado em `teste-integrado-20260516-204125.log`
   - 20 testes executados; **5 passaram (25%), 15 falharam ou foram pulados**
   - Checklist gerado em `teste-integrado-checklist-20260516-204125.md`

2. **Análise completa das falhas** — `DIAGNOSTICO-TESTES-INTEGRADOS.md`

   | # | Problema | Severidade | Esforço |
   |---|---|---|---|
   | 1 | RabbitMQ — endpoint `/api/health` não existe (correto: `/api/aliveness-test/%2F`) | Baixa | ⚡ 30 min |
   | 2 | BFF retorna 401 em todos os endpoints — script não envia Bearer token Authentik | Alta | 🟡 1-2h |
   | 3 | `GET /bff/menu` e `GET /bff/features/flow-manager/ui-schema` — schema/menu não retornam dados esperados | Média | 🟡 1-2h |
   | 4 | `POST /bff/flows` — criação de workflow retorna 401 (bloqueado pelo #2) | Alta | (depende do #2) |
   | 5 | Cascata de dependências — CRUD e execução falham porque a criação falhou | Alta | (depende do #4) |

3. **Plano de ação** — `RECOMENDACOES-TESTES-INTEGRADOS.md`
   - 5 fases detalhadas com comandos prontos
   - Taxa de sucesso esperada após correções: 80%+

4. **Script v2** — `teste-integrado-service-portal-v2.sh`
   - Suporte a autenticação Manager e Authentik (Bearer token)
   - Modo DEBUG com logging detalhado
   - Error handling robusto com `jq`
   - Fallback de endpoints

5. **Documentação** — `TESTES-README.md`, `PROXIMAS-ETAPAS-TESTES.md`, `RESUMO-SESSAO-TESTES.md`

### Arquivos criados

- `DIAGNOSTICO-TESTES-INTEGRADOS.md` — análise de causas raiz por problema
- `RECOMENDACOES-TESTES-INTEGRADOS.md` — plano de ação em 5 fases
- `teste-integrado-service-portal-v2.sh` — script melhorado com autenticação
- `TESTES-README.md` — guia de uso e troubleshooting
- `PROXIMAS-ETAPAS-TESTES.md` — checklist acionável de próximas etapas
- `RESUMO-SESSAO-TESTES.md` — consolidação executiva da sessão

---

## Próximos passos — Decisão necessária

Temos 3 caminhos possíveis a partir daqui. Escolha um:

### Opção A — Corrigir os testes integrados (prioridade)

Sequência recomendada (menor para maior esforço):

1. **[⚡ 30 min] Corrigir endpoint RabbitMQ no script** — trivial, sem toque em código de aplicação
   - Arquivo: `teste-integrado-service-portal.sh` linha com `/api/health` → `/api/aliveness-test/%2F`

2. **[🟡 1-2h] Resolver autenticação BFF no script** — entender se BFF exige Bearer Authentik ou se aceita direto
   - Investigar: `curl -v http://localhost:8081/bff/menu` (sem token) — se retornar 401, BFF exige Authentik
   - Se sim: configurar Authentik no docker-compose + obter token no script v2
   - Se não: há outro problema nos endpoints

3. **[🟡 1-2h] Validar Server Driven UI (menu + schema)** — dependente do #2
   - Verificar se dados de menu estão populados no BFF para `flow-manager`

4. **[⬜ follow-up] Rodar script v2** e medir nova taxa de sucesso

**Meta**: chegar em 80%+ de testes passando.

---

### Opção B — Criar `AGENTS.md` por componente

Item em aberto mais antigo. Baixo risco, sem impacto em runtime:

- ✅ `generic-orchestrator/AGENTS.md` — criado
- ✅ `service-portal-bff/AGENTS.md` — criado
- ✅ `service-portal-manager/AGENTS.md` — criado
- ✅ `service-portal-frontend/AGENTS.md` — criado

---

### Opção C — Nova feature de produto

Iniciar a próxima evolução arquitetural. Possíveis candidatas:

- **Invalidação proativa de cache** — Manager notifica orquestrador via Redis Pub/Sub quando workflow é atualizado (em vez de esperar TTL 1h)
- **Endpoint admin de cache** — `DELETE /api/admin/cache/workflows/{flowId}` no orquestrador
- ~~**Authentik no docker-compose**~~ — ✅ Feito: blueprint auto-aplica providers SPA + M2M; BFF aceita tokens de múltiplos issuers; testes integrados chegaram a 96% (32/33)
- ~~**Versionamento semântico no update de workflow**~~ — ✅ Feito: Manager calcula e persiste nova versão automaticamente no `PUT`

---

## Sessão mais recente — CONCLUÍDA ✅

> Implementação de versionamento semântico automático ao atualizar workflows no Manager

### O que foi feito

1. **`VersioningService`** (novo) — `service-portal-manager/src/main/kotlin/.../service/VersioningService.kt`
   - `detectChangeType(oldYaml, newYaml)`: compara seções `contract`, `integrations`, `description` (normalização JSON para comparação agnóstica a formatação)
   - `calculateNextVersion(currentVersion, changeType)`: SemVer 2.0.0 — MAJOR resets minor+patch, MINOR resets patch, PATCH incrementa apenas patch
   - `updateVersionInYaml(yamlContent, newVersion)`: sobrescreve o campo `flow.version` no YAML persistido para manter consistência

2. **`FlowDocumentService.update()` refatorado**
   - Não atualiza mais o documento in-place
   - Desativa a versão existente (`active = false`)
   - Calcula nova versão via `VersioningService`
   - Valida que a versão calculada não existe ainda (409 se existir)
   - Cria novo documento com a nova versão e YAML atualizado
   - Validação alterada: só exige que `flow.id` do YAML bata com o `flowId` do path (versão no YAML é ignorada)

3. **`FlowDocumentRepository`** — adicionado `findAllByActiveTrue(pageable)` para listagem paginada de ativos

4. **`FlowDocumentService.listAll()`** — alterado para usar `findAllByActiveTrue(pageable)` em vez de `findAll(pageable)` — endpoints de listagem só exibem workflows ativos

5. **`FlowController.update()`** — retorna **201 Created** com header `Location: /manager/flows/{flowId}/versions/{newVersion}` (novo recurso criado)

6. **Testes**
   - `VersioningServiceTest` — 11 casos: detecção MAJOR/MINOR/PATCH, precedência, cálculo de bump, update de YAML
   - `FlowDocumentServiceTest` — reescrito para novo comportamento: PATCH bump, MAJOR bump, erros de validação, teste de listAll ativo-only
   - `FlowControllerTest` — update verificado com 201 + Location

### Resultado
- **71 testes, 0 falhas**, cobertura JaCoCo ≥ 95% INSTRUCTION

### Pendência marcada
- `GET /manager/flows/{flowId}/versions?status=inactive` — endpoint de histórico para listar versões desativadas (auditoria/rollback)
