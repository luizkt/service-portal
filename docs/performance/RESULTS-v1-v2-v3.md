# Resultados de Performance — Orquestrador v1 × v2 × v3

> Gerado em: 2026-11-14 23:08:40 | Host: 192.168.0.72

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
| Métrica do pool (Micrometer) | não informada (opcional) |
| Versões executadas | v1 v2 v3 |
| Warm-up / cooldown | 15s / 20s |
| Repetições | 2 por cenário×versão (mediana), ordem v1→v2→v3 intercalada por repetição |
| Reinício entre execuções | sim — `docker restart portal-orchestrator` + healthy + CPU < 10% antes de cada warm-up e medição |
| Circuit breaker | **relaxado**: `slow-call-duration-threshold` = 3000 ms via `ORCHINTEGRATIONS_CIRCUITBREAKERCONFIGURATION_SLOWCALLDURATIONTHRESHOLD=3000` (default da app: 800 ms) |
| Ferramenta | k6 (Docker `grafana/k6:latest`) |
| Rede Docker | `service-portal_portal` |

## Cenários

| Nome | VUs | Duração |
|---|---|---|
| baseline | 1 | 30s |
| load | 20 | 2m |
| stress | 50 | 3m |
| spike | 150 | 1m |

## Resultados

Valores = **mediana** das repetições (coluna Reps); cada repetição fica em `docs/performance/raw/<cenario>-<versao>-r<N>.*`.

`Resultado`: `ok` cumpre Sucesso ≥ 99% e p95 ≤ 8 s; `saturado` terminou, mas fora desses limites (esperado no stress e no spike, que procuram a saturação); `FALHOU` violou os limiares do cenário (stress/spike: Sucesso > 80% e p95 < 30 s) e o runner sai com código 1.

| Cenário | Versão | Latência avg | Latência P95 | Total reqs | Erros (HTTP) | Sucesso (flows) | Reps | Resultado |
|---|---|---|---|---|---|---|---|---|
| baseline | v1 | 2798 ms | 3170 ms | 10 | 0.00% | 100.00% | 2 | ok |
| baseline | v2 | 522 ms | 563 ms | 30 | 0.00% | 100.00% | 2 | ok |
| baseline | v3 | 520 ms | 556 ms | 30 | 0.00% | 100.00% | 2 | ok |
| load | v1 | 3052 ms | 3135 ms | 681 | 0.00% | 100.00% | 2 | ok |
| load | v2 | 517 ms | 547 ms | 2361 | 0.00% | 100.00% | 2 | ok |
| load | v3 | 517 ms | 536 ms | 2363 | 0.00% | 100.00% | 2 | ok |
| stress | v1 | 3040 ms | 3092 ms | 2551 | 0.00% | 100.00% | 2 | ok |
| stress | v2 | 516 ms | 532 ms | 8872 | 0.00% | 100.00% | 2 | ok |
| stress | v3 | 515 ms | 533 ms | 8899 | 0.00% | 100.00% | 2 | ok |
| spike | v1 | 3068 ms | 3505 ms | 2551 | 0.00% | 100.00% | 2 | ok |
| spike | v2 | 1412 ms | 2523 ms | 4778 | 0.00% | 100.00% | 2 | ok |
| spike | v3 | 545 ms | 607 ms | 8675 | 0.00% | 100.00% | 2 | ok |

### Speedup (razão entre as medianas de latência avg)

| Cenário | v2 vs v1 | v3 vs v1 | v3 vs v2 (avg) | v3 vs v2 (P95) |
|---|---|---|---|---|
| baseline | 5.36× | 5.38× | 1.00× | 1.01× |
| load | 5.90× | 5.90× | 1.00× | 1.02× |
| stress | 5.89× | 5.91× | 1.00× | 1.00× |
| spike | 2.17× | 5.63× | 2.59× | 4.16× |

> **A latência só é comparável quando Sucesso (flows) = 100%.** O orquestrador responde
> HTTP 200 mesmo com flow `FAILED` no corpo, então a coluna Erros (HTTP) não revela essas
> falhas; flows falhos (ex.: breaker aberto) distorcem a latência.
> Linhas com Sucesso < 100% devem ser lidas como "versão degradou", não como speedup.
>
> "v2 vs v1" e "v3 vs v1" = quantas vezes a versão é mais rápida que a v1;
> "v3 vs v2" > 1× = v3 mais rápida que a v2. "n/a" = versão não executada.

### Recursos do container `portal-orchestrator` (docker stats, amostras a cada 5s; mediana das repetições)

