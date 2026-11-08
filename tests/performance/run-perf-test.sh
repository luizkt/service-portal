#!/bin/bash
# Executa o benchmark de performance do generic-orchestrator (v1 vs v2).
#
# Fluxo:
#   1. Aplica o perfil de performance (docker-compose.perf.yml: circuit breaker sem abrir por
#      chamada lenta e WireMock com pool folgado) e espera ficar healthy. Ao terminar, restaura.
#   2. Cria o perf-test-flow no Manager (via setup-perf-flow.sh)
#   3. Roda k6 nos cenários baseline / load / stress para v1 e v2
#   4. Salva logs brutos em docs/performance/raw/
#   5. Gera relatório Markdown em docs/performance/RESULTS-v1-vs-v2.md
#
# O k6 falha a execução quando menos de 99% das respostas trazem "status":"SUCCESS" (limiar
# workflow_success). O script segue para os demais cenários, marca o resultado como FALHOU no
# relatório e sai com código 1 no fim.
#
# Pré-requisitos:
#   • docker compose up -d (todos os serviços healthy)
#   • Docker com acesso à imagem grafana/k6
#
# Uso:
#   ./tests/performance/run-perf-test.sh [--skip-setup] [--no-perf-profile] \
#                                        [--scenario baseline|load|stress|all]
#
# Exemplos:
#   ./tests/performance/run-perf-test.sh
#   ./tests/performance/run-perf-test.sh --scenario load
#   ./tests/performance/run-perf-test.sh --skip-setup --scenario stress
#   ./tests/performance/run-perf-test.sh --no-perf-profile   # mede com a config padrão do circuito

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RAW_DIR="${REPO_ROOT}/docs/performance/raw"
RESULTS_FILE="${REPO_ROOT}/docs/performance/RESULTS-v1-vs-v2.md"
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-service-portal}"
COMPOSE_FILE="${REPO_ROOT}/docker-compose-service-portal.yml"
PERF_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.perf.yml"
NETWORK="${COMPOSE_PROJECT}_portal"
K6_IMAGE="grafana/k6:latest"
ORCH_CONTAINER="${ORCH_CONTAINER:-portal-orchestrator}"

SKIP_SETUP=false
PERF_PROFILE=true
SCENARIO="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-setup)       SKIP_SETUP=true; shift ;;
        --no-perf-profile)  PERF_PROFILE=false; shift ;;
        --scenario)         SCENARIO="$2"; shift 2 ;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
done

mkdir -p "${RAW_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Perfil de performance do orquestrador ─────────────────────────────────────

wait_orchestrator_healthy() {
    local status="" i
    for i in $(seq 1 40); do
        status="$(docker inspect -f '{{.State.Health.Status}}' "${ORCH_CONTAINER}" 2>/dev/null || true)"
        [[ "${status}" == "healthy" ]] && return 0
        sleep 5
    done
    log "Orquestrador não ficou healthy (último estado: ${status:-desconhecido})"
    return 1
}

