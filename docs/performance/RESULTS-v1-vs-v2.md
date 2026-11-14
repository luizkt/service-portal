# Resultados de Performance — Orquestrador v1 vs v2

> Gerado em: 2026-11-08 17:37:48 | Host: 192.168.0.72 | Perfil de performance: ligado

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | `perf-test-flow` |
| Integrações | 6 × HTTP (mesmo `order: 1`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo — Java Virtual Threads por grupo de `order` |
| Ferramenta | k6 (Docker `grafana/k6:latest`) |
| Rede Docker | `service-portal_portal` |
| Circuit breaker | slow-call-duration-threshold elevado por `docker-compose.perf.yml` |
| Stub WireMock | pool de 400 threads e resposta assíncrona (`docker-compose.perf.yml`) |

## Resultados

`SUCCESS` é a fração de respostas com `"status":"SUCCESS"` no corpo (limiar do k6: acima de 99%).
O orquestrador responde HTTP 200 mesmo quando o fluxo falha, então `Erros` (transporte) não basta.
Um cenário com `SUCCESS` baixo mede respostas de erro rápidas e **não** vale como medida de capacidade.

`Resultado`: `ok` cumpre SUCCESS ≥ 99% e p95 ≤ 8 s; `saturado` terminou, mas fora desses limites (esperado no stress, que procura o ponto de saturação); `FALHOU` violou os limiares do cenário (stress: SUCCESS > 80% e p95 < 30 s).

| Cenário | Versão | Latência avg | Latência P95 | Total reqs | Erros | SUCCESS | Resultado |
|---|---|---|---|---|---|---|---|
| baseline | v1 | 2.81s | 3.21s | 10 | 0.00% | 100.00% | ok |
| baseline | v2 | 513.51ms | 543.5ms | 31 | 0.00% | 100.00% | ok |
| load | v1 | 3.05s | 3.08s | 681 | 0.00% | 100.00% | ok |
| load | v2 | 512.05ms | 532.44ms | 2381 | 0.00% | 100.00% | ok |
| stress | v1 | 3.04s | 3.06s | 2551 | 0.00% | 100.00% | ok |
| stress | v2 | 510.6ms | 526.65ms | 8911 | 0.00% | 100.00% | ok |

### Speedup do v2 sobre o v1 (latência média)

| Cenário | v1 avg | v2 avg | Speedup |
|---|---|---|---|
| baseline | 2.81s | 513.51ms | 5.5× |
| load | 3.05s | 512.05ms | 6.0× |
| stress | 3.04s | 510.6ms | 6.0× |

## Análise

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 paralelo   | ~500 ms   | Todas as 6 do mesmo `order` disparam juntas |

**Speedup esperado: ~6×** para workflows com 6 integrações de I/O-bound no mesmo passo.

### Interpretação

- **Baseline (1 VU)**: confirma o speedup mínimo sem contenção de recursos.
- **Load (20 VUs)**: avalia se o pool de conexões do WebClient/Netty sustenta a paralelização.
- **Stress (50 VUs)**: identifica o ponto de saturação onde v2 começa a convergir com v1 por esgotamento de threads ou conexões.

### Logs brutos

Os logs completos de cada execução k6 estão em `docs/performance/raw/`:

```
baseline-v1.txt
baseline-v2.txt
load-v1.txt
load-v2.txt
stress-v1.txt
stress-v2.txt
```

## Como reproduzir

```bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Executar todos os cenários (aplica e restaura o perfil de performance sozinho)
./tests/performance/run-perf-test.sh

# Cenário específico (sem recriar o workflow)
./tests/performance/run-perf-test.sh --skip-setup --scenario load

# Medir com a configuração padrão do circuit breaker
./tests/performance/run-perf-test.sh --no-perf-profile
```