| Cenário | Versão | CPU média | CPU máx | Memória máx |
|---|---|---|---|---|
| baseline | v1 | 7.5% | 20% | 441 MiB |
| baseline | v2 | 21% | 39% | 465 MiB |
| baseline | v3 | 22.5% | 55% | 448 MiB |
| load | v1 | 30.5% | 66.5% | 449.5 MiB |
| load | v2 | 55.5% | 142% | 482.5 MiB |
| load | v3 | 55.5% | 160% | 467 MiB |
| stress | v1 | 38.5% | 121.5% | 457 MiB |
| stress | v2 | 74.5% | 202% | 513.5 MiB |
| stress | v3 | 72.5% | 266% | 499 MiB |
| spike | v1 | 99.5% | 229.5% | 500 MiB |
| spike | v2 | 169.5% | 382.5% | 519 MiB |
| spike | v3 | 219% | 485.5% | 534 MiB |

## Análise

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 threads físicas | ~500 ms | As 6 do mesmo `order` disparam juntas, enquanto houver thread livre no pool |
| v3 virtual threads | ~500 ms | As 6 disparam juntas; sem limite prático de threads |

### Interpretação

- **v1** é o piso: latência ≈ soma das integrações, independente do pool.
- **Baseline (1 VU)**: confirma o speedup (~6×) de v2 e v3 sem contenção.
- **Load (20 VUs)**: 20 × 6 = 120 tarefas simultâneas, abaixo do pool de 200; v2 e v3 devem ser equivalentes.
- **Stress (50 VUs)**: 50 × 6 = 300 tarefas simultâneas, acima de 200 threads — a v2 começa a saturar o pool.
- **Spike (150 VUs)**: 900 tarefas simultâneas; a v2 deve degradar conforme a política de saturação (CallerRunsPolicy: execução na thread da request, perdendo paralelismo), enquanto a v3 não depende de pool.
- Se a v3 também degradar, o gargalo provavelmente está fora do modelo de threads (`block()` do WebClient em `HttpIntegrationExecutor`, limite do WireMock, CPU do host) — registrar e investigar.
- Observação: `docker stats` mede o container inteiro; para threads ativas/fila do pool v2 use o Grafana/Prometheus (métricas `ExecutorServiceMetrics`).

### Logs brutos

Os logs e summaries de cada execução k6 estão em `docs/performance/raw/`:

```
baseline-v1-r1.json
baseline-v1-r1.txt
baseline-v1-r2.json
baseline-v1-r2.txt
baseline-v1.txt
baseline-v2-r1.json
baseline-v2-r1.txt
baseline-v2-r2.json
baseline-v2-r2.txt
baseline-v2.txt
baseline-v3-r1.json
baseline-v3-r1.txt
baseline-v3-r2.json
baseline-v3-r2.txt
load-v1-r1.json
load-v1-r1.txt
load-v1-r2.json
load-v1-r2.txt
load-v1.txt
load-v2-r1.json
load-v2-r1.txt
load-v2-r2.json
load-v2-r2.txt
load-v2.txt
load-v3-r1.json
load-v3-r1.txt
load-v3-r2.json
load-v3-r2.txt
spike-v1-r1.json
spike-v1-r1.txt
spike-v1-r2.json
spike-v1-r2.txt
spike-v2-r1.json
spike-v2-r1.txt
spike-v2-r2.json
spike-v2-r2.txt
spike-v3-r1.json
spike-v3-r1.txt
spike-v3-r2.json
spike-v3-r2.txt
stress-v1-r1.json
stress-v1-r1.txt
stress-v1-r2.json
stress-v1-r2.txt
stress-v1.txt
stress-v2-r1.json
stress-v2-r1.txt
stress-v2-r2.json
stress-v2-r2.txt
stress-v2.txt
stress-v3-r1.json
stress-v3-r1.txt
stress-v3-r2.json
stress-v3-r2.txt
```

## Como reproduzir

```bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Todos os cenários, v1 → v2 → v3
./tests/performance/run-perf-test.sh

# Só o spike, comparando v2 e v3, sem recriar o workflow
./tests/performance/run-perf-test.sh --skip-setup --scenario spike --versions v2,v3
```

### Circuit breaker relaxado e reinício

Esta rodada aplicou o override `tests/performance/compose.perf.override.yml` (`ORCHINTEGRATIONS_CIRCUITBREAKERCONFIGURATION_SLOWCALLDURATIONTHRESHOLD=3000`). **A stack ficou com o override ativo**; para remover:

```bash
# aplicar (slow-call-duration-threshold = 3000 ms)
docker compose -f docker-compose-service-portal.yml -f tests/performance/compose.perf.override.yml up -d --no-build orchestrator
# remover (volta ao default de 800 ms)
docker compose -f docker-compose-service-portal.yml up -d --no-build orchestrator
```
