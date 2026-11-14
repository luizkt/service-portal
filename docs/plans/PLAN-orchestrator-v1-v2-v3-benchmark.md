# PLAN: Orquestrador v1 / v2 / v3 — comparativo single thread × threads físicas × virtual threads

## Contexto

Hoje o `generic-orchestrator` expõe duas versões de execução:

| Versão | Modelo | Classe |
|---|---|---|
| v1 | Sequencial (1 thread da request) | `OrchestrationService` |
| v2 | Paralelo por `order` com **virtual threads** (`Executors.newVirtualThreadPerTaskExecutor()` por grupo) | `OrchestrationV2Service` |

Objetivo: ter um benchmark que compare três modelos de concorrência sobre o mesmo workflow.

## Decisões (confirmadas com o usuário)

1. **Escopo ponta a ponta**: orquestrador, BFF, frontend, k6, docs.
2. **Pool da nova v2**: `ThreadPoolExecutor` fixo, **compartilhado** (bean único) e configurável via `application.yml`.
3. **Refatoração**: extrair classe base comum para v2 e v3; só o `ExecutorService` muda. v1 não é tocada.
4. **k6**: manter baseline/load/stress e rodar as 3 versões; adicionar cenário **spike** para expor saturação do pool físico.

## Resultado final

| Versão | Modelo | Classe | Endpoint orquestrador |
|---|---|---|---|
| v1 | Sequencial (sem mudança) | `OrchestrationService` | `/api/v1/flows/{id}/versions/{v}/executions` |
| **v2 (nova)** | Paralelo por `order`, **platform threads** em pool fixo compartilhado | `OrchestrationV2Service` (reescrita) | `/api/v2/...` |
| **v3 (ex-v2)** | Paralelo por `order`, **virtual threads** (1 por tarefa) | `OrchestrationV3Service` | `/api/v3/...` |

> **Atenção (breaking change semântico):** `/api/v2` muda de significado (virtual → física). Todo consumidor que hoje chama `/api/v2` espera virtual threads, por isso a ordem das etapas abaixo renomeia **antes** de criar a nova v2, e BFF/frontend são migrados no mesmo PR/release.

## Etapas

### Etapa 1 — Orquestrador: refatoração e renomeação (`generic-orchestrator`)

Fazer em commits separados, nesta ordem, para o histórico/`git blame` ficar legível e a v2 nunca apontar para o modelo errado.

1. **Extrair base comum** `service/AbstractParallelOrchestrationService`
   - Move de `OrchestrationV2Service`: `execute`, `executePhase`, `runStep`, `build`, `applyMapping`, cópia de MDC/OTel para a thread filha.
   - Ponto de extensão único: `protected abstract ExecutorService executorForGroup()` (ou `<T> Future<T> submit(Runnable)`), mais o `versionTag()` para o log (`[v2]` / `[v3]`).
   - Cuidado com o ciclo de vida: virtual hoje usa try-with-resources (cria e fecha por grupo). Pool compartilhado **não pode ser fechado** por request → o template precisa distinguir "executor próprio por grupo" de "executor compartilhado" (ex.: base recebe `submit` e quem fecha é a subclasse).
   - Semântica a preservar (documentada no AGENTS.md): irmãos terminam antes de a falha ser relançada; grupos e validações seguintes não rodam; `continueOnError` → `PARTIAL_SUCCESS`; grupo de 1 passo roda inline.
2. **Renomear v2 → v3**: `OrchestrationV3Service extends AbstractParallelOrchestrationService`, `Executors.newVirtualThreadPerTaskExecutor()` por grupo, log `[v3]`.
3. **Nova v2**: `OrchestrationV2Service extends AbstractParallelOrchestrationService`, usa o pool compartilhado, log `[v2]`.
4. **Config do pool** `config/PlatformThreadPoolConfig` + `config/properties/OrchestratorThreadPoolProperties` (`orchestrator.platform-pool.*`):
   - `core-size`, `max-size`, `queue-capacity`, `keep-alive-seconds`, `thread-name-prefix` (`orch-v2-`).
   - Default sugerido: `core=max=200`, fila `SynchronousQueue`/limitada pequena + `CallerRunsPolicy` **ou** fila grande — **a decidir no início da etapa** (ver "Pontos em aberto"). A política precisa ser explícita e documentada: ela define o comportamento sob saturação, que é exatamente o que o benchmark quer medir.
   - Expor métricas do pool via Micrometer (`ExecutorServiceMetrics.monitor`) para o Grafana mostrar threads ativas/fila.
   - Shutdown limpo (`@Bean(destroyMethod = "shutdown")`).
