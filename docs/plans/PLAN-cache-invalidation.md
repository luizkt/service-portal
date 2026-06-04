# PLAN: Invalidação de cache cross-service (Orquestrador ↔ Manager)

## Contexto

O orquestrador armazena `FlowDefinition` no Redis com TTL de 1 hora. Quando o Manager atualiza ou desativa um workflow, o orquestrador não sabe — o cache fica stale por até 60 minutos.

Em desenvolvimento local isso raramente causa problemas (basta aguardar o TTL), mas é uma inconsistência arquitetural: o Manager é o dono dos dados, o orquestrador é consumidor, e hoje o consumidor não recebe notificação de mudança.

O `WorkflowCacheService` já expõe `evict(flowId, versao)` e `evictAll()` para esse uso futuro.

---

## Abordagens possíveis

| Abordagem | Vantagens | Desvantagens |
|---|---|---|
| **A) Endpoint admin no orquestrador** (recomendada) | Simples, observável, sem infra adicional | Coupling síncrono Manager → Orquestrador; falha se orquestrador estiver down |
| **B) Redis Pub/Sub** | Desacoplado, fanout para múltiplas instâncias | Mais complexo; requer tratamento de at-most-once delivery |

**Recomendação:** Opção A (endpoint admin). O ambiente já tem Redis disponível, mas Pub/Sub adiciona complexidade sem benefício real para o volume atual. Se múltiplas instâncias do orquestrador forem necessárias no futuro, migrar para B.

---

## Escopo — Opção A (Endpoint Admin)

### Orquestrador (`generic-orchestrator`)

| Arquivo | Mudança |
|---|---|
| `controller/CacheAdminController.java` | **Novo** — expõe `DELETE /api/admin/cache/workflows/{flowId}/versions/{version}` e `DELETE /api/admin/cache/workflows` |
| `manager/WorkflowCacheService.java` | Sem mudança — `evict()` e `evictAll()` já existem |
| `security/SecurityConfig.java` | Liberar endpoints `/api/admin/**` apenas para `admin` (token interno) |
| `src/main/resources/application.yml` | Sem mudança necessária |
| Testes | `CacheAdminControllerTest.java` |

### Manager (`service-portal-manager`)

| Arquivo | Mudança |
|---|---|
| `client/OrchestratorCacheClient.kt` | **Novo** — chama endpoints admin do orquestrador |
| `config/OrchestratorClientConfig.kt` | **Novo** — `WebClient` para o orquestrador + props (`orchestrator.url`, `orchestrator.admin-token`) |
| `service/FlowDocumentService.kt` | Chamar `orchestratorCacheClient.evict()` após `update()` e `deactivate()` |
| `src/main/resources/application.yml` | Adicionar `orchestrator.url` e `orchestrator.admin-token` |
| `src/main/resources/application-docker.yml` | Idem, com valores docker |
| `Dockerfile` | Adicionar env vars `ORCHESTRATOR_URL` e `ORCHESTRATOR_ADMIN_TOKEN` |
| `docker-compose-service-portal.yml` | Adicionar env vars ao serviço `manager` |
| Testes | `OrchestratorCacheClientTest.kt`, `FlowDocumentServiceTest.kt` atualizado |

---

## Implementação passo a passo

### Fase 1 — Orquestrador: endpoint admin de cache

#### `CacheAdminController.java`

```java
@RestController
@RequestMapping("/api/admin/cache")
public class CacheAdminController {

    private final WorkflowCacheService cacheService;

    // DELETE /api/admin/cache/workflows/{flowId}/versions/{version}
    @DeleteMapping("/workflows/{flowId}/versions/{version}")
    public ResponseEntity<Void> evictWorkflow(
            @PathVariable String flowId,
            @PathVariable String version) {
        cacheService.evict(flowId, version);
        return ResponseEntity.noContent().build();
    }

    // DELETE /api/admin/cache/workflows
    @DeleteMapping("/workflows")
    public ResponseEntity<Void> evictAllWorkflows() {
        cacheService.evictAll();
        return ResponseEntity.noContent().build();
    }
}
```

#### `SecurityConfig.java` — proteger `/api/admin/**` com o mesmo JWT interno

O orquestrador já tem autenticação JWT HS512 (admin/admin). Basta garantir que `/api/admin/**` exige autenticação:

```java
.authorizeHttpRequests(auth -> auth
    .requestMatchers(HttpMethod.POST, "/api/auth/**").permitAll()
    .requestMatchers("/actuator/health", "/actuator/info").permitAll()
    .anyRequest().authenticated()   // /api/admin/** fica autenticado
)
```

Nenhuma mudança necessária se `anyRequest().authenticated()` já está presente.

### Fase 2 — Manager: cliente HTTP para o orquestrador

#### `OrchestratorClientConfig.kt`

```kotlin
@Configuration
@ConfigurationProperties("orchestrator")
data class OrchestratorProperties(
    var url: String = "http://localhost:8080",
    var adminToken: String = ""
)

@Configuration
class OrchestratorClientConfig(private val props: OrchestratorProperties) {

    @Bean("orchestratorAdminWebClient")
    fun orchestratorAdminWebClient(): WebClient =
        WebClient.builder()
            .baseUrl(props.url)
            .build()
}
```

#### `OrchestratorCacheClient.kt`

