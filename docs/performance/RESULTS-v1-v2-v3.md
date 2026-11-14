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

## Resultados

Ainda não executado. Rode `./tests/performance/run-perf-test.sh` para gerar as tabelas de latência, speedup e recursos (docker stats); os brutos ficam em `docs/performance/raw/`.

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 threads físicas | ~500 ms | As 6 do mesmo `order` disparam juntas, enquanto houver thread livre no pool |
| v3 virtual threads | ~500 ms | As 6 disparam juntas; sem limite prático de threads |

## Como reproduzir

```bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Todos os cenários, v1 → v2 → v3
./tests/performance/run-perf-test.sh

# Só o spike, comparando v2 e v3, sem recriar o workflow
./tests/performance/run-perf-test.sh --skip-setup --scenario spike --versions v2,v3
```