5. **Controller**: `OrchestrationController` ganha `executeV3`; `executeV2` passa a usar o novo serviço; atualizar Javadocs/OpenAPI.
6. **Segurança**: confirmar que `SecurityConfig` cobre `/api/v3/**` (se a regra for `/api/**`, nada muda).

### Etapa 2 — Testes do orquestrador

- `OrchestrationV2ServiceTest` atual → **renomear para `OrchestrationV3ServiceTest`** e trocar o SUT (`OrchestrationV3Service`); ajustar logs `[v3]` se asserts dependerem disso.
- Novo `OrchestrationV2ServiceTest` cobrindo o mesmo contrato (sucesso, `sameOrderRunsInParallel`, `differentOrderRunsSequentially`, falha opcional/obrigatória em grupo paralelo, validações, flow inexistente) usando um pool real pequeno no teste.
- Testes **específicos do pool físico**:
  - paralelismo real limitado ao tamanho do pool (pool=2, grupo de 4 → no máximo 2 simultâneos);
  - comportamento sob saturação conforme a política escolhida (sem deadlock);
  - nomes de thread `orch-v2-*` (prova de que é platform thread, `!Thread.currentThread().isVirtual()`), e v3 com `isVirtual()==true`.
  - MDC/OTel propagados na thread do pool **e limpos** ao devolvê-la ao pool (pool reaproveita threads → vazamento de MDC entre requests é o risco novo que a virtual thread não tinha).
- Teste do controller/IT: v1, v2 e v3 respondem 200 com o mesmo `OrchestrationResponse` para o mesmo flow (extender `SecurityIT`/IT existente se couber).
- Meta: `./gradlew test jacocoTestCoverageVerification` verde (gate 95% não cobre os serviços, mas manter a cobertura de linhas alta).

### Etapa 3 — BFF (`service-portal-bff`)

- `OrchestratorClient`: `executeV2` passa a apontar para o novo `/api/v2`; **novo `executeV3`** → `/api/v3/...`.
- `FlowProxyController`: manter `POST .../executions` (v1), `.../executions/v2` (física) e adicionar `.../executions/v3` (virtual). Atualizar Javadoc/`@Operation` (hoje diz "Java Virtual Threads" na v2).
- Testes: `OrchestratorClientTest` (path `/api/v2` e novo `/api/v3`), `FlowProxyControllerTest` (novo caso v3; v2 delega para `executeV2`).

### Etapa 4 — Frontend (`service-portal-frontend`)

- `api/bff.ts`: `executeV3` (`/executions/v3`); `executeV2` mantém `/executions/v2` (agora física).
- `FlowManager.tsx`: botões **v1 Sequencial / v2 Threads Físicas / v3 Virtual Threads**; layout de comparação (`FlowManager.css`, hoje "v1 e v2 lado a lado") passa a 3 colunas; estado `execResultV3`/`executingV3`.
- Testes: `bff.test.ts` (caso `executeV3`, o de `executeV2` segue válido) e testes do `FlowManager` se existirem.

### Etapa 5 — Performance (k6)

Arquivos: `tests/performance/orchestrator-test.js`, `run-perf-test.sh`, `docs/performance/RESULTS-v1-vs-v2.md`.

1. `orchestrator-test.js`: `API_VERSION` aceita `v1|v2|v3`; atualizar o comentário de cabeçalho (v2 = física, v3 = virtual). Adicionar tag `version` nos checks/métricas para facilitar a comparação.
2. `run-perf-test.sh`:
   - `run_scenario` roda **v1 → v2 → v3** (loop sobre `VERSIONS=(v1 v2 v3)`), com **pausa de cooldown** (ex.: 20–30 s) e um warm-up curto antes de cada execução para o JIT/pool não enviesar a primeira versão medida.
   - Novo cenário **spike** (ex.: 150 VUs × 1 min) além de baseline (1×30s), load (20×2m), stress (50×3m). Justificativa: 50 VUs × 6 integrações = 300 tarefas simultâneas, que só passa de 200 threads se o pool for o default sugerido — garantir que pelo menos um cenário **ultrapasse** o tamanho do pool.
   - `extract_*`: hoje parseiam texto do k6; trocar por `--summary-export` JSON (mais robusto) e ler com `jq`, se disponível.
   - Relatório: tabela com 3 versões, colunas avg / p95 / reqs / erros **+ speedup vs v1** e **v3 vs v2**; seção "Interpretação" reescrita (v2 satura no pool, v3 não; v1 é o piso).
   - Renomear saída para `RESULTS-v1-v2-v3.md` (e arquivos `raw/<cenario>-<versao>.txt` já cobrem v3).