```kotlin
@Component
class OrchestratorCacheClient(
    @Qualifier("orchestratorAdminWebClient") private val webClient: WebClient,
    private val authService: OrchestratorAuthService   // reutiliza o client_credentials login
) {

    fun evictWorkflow(flowId: String, version: String) {
        try {
            webClient.delete()
                .uri("/api/admin/cache/workflows/$flowId/versions/$version")
                .header(HttpHeaders.AUTHORIZATION, "Bearer ${authService.token()}")
                .retrieve()
                .toBodilessEntity()
                .block()
        } catch (ex: Exception) {
            log.warn("Failed to evict cache for $flowId/$version: ${ex.message}")
            // não propaga — falha de invalidação não deve impedir o update do Manager
        }
    }
}
```

> **Nota:** A falha de invalidação é logada como warning mas **não lança exceção** — o workflow foi atualizado com sucesso; o orquestrador vai carregar a nova versão no próximo cache miss (ou após TTL). Esse trade-off é intencional.

#### `FlowDocumentService.kt` — chamar invalidação após update e deactivate

```kotlin
// Após repository.save() no método update()
val newDoc = repository.save(newFlowDoc)
orchestratorCacheClient.evictWorkflow(flowId, currentDoc.version) // evict versão antiga
return newDoc.toSummary()

// Após repository.save() no método deactivate()
repository.save(doc)
orchestratorCacheClient.evictWorkflow(flowId, version)
```

#### `OrchestratorAuthService.kt` (novo no Manager)

O Manager precisa de um token para chamar o orquestrador. Como o orquestrador usa `POST /api/auth/tokens` com `admin/admin`, criar um `OrchestratorAuthService.kt` no Manager com o mesmo padrão do `ManagerAuthService` já existente no BFF e no orquestrador.

Alternativamente, se preferir evitar duplicação: usar um token estático hardcoded em env var (`ORCHESTRATOR_ADMIN_TOKEN`) e injetá-lo diretamente no header, sem login — o orquestrador aceita qualquer Bearer JWT válido gerado com o segredo HS512. O Manager pode usar o seu próprio JWT para chamar o orquestrador se o segredo for o mesmo (configurável via `ORCHESTRATOR_JWT_SECRET`).

#### Configuração

`application.yml` do Manager:
```yaml
orchestrator:
  url: ${ORCHESTRATOR_URL:http://localhost:8080}
  admin-username: ${ORCHESTRATOR_ADMIN_USERNAME:admin}
  admin-password: ${ORCHESTRATOR_ADMIN_PASSWORD:admin}
```

`application-docker.yml` do Manager:
```yaml
orchestrator:
  url: ${ORCHESTRATOR_URL:http://orchestrator:8080}
```

`docker-compose-service-portal.yml` — serviço `manager`:
```yaml
ORCHESTRATOR_URL: http://orchestrator:8080
```

---

## Arquivos críticos

### Orquestrador

| Arquivo | Relevância |
|---|---|
| `manager/WorkflowCacheService.java` | `evict(flowId, versao)` e `evictAll()` — já existem |
| `controller/CacheAdminController.java` | **Novo** — expõe os métodos via HTTP |
| `security/SecurityConfig.java` | Verificar se `/api/admin/**` está coberto por `anyRequest().authenticated()` |

### Manager

| Arquivo | Relevância |
|---|---|
| `service/FlowDocumentService.kt` | Pontos de inserção: após `update()` e `deactivate()` |
| `client/OrchestratorCacheClient.kt` | **Novo** — chama DELETE no orquestrador |
| `config/OrchestratorClientConfig.kt` | **Novo** — WebClient + properties |

---

## Considerações

- **Falha tolerante:** A invalidação não bloqueia o update — falha silenciosa com log warning
- **Instâncias múltiplas do orquestrador:** A abordagem A invalida apenas a instância chamada. Para múltiplas instâncias, migrar para Redis Pub/Sub (Opção B): Manager publica em canal `workflow.evict`, cada instância do orquestrador assina e chama `cacheService.evict()` ao receber mensagem
- **Rollback:** Se o Manager fizer update mas a invalidação falhar, o orquestrador ainda serve a versão antiga por até 1h. Workaround imediato: `WORKFLOWS_CACHE_TTL_SECONDS=60` (reduz TTL para 1 min em dev)

---

## Verificação

1. **Criar e cachear um workflow:**
   ```bash
   # Executar o workflow para forçar cache miss → carregamento
   curl -X POST "http://localhost:8080/api/flows/create-order-v1/versions/1.0.0/executions" \
     -H "Authorization: Bearer $ORCH_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"clientId":"ABC123","amount":150}'
   ```

2. **Atualizar o workflow via Manager:**
   ```bash
   curl -X PUT "http://localhost:8082/manager/flows/create-order-v1/versions/1.0.0" \
     -H "Authorization: Bearer $MGR_TOKEN" \
     -H "Content-Type: text/plain" \
     -d "$(cat modified-flow.yml)"
   # Retorna 201 com Location para nova versão
   ```

3. **Verificar que o cache foi invalidado no Redis:**
   ```bash
   docker exec portal-redis redis-cli keys "workflows::*"
   # A entrada workflows::create-order-v1_1.0.0 deve ter sido removida
   ```

4. **Verificar log de invalidação no Manager:**
   ```bash
   docker logs portal-manager | grep "evict"
   # Deve conter: "Evicted cache for create-order-v1/1.0.0"
   ```

5. **Executar testes do Manager:**
   ```bash
   cd service-portal-manager && ./gradlew test
   # Esperado: testes passando incluindo OrchestratorCacheClientTest
   ```

6. **Executar testes do orquestrador:**
   ```bash
   cd generic-orchestrator && ./gradlew test
   # Esperado: CacheAdminControllerTest passando
   ```
