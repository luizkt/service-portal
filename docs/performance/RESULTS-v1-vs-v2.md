# Resultados de Performance — Orquestrador v1 vs v2

> **Ainda não executado.** Execute `./tests/performance/run-perf-test.sh` com a stack rodando para popular este arquivo.

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | `perf-test-flow` |
| Integrações | 6 × HTTP (mesmo `order: 1`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo — Java Virtual Threads por grupo de `order` |
| Ferramenta | k6 (Docker `grafana/k6:latest`) |
| Rede Docker | `service-portal_portal` |

## Cenários

| # | Nome | VUs | Duração | Objetivo |
|---|---|---|---|---|
| 1 | **baseline** | 1 | 30s | Confirmar speedup sem contenção de recursos |
| 2 | **load** | 20 | 2min | Sustentabilidade do pool de conexões WebClient/Netty |
| 3 | **stress** | 50 | 3min | Ponto de saturação — onde v2 converge para v1 |

## Expectativas Teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 paralelo   | ~500 ms   | Todas as 6 do mesmo `order` disparam juntas via Virtual Threads |

**Speedup esperado (baseline): ~6×**

## Como Executar

```bash
# 1. Subir a stack
docker compose -f docker-compose-service-portal.yml up -d

# 2. Aguardar todos os serviços ficarem healthy (verificar Portainer em http://localhost:9001)

# 3. Rodar o benchmark completo
./tests/performance/run-perf-test.sh

# 4. Cenário isolado (após primeiro setup)
./tests/performance/run-perf-test.sh --skip-setup --scenario load
```

## Resultados

*(Será sobrescrito pelo `run-perf-test.sh` após a execução)*

## Arquivos de Log Brutos

Os logs completos de cada execução k6 são salvos em `docs/performance/raw/`:
- `baseline-v1.txt` / `baseline-v2.txt`
- `load-v1.txt` / `load-v2.txt`
- `stress-v1.txt` / `stress-v2.txt`