3. **Observabilidade durante o teste**: capturar CPU/memória do container do orquestrador (`docker stats --no-stream` em loop) e threads do pool via Prometheus/Grafana (métricas da Etapa 1.4) — objetivo 3 do plano k6 original (eficiência de recursos).
4. **Fixture**: confirmar que o `setup-perf-flow.sh` e o stub WireMock (~500 ms) seguem válidos; nenhuma mudança de flow esperada.
5. Executar o benchmark completo **uma vez** com a stack levantada e commitar o `RESULTS-*.md` gerado. (Regra de memória: não limpar cache do Docker; build frio só com `--no-cache`.)

### Etapa 6 — Documentação e índices

- `generic-orchestrator/AGENTS.md`: tabela de endpoints (v1/v2/v3), seção "Fluxo de execução", "Mapa" (`AbstractParallelOrchestrationService`, `PlatformThreadPoolConfig`), "Quero mudar... onde" (mudar semântica agora toca base + v1) e "Armadilhas" (MDC no pool físico; política de saturação). Usar a skill `update-agents-index` e incluir o `AGENTS.md` no mesmo commit (exigência do hook).
- `PLAN.md` (linhas 34, 111–112, 210–218 citam v2=virtual): atualizar/anotar a mudança.
- `docs/plans/PLAN-performance-test-k6.md`, `TESTES-README.md` (linhas 195–196: "Latência v1/v2"), `README.md` se citar v2, `docs/performance/RESULTS-*.md`.
- `teste-integrado-service-portal.sh`: hoje só usa v1; avaliar incluir v2 e v3 na comparação de latência que o `TESTES-README` descreve.
- BFF/frontend: atualizar README/AGENTS.md de cada repo se existirem índices.

## Ordem de execução e PRs

1. **PR 1 — orquestrador** (Etapas 1, 2, 6-parcial): refactor + v3 + nova v2 + testes. Commits separados: base → v3 (rename) → v2 nova → pool/config → testes.
2. **PR 2 — BFF + frontend** (Etapas 3 e 4). Só mergear **junto/depois** do PR 1, senão o botão "v2" chama o modelo errado.
3. **PR 3 — k6 + docs + resultados** (Etapas 5 e 6).

Branch por PR no padrão do repo (`feature/...`).

## Riscos

| Risco | Mitigação |
|---|---|
| `/api/v2` muda de semântica; clientes externos esperam virtual threads | Documentar; BFF/frontend migrados juntos; sem consumidores além do BFF encontrados no monorepo |
| Pool compartilhado + MDC: threads reaproveitadas vazam `executionId` entre requests | `finally { MDC.clear() }` (já existe) + teste dedicado |
| Deadlock por thread starvation (tarefa do pool esperando outra tarefa do mesmo pool) | Grupo de 1 passo roda inline; a request thread (Tomcat) nunca roda dentro do pool; teste de saturação |
| Benchmark enviesado (JIT, ordem de execução, cache Redis frio, WireMock) | Warm-up + cooldown, ordem fixa e, se possível, repetir 2× e usar a mediana |
| Comparação injusta se v2 e v3 divergirem em lógica | Base comum única — só o executor muda |
| 6 integrações/request × spike pode saturar o WireMock e não o orquestrador | Monitorar WireMock; se virar gargalo, subir limite de threads do stub antes do spike |
| `@InjectMocks` do teste da v2 depende do construtor | Base abstrata mantém campos por construtor; ajustar testes ao novo construtor (pool injetado) |

## Pontos em aberto (decidir durante a execução, não bloqueiam o início)

1. **Política de saturação do pool v2**: `CallerRunsPolicy` (degrada para sequencial na thread da request, sem erro), fila ilimitada (latência cresce, sem erro) ou `AbortPolicy` (5xx sob carga). Recomendação inicial: **fila limitada + `CallerRunsPolicy`** — não derruba requests e a degradação aparece nas métricas. Confirmar com o usuário antes de fixar.
2. **Tamanho default do pool** (200?) e se o valor do benchmark deve ser registrado no relatório (sim, entra na tabela "Configuração do Teste").
3. **Remover ou manter** o redirecionamento temporário `/api/v2` → virtual? Plano assume **sem** compatibilidade retroativa.

