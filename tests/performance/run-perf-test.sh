#!/bin/bash
# Executa o benchmark de performance do generic-orchestrator (v1 vs v2).
#
# Fluxo:
#   1. Cria o perf-test-flow no Manager (via setup-perf-flow.sh)
#   2. Roda k6 nos cenários baseline / load / stress para v1 e v2
#   3. Salva logs brutos em docs/performance/raw/
#   4. Gera relatório Markdown em docs/performance/RESULTS-v1-vs-v2.md
#
# Pré-requisitos:
#   • docker compose up -d (todos os serviços healthy)
#   • Docker com acesso à imagem grafana/k6
#
# Uso:
#   ./tests/performance/run-perf-test.sh [--skip-setup] [--scenario baseline|load|stress|all]
#
# Exemplos:
#   ./tests/performance/run-perf-test.sh
#   ./tests/performance/run-perf-test.sh --scenario load
#   ./tests/performance/run-perf-test.sh --skip-setup --scenario stress

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RAW_DIR="${REPO_ROOT}/docs/performance/raw"
RESULTS_FILE="${REPO_ROOT}/docs/performance/RESULTS-v1-vs-v2.md"
NETWORK="service-portal_portal"
K6_IMAGE="grafana/k6:latest"

SKIP_SETUP=false
SCENARIO="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-setup) SKIP_SETUP=true; shift ;;
        --scenario)   SCENARIO="$2"; shift 2 ;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
done

mkdir -p "${RAW_DIR}"

# ── Helpers ─────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

run_k6() {
    local version="$1"   # v1 | v2
    local vus="$2"
    local duration="$3"
    local label="$4"
    local out="${RAW_DIR}/${label}-${version}.txt"

    log "k6 ${label} — API_VERSION=${version} VUS=${vus} DURATION=${duration}"

    docker run --rm \
        --network "${NETWORK}" \
        -v "${SCRIPT_DIR}:/scripts:ro" \
        -e API_VERSION="${version}" \
        -e VUS="${vus}" \
        -e DURATION="${duration}" \
        "${K6_IMAGE}" run /scripts/orchestrator-test.js \
        2>&1 | tee "${out}"

    log "Resultado salvo em ${out}"
}

extract_metric() {
    # Extrai P95 ou avg de um arquivo de log k6
    local file="$1"
    local metric="$2"   # p\(95\) | avg
    grep -oE "${metric}=[0-9.]+(ms|s|µs)" "${file}" 2>/dev/null | tail -1 | grep -oE '[0-9.]+[a-zµ]+' || echo "n/a"
}

extract_throughput() {
    local file="$1"
    grep -oE 'http_reqs\s+[0-9]+' "${file}" 2>/dev/null | grep -oE '[0-9]+$' || echo "n/a"
}

extract_errors() {
    local file="$1"
    grep -oE 'http_req_failed\s+[0-9.]+%' "${file}" 2>/dev/null | grep -oE '[0-9.]+%$' || echo "n/a"
}

# ── Setup ────────────────────────────────────────────────────────────────────

if [[ "${SKIP_SETUP}" == false ]]; then
    log "Criando/verificando perf-test-flow no Manager…"
    "${SCRIPT_DIR}/setup-perf-flow.sh"
fi

# ── Execução dos cenários ────────────────────────────────────────────────────

run_scenario() {
    local name="$1"; local vus="$2"; local duration="$3"
    [[ "${SCENARIO}" == "all" || "${SCENARIO}" == "${name}" ]] || return 0

    log "=== Cenário: ${name} (${vus} VUs × ${duration}) ==="
    run_k6 "v1" "${vus}" "${duration}" "${name}"
    run_k6 "v2" "${vus}" "${duration}" "${name}"
}

run_scenario "baseline" 1  "30s"
run_scenario "load"     20 "2m"
run_scenario "stress"   50 "3m"

# ── Geração do relatório ─────────────────────────────────────────────────────

log "Gerando relatório em ${RESULTS_FILE}…"

RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(hostname)"

collect_row() {
    local label="$1" version="$2"
    local file="${RAW_DIR}/${label}-${version}.txt"
    [[ -f "${file}" ]] || { echo "| ${label} | ${version} | — | — | — | — |"; return; }
    local p95;   p95="$(extract_metric "${file}" 'p(95)')"
    local avg;   avg="$(extract_metric "${file}" 'avg')"
    local reqs;  reqs="$(extract_throughput "${file}")"
    local errs;  errs="$(extract_errors "${file}")"
    echo "| ${label} | ${version} | ${avg} | ${p95} | ${reqs} | ${errs} |"
}

{
cat <<HEADER
# Resultados de Performance — Orquestrador v1 vs v2

> Gerado em: ${RUN_DATE} | Host: ${HOSTNAME}

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | \`perf-test-flow\` |
| Integrações | 6 × HTTP (mesmo \`order: 1\`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo — Java Virtual Threads por grupo de \`order\` |
| Ferramenta | k6 (Docker \`${K6_IMAGE}\`) |
| Rede Docker | \`${NETWORK}\` |

## Resultados

| Cenário | Versão | Latência avg | Latência P95 | Total reqs | Erros |
|---|---|---|---|---|---|
HEADER

collect_row "baseline" "v1"
collect_row "baseline" "v2"
collect_row "load"     "v1"
collect_row "load"     "v2"
collect_row "stress"   "v1"
collect_row "stress"   "v2"

cat <<ANALYSIS

## Análise

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 paralelo   | ~500 ms   | Todas as 6 do mesmo \`order\` disparam juntas |

**Speedup esperado: ~6×** para workflows com 6 integrações de I/O-bound no mesmo passo.

### Interpretação

- **Baseline (1 VU)**: confirma o speedup mínimo sem contenção de recursos.
- **Load (20 VUs)**: avalia se o pool de conexões do WebClient/Netty sustenta a paralelização.
- **Stress (50 VUs)**: identifica o ponto de saturação onde v2 começa a convergir com v1 por esgotamento de threads ou conexões.

### Logs brutos

Os logs completos de cada execução k6 estão em \`docs/performance/raw/\`:

\`\`\`
$(ls "${RAW_DIR}"/*.txt 2>/dev/null | xargs -I{} basename {} || echo "(nenhum log encontrado)")
\`\`\`

## Como reproduzir

\`\`\`bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Executar todos os cenários
./tests/performance/run-perf-test.sh

# Cenário específico (sem recriar o workflow)
./tests/performance/run-perf-test.sh --skip-setup --scenario load
\`\`\`
ANALYSIS
} > "${RESULTS_FILE}"

log "✅ Relatório gerado: ${RESULTS_FILE}"
log "✅ Benchmark concluído."