recreate_orchestrator() {
    # Recria WireMock e orquestrador (o perfil muda a capacidade do stub e o circuit breaker).
    # $@ = arquivos -f adicionais
    (cd "${REPO_ROOT}" && docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" "$@" \
        up -d --no-deps --force-recreate wiremock orchestrator) >/dev/null
    wait_orchestrator_healthy
}

restore_orchestrator() {
    if [[ "${PERF_PROFILE}" == true ]]; then
        log "Restaurando a configuração normal do orquestrador…"
        recreate_orchestrator || true
    fi
}

if [[ "${PERF_PROFILE}" == true ]]; then
    log "Aplicando perfil de performance no orquestrador (circuit breaker sem abrir por chamada lenta)…"
    trap restore_orchestrator EXIT
    recreate_orchestrator -f "${PERF_COMPOSE_FILE}"
else
    log "Perfil de performance desligado: o circuit breaker usa a configuração padrão do application.yml."
fi

# ── Execução ──────────────────────────────────────────────────────────────────

FAILED_RUNS=()

run_k6() {
    local version="$1"   # v1 | v2
    local vus="$2"
    local duration="$3"
    local label="$4"
    local min_success="${5:-0.99}"
    local p95_max="${6:-8000}"
    local out="${RAW_DIR}/${label}-${version}.txt"
    local rc=0

    log "k6 ${label} — API_VERSION=${version} VUS=${vus} DURATION=${duration}"
    set +e
    docker run --rm \
        --network "${NETWORK}" \
        -v "${SCRIPT_DIR}:/scripts:ro" \
        -e API_VERSION="${version}" \
        -e VUS="${vus}" \
        -e DURATION="${duration}" \
        -e MIN_SUCCESS="${min_success}" \
        -e P95_MAX_MS="${p95_max}" \
        "${K6_IMAGE}" run /scripts/orchestrator-test.js \
        2>&1 | tee "${out}"
    rc="${PIPESTATUS[0]}"
    set -e

    if [[ "${rc}" != "0" ]]; then
        log "⚠ k6 ${label}-${version} terminou com código ${rc} (limiar violado ou erro de execução)"
        FAILED_RUNS+=("${label}-${version}")
    fi
    log "Resultado salvo em ${out}"
}

# ── Extração de métricas do resumo do k6 ──────────────────────────────────────

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' "$1" | tr '\r' '\n'; }

# Linha de resumo "http_req_duration....: avg=… p(95)=…" (a primeira, sem o filtro expected_response).
duration_line() {
    strip_ansi "$1" | grep -E '^\s*http_req_duration\.+:' | head -1
}

metric_from_line() {
    # $1 = linha, $2 = chave (avg | p(95))
    local key="${2//(/\\(}"; key="${key//)/\\)}"
    echo "$1" | grep -oE "${key}=[0-9.]+(µs|ms|s)" | head -1 | cut -d= -f2
}

to_ms() {
    # converte 513.55ms | 3.08s | 36µs para milissegundos (número)
    awk -v v="$1" 'BEGIN{
        if (v ~ /µs$/) { sub(/µs$/,"",v); printf "%.2f", v/1000 }
        else if (v ~ /ms$/) { sub(/ms$/,"",v); printf "%.2f", v }
        else if (v ~ /s$/) { sub(/s$/,"",v); printf "%.2f", v*1000 }
        else print "0" }'
}

extract_reqs()    { strip_ansi "$1" | grep -E '^\s*http_reqs\.+:' | head -1 | grep -oE ':\s+[0-9]+' | grep -oE '[0-9]+' || echo "n/a"; }
extract_errors()  { strip_ansi "$1" | grep -E '^\s*http_req_failed\.+:' | head -1 | grep -oE '[0-9.]+%' | head -1 || echo "n/a"; }
extract_success() { strip_ansi "$1" | grep -E '^\s*workflow_success\.+:' | head -1 | grep -oE '[0-9.]+%' | head -1 || echo "n/a"; }

if [[ "${SKIP_SETUP}" == false ]]; then
    log "Criando/verificando perf-test-flow no Manager…"
    "${SCRIPT_DIR}/setup-perf-flow.sh"
fi

run_scenario() {
    local name="$1"; local vus="$2"; local duration="$3"
    local min_success="${4:-0.99}"; local p95_max="${5:-8000}"
    [[ "${SCENARIO}" == "all" || "${SCENARIO}" == "${name}" ]] || return 0
    log "=== Cenário: ${name} (${vus} VUs × ${duration}; SUCCESS > ${min_success}, p95 < ${p95_max} ms) ==="
    run_k6 "v1" "${vus}" "${duration}" "${name}" "${min_success}" "${p95_max}"
    run_k6 "v2" "${vus}" "${duration}" "${name}" "${min_success}" "${p95_max}"
}

run_scenario "baseline" 1  "30s"
run_scenario "load"     20 "2m"
# Stress acha a saturação: limiares frouxos; o relatório marca "saturado" quando passa dos de aceite.
run_scenario "stress"   50 "3m" 0.80 30000

# ── Relatório ─────────────────────────────────────────────────────────────────

log "Gerando relatório em ${RESULTS_FILE}…"

RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(hostname)"

run_failed() {
    local key="$1" f
    for f in "${FAILED_RUNS[@]:-}"; do [[ "${f}" == "${key}" ]] && return 0; done
    return 1
}

collect_row() {
    local label="$1" version="$2"
    local file="${RAW_DIR}/${label}-${version}.txt"
    [[ -f "${file}" ]] || { echo "| ${label} | ${version} | — | — | — | — | — | — |"; return; }
    local line avg p95 reqs errs succ result
    line="$(duration_line "${file}")"
    avg="$(metric_from_line "${line}" 'avg')"
    p95="$(metric_from_line "${line}" 'p(95)')"
    reqs="$(extract_reqs "${file}")"
    errs="$(extract_errors "${file}")"
    succ="$(extract_success "${file}")"
    if run_failed "${label}-${version}"; then
        result="FALHOU"
    else
        # Passou dos limiares do cenário; "saturado" se ficou fora dos de aceite (SUCCESS ≥ 99%, p95 ≤ 8 s).
        local succ_n p95_ms
        succ_n="$(echo "${succ}" | tr -d '%')"
        p95_ms="$(to_ms "${p95:-0}")"
        if awk -v s="${succ_n:-0}" -v p="${p95_ms}" 'BEGIN{exit !(s < 99 || p > 8000)}'; then result="saturado"; else result="ok"; fi
    fi
    echo "| ${label} | ${version} | ${avg:-n/a} | ${p95:-n/a} | ${reqs} | ${errs} | ${succ} | ${result} |"
}