## Critérios de aceite

- `./gradlew spotlessApply test jacocoTestCoverageVerification` verde no orquestrador; testes de BFF (`./gradlew test`) e frontend (`npm test`) verdes.
- `curl` autenticado nos 3 endpoints do mesmo flow retorna `SUCCESS` com o mesmo `result`; logs mostram `[v1]`/`[v2]`/`[v3]` e threads `orch-v2-*` apenas na v2.
- `./tests/performance/run-perf-test.sh` roda v1, v2, v3 em baseline/load/stress/spike e gera `RESULTS-v1-v2-v3.md` com speedups e configuração do pool.
- Baseline esperado: v1 ≈ 3000 ms; v2 ≈ v3 ≈ 500 ms. Sob stress/spike, v2 deve degradar ao saturar o pool e v3 não (se não ocorrer, registrar e investigar — gargalo pode estar no `block()` do WebClient em `HttpIntegrationExecutor` ou no WireMock).
- `AGENTS.md` atualizado no mesmo commit da mudança de produção.

---

## Decisões finais dos pontos em aberto (2026-11-14)

- Saturação do pool v2: fila limitada (200) + `CallerRunsPolicy`. Pool em 200 threads. Sem retrocompatibilidade de `/api/v2`.

## Achados da 1ª bateria

- O WireMock (`--verbose`, `fixedDelay` bloqueando thread do Jetty, journal ilimitado) limitava o stub a ~40 req/s e distorceu os resultados. Corrigido em `docker-compose-service-portal.yml`: `--async-response-enabled=true`, `--async-response-threads=200`, `--max-request-journal-entries=1000`, sem `--verbose`. Medido: 500 ms estáveis a ~260 req/s com 300 clientes. A 1ª bateria **não vale** para conclusões; a 2ª (WireMock corrigido) é a referência.
- O parser de erros do `run-perf-test.sh` (sem `jq`) lia `n/a`; corrigido.

## TAREFA PENDENTE — cenário `heavy` (executar isolado após a 2ª bateria)

**Motivo:** v2 (pool físico 200 + fila 200) e v3 (virtual) empatam em baseline/load/stress porque raramente há > 200 chamadas simultâneas bloqueadas. O `heavy` força esse regime para evidenciar a diferença.

**Escopo:**
1. Stub novo no WireMock: `/slow2/{id}` com `fixedDelayMilliseconds: 2000` (`wiremock/mappings/slow2-get.json`).
2. Flow novo `perf-heavy-flow` (v1.0.0) no Manager: 20 integrações HTTP no MESMO `order` apontando para `/slow2` (estender `tests/performance/setup-perf-flow.sh` ou criar `setup-heavy-flow.sh`).
3. `orchestrator-test.js`: `FLOW_ID` já é parametrizável; permitir `SLEEP` (0 no heavy) e `payload` configurável se necessário.
4. `run-perf-test.sh`: cenário `heavy` (50 VUs, `sleep` 0, ~2 min), rodando **somente v2 e v3** por padrão (`--scenario heavy --versions v2,v3`); v1 opcional (20 × 2 s = 40 s por request).
5. Coletar `orchestrator_platform_pool_caller_runs_total`, `executor_active_threads`/`executor_queued_tasks` (Prometheus) e CPU/memória do container; incluir no relatório.
6. Variante opcional: mesmo cenário com pool reduzido (`PLATFORM_POOL_CORE_SIZE=50`, `PLATFORM_POOL_MAX_SIZE=50`) para mostrar a saturação com menos carga.
7. **Acrescentar** os resultados ao `RESULTS-v1-v2-v3.md` (seção "Cenário heavy"), sem sobrescrever a bateria principal.

**Resultado esperado:** v3 ≈ 2 s por request; v2 degrada (fila + caller-runs) quando as chamadas simultâneas passam de ~400 (200 do pool + 200 da fila).

**Pré-condição:** 2ª bateria concluída e conclusões geradas. Não mexer na stack durante a execução.

## TAREFAS PENDENTES gerais

- Subir BFF e frontend (`up -d --no-build bff frontend`; authentik já está healthy após reset de senha) e validar `/bff/flows/.../executions/v3` e a UI com 3 colunas.
- Corrigir a referência a `teste-integrado-service-portal-v3.sh` (inexistente) em `TESTES-README.md`.
- Decidir commits/PRs (3 PRs previstos) e se `docs/performance/raw/` entra no repositório.
