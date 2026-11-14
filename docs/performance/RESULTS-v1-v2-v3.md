# Resultados de Performance — Orquestrador v1 × v2 × v3

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | `perf-test-flow` |
| Integrações | 6 × HTTP (mesmo `order: 1`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo por `order` — **threads físicas** em pool fixo compartilhado |
| Modelo v3 | Paralelo por `order` — **Java Virtual Threads** (1 por tarefa) |
| Pool v2 (core / max) | 200 / 200 (prefixo `orch-v2-`) |
| Pool v2 (fila) | limitada (ver orchestrator.platform-pool.queue-capacity) |
| Pool v2 (saturação) | CallerRunsPolicy |
| Métrica do pool (Micrometer) | executor_active_threads{name="orchestrator-v2"}, executor_queued_tasks, orchestrator_platform_pool_caller_runs_total |
| Versões executadas | v1 v2 v3 |
| Warm-up / cooldown | 15s / 20s |
| Repetições | 2 por cenário×versão (mediana), ordem v1→v2→v3 intercalada por repetição |
| Ferramenta | k6 (Docker `grafana/k6:latest`) |
| Rede Docker | `service-portal_portal` |

## Cenários

| Nome | VUs | Duração |
|---|---|---|
| baseline | 1 | 30s |
| load | 20 | 2m |
| stress | 50 | 3m |
| spike | 150 | 1m |

## Metodologia (leia antes dos números)

### Sucesso (flows) e por que a latência só vale com 100%

O orquestrador responde **HTTP 200 mesmo quando o flow termina `FAILED`** (o status vem no corpo). Por isso `http_req_failed` do k6 / a coluna "Erros (HTTP)" mostra ~0% e esconde falhas; numa rodada anterior a v3 teve ~22% de flows `FAILED` no spike com 0% de erro HTTP. O k6 agora exporta a métrica `workflow_success` (true quando HTTP 200 **e** `"status":"SUCCESS"` no corpo, com tag `version`), exibida como **"Sucesso (flows)"**. A latência de uma linha só é comparável com as demais quando Sucesso = 100%; abaixo disso, a linha mede degradação, não ganho.

### Reinício entre execuções

Execuções seguidas se contaminam: o estado do circuit breaker (por id de integração, `perf-1`..`perf-6`) é compartilhado entre versões e rodadas, e requests pendentes de uma rodada atrasam a seguinte (o `setup()` do k6 chegou a estourar 60 s). O runner reinicia o orquestrador (`docker restart`), espera `healthy` e aguarda CPU ociosa (< 10% em 2 amostras do `docker stats`) antes de **cada** warm-up e de cada execução medida. Desligue com `--no-restart`.

### Circuit breaker relaxado

O breaker tem `slow-call-duration-threshold: 800` ms (janela de 10 chamadas, `slowCallRateThreshold` fixo em 100%) e o stub responde em ~500 ms: sob carga a latência passa de 800 ms, o breaker abre por 30 s e derruba os flows. Para medir concorrência e não o ajuste do breaker, o runner (default `--relaxed-breaker`) recria o orquestrador uma vez com `tests/performance/compose.perf.override.yml`, que define `ORCHINTEGRATIONS_CIRCUITBREAKERCONFIGURATION_SLOWCALLDURATIONTHRESHOLD=3000`. A stack **fica com o override** ao final. Para remover: `docker compose -f docker-compose-service-portal.yml up -d --no-build orchestrator`. Use `--no-relaxed-breaker` para não aplicá-lo.

## Resultados

Ainda não executado. Rode `./tests/performance/run-perf-test.sh` para gerar as tabelas de latência, speedup e recursos (docker stats); os brutos ficam em `docs/performance/raw/`.

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 threads físicas | ~500 ms | As 6 do mesmo `order` disparam juntas, enquanto houver thread livre no pool |
| v3 virtual threads | ~500 ms | As 6 disparam juntas; sem limite prático de threads |

## Referência: medição v1 x v2 (PR #14, 2026-11-08, Boot 4.1.2)

Medição anterior, antes do v3, com breaker relaxado e WireMock com pool folgado (100% de SUCCESS). Serve de ponto de comparação; o runner sobrescreve este arquivo com as novas medições.

| Cenário | v1 avg | v2 avg | Speedup |
|---|---|---|---|
| baseline | 2.81s | 513.51ms | 5.5× |
| load | 3.05s | 512.05ms | 6.0× |
| stress | 3.04s | 510.6ms | 6.0× |

## Como reproduzir

```bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Todos os cenários, v1 → v2 → v3
./tests/performance/run-perf-test.sh

# Só o spike, comparando v2 e v3, sem recriar o workflow
./tests/performance/run-perf-test.sh --skip-setup --scenario spike --versions v2,v3

# Com o circuit breaker padrão (800 ms), sem o override
./tests/performance/run-perf-test.sh --no-relaxed-breaker
```