collect_speedup() {
    local label="$1"
    local f1="${RAW_DIR}/${label}-v1.txt" f2="${RAW_DIR}/${label}-v2.txt"
    [[ -f "${f1}" && -f "${f2}" ]] || return 0
    local a1 a2 m1 m2
    a1="$(metric_from_line "$(duration_line "${f1}")" 'avg')"
    a2="$(metric_from_line "$(duration_line "${f2}")" 'avg')"
    [[ -n "${a1}" && -n "${a2}" ]] || return 0
    m1="$(to_ms "${a1}")"; m2="$(to_ms "${a2}")"
    awk -v l="${label}" -v a="${a1}" -v b="${a2}" -v x="${m1}" -v y="${m2}" \
        'BEGIN{ if (y > 0) printf "| %s | %s | %s | %.1f× |\n", l, a, b, x/y }'
}

{
cat <<HEADER
# Resultados de Performance — Orquestrador v1 vs v2

> Gerado em: ${RUN_DATE} | Host: ${HOSTNAME} | Perfil de performance: $([[ "${PERF_PROFILE}" == true ]] && echo "ligado" || echo "desligado")

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | \`perf-test-flow\` |
| Integrações | 6 × HTTP (mesmo \`order: 1\`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo — Java Virtual Threads por grupo de \`order\` |
| Ferramenta | k6 (Docker \`${K6_IMAGE}\`) |
| Rede Docker | \`${NETWORK}\` |
| Circuit breaker | $([[ "${PERF_PROFILE}" == true ]] && echo "slow-call-duration-threshold elevado por \`docker-compose.perf.yml\`" || echo "configuração padrão do application.yml") |
| Stub WireMock | $([[ "${PERF_PROFILE}" == true ]] && echo "pool de 400 threads e resposta assíncrona (\`docker-compose.perf.yml\`)" || echo "configuração padrão (~40 chamadas/s com o stub de 500 ms)") |

## Resultados

\`SUCCESS\` é a fração de respostas com \`"status":"SUCCESS"\` no corpo (limiar do k6: acima de 99%).
O orquestrador responde HTTP 200 mesmo quando o fluxo falha, então \`Erros\` (transporte) não basta.
Um cenário com \`SUCCESS\` baixo mede respostas de erro rápidas e **não** vale como medida de capacidade.

\`Resultado\`: \`ok\` cumpre SUCCESS ≥ 99% e p95 ≤ 8 s; \`saturado\` terminou, mas fora desses limites (esperado no stress, que procura o ponto de saturação); \`FALHOU\` violou os limiares do cenário (stress: SUCCESS > 80% e p95 < 30 s).

| Cenário | Versão | Latência avg | Latência P95 | Total reqs | Erros | SUCCESS | Resultado |
|---|---|---|---|---|---|---|---|
HEADER

collect_row "baseline" "v1"
collect_row "baseline" "v2"
collect_row "load"     "v1"
collect_row "load"     "v2"
collect_row "stress"   "v1"
collect_row "stress"   "v2"

cat <<SPEEDUP

### Speedup do v2 sobre o v1 (latência média)

| Cenário | v1 avg | v2 avg | Speedup |
|---|---|---|---|
$(collect_speedup baseline)
$(collect_speedup load)
$(collect_speedup stress)
SPEEDUP

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

# Executar todos os cenários (aplica e restaura o perfil de performance sozinho)
./tests/performance/run-perf-test.sh

# Cenário específico (sem recriar o workflow)
./tests/performance/run-perf-test.sh --skip-setup --scenario load

# Medir com a configuração padrão do circuit breaker
./tests/performance/run-perf-test.sh --no-perf-profile
\`\`\`
ANALYSIS
} > "${RESULTS_FILE}"

log "✅ Relatório gerado: ${RESULTS_FILE}"

if [[ ${#FAILED_RUNS[@]} -gt 0 ]]; then
    log "❌ Execuções que violaram limiares: ${FAILED_RUNS[*]}"
    exit 1
fi

log "✅ Benchmark concluído."
