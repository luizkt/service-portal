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

**Infraestrutura local:** MongoDB 7, **Redis 7** (cache de workflows no orquestrador), RabbitMQ 3, Kafka (Bitnami 3.7 KRaft, sem Zookeeper), LocalStack 3 (SQS), WireMock (simulador de APIs externas)
**Segurança:** JWT HS512 (jjwt 0.12.6) no orquestrador; OAuth2 Resource Server (Authentik) no BFF
**HTTP client:** Spring WebFlux WebClient (Netty)

---

## Decisões tomadas

- Padrão **Server Driven UI**: BFF controla menu e schema de UI; frontend não tem regras de negócio
- Frontend fala **somente com o BFF** — nunca diretamente com o orquestrador
- Auth BFF → Orquestrador é **server-to-server** (admin/admin), token em cache com renovação automática
- Multi-instância de Kafka e RabbitMQ configurada via `orch-integrations` no `application.yml`; match pelo campo `id`
- Profile Spring `docker` para rodar com `docker compose up`
- Sem libs de UI/state externas no frontend — `fetch` nativo + `useState/useEffect`
- `POST /api/orchestrate/{version}/{flowId}` exige `version` no path (BFF já repassa, frontend usa `v1` por padrão)
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
| Revisão dos cenarios de testes com novas atualizaćões | Raiz | ⬜ Pendente | ponto em aberto |
| Criaćão de arquivo AGENTS.md para cada aplicaćão para melhor prática | Todos | ⬜ Pendente | ponto em aberto |

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

### ⬜ Pendente

(nenhum item pendente neste componente — refactor do BFF e orquestrador para consumir o Manager são tarefas separadas)

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

## Pontos em aberto (infra / outros)

- **Authentik provider/application**: cadastrar OAuth2/OIDC Provider + Application no Authentik com slug `service-portal` e client public `service-portal-spa` (passos descritos no header do `docker-compose-service-portal.yml`)
- **Frontend e novo formato de path do BFF**: o BFF agora expõe `/bff/flows/{flowId}/{versao}` (com versão explícita). O `FlowManager` do frontend pode precisar de ajuste para passar versão em PUT/DELETE/GET — tarefa de follow-up se aparecer regressão
- **Migração de docs antigos**: documentos da collection `workflows` criados pelo orquestrador antes do Manager não têm `yamlContent`. O `getYaml` devolve 404. Backfill não escopado nesta tarefa
- **Invalidação de cache cross-service**: orquestrador invalida workflows apenas pelo TTL de 1h. Para produção, considerar Redis Pub/Sub ou endpoint admin de invalidação no orquestrador chamado pelo Manager nos updates

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

## Tarefa desta sessão

> Correção do `docker-compose.yml` (contextos de build)

**Componente alvo:**
`docker-compose-service-portal.yml`

**O que quero fazer agora:**
Vamos realizar uma validaćão no arquivo `docker-compose-service-portal.yml` para preparar o nosso ambiente de execućão com docker compose. Precisamos rodar as aplicaćões do frontend, bff, orquestrador e manager. A infra necessaria também é necessaria subir no docker compose para realizarmos testes integrados. Com o intuito dos testes precisamos garantir que teremos as configuraćões de integraćão corretas nos arquivos do docker compose, utilize as redes do docker-compose para realizar as integraćões bem como as variaveis de ambiente das aplicaćões para realizar as conexões necessarias.

**Arquivos relevantes:**
generic-orchestrator/README.md
service-portal-bff/README.md
service-portal-manager/README.md
service-portal-frontend/README.md

**Comportamento esperado:**
- Testes unitários executando com sucesso.
- Cobertura de codigo deve ser pelo menos 95%.
- Imagem docker sendo construida com sucesso.
- Atualizaćão dos README.md geral do projeto na raiz.

**O que não quero que mude:**
- As funcionalidades das aplicaćões, caso encontre algum problema me informe.
