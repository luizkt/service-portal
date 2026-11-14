#!/bin/bash
# Executa o benchmark de performance do generic-orchestrator (v1 x v2 x v3).
#
#   v1 = sequencial | v2 = threads físicas (pool fixo) | v3 = virtual threads
#
# Fluxo:
#   1. Cria o perf-test-flow no Manager (via setup-perf-flow.sh)
#   2. Para cada cenário e cada versão: warm-up curto + k6 medido + cooldown
#   3. Salva logs (.txt) e summary (.json) em docs/performance/raw/
#   4. Gera docs/performance/RESULTS-v1-v2-v3.md
#
# Pré-requisitos:
#   • docker compose up -d (todos os serviços healthy)
#   • Docker com acesso à imagem grafana/k6
#   • jq (opcional; sem ele usa fallback com grep/sed)
#
# Uso:
#   ./tests/performance/run-perf-test.sh [opções]
#
# Opções:
#   --skip-setup            não cria o perf-test-flow
#   --scenario LISTA        baseline|load|stress|spike|all, ou lista separada
#                           por vírgula (ex.: load,spike)         [all]
#   --versions LISTA        lista de versões, ex.: v2,v3          [v1,v2,v3]
#   --warmup DURACAO        warm-up antes de cada medição, 0 desliga [15s]
#   --cooldown SEGUNDOS     pausa entre execuções                 [20]
#   --repeats N             repetições por cenário×versão; o relatório usa a
#                           MEDIANA. Ordem v1→v2→v3 intercalada por repetição;
#                           raw em <cenario>-<versao>-r<N>.{txt,json,stats} [2]
#   --no-stats              desliga a coleta de docker stats
#   --stats-interval SEG    intervalo do docker stats             [5]
#   --no-restart            NÃO reinicia o orquestrador antes de cada execução.
#                           Por padrão, antes do warm-up e de cada execução medida
#                           roda `docker restart ${ORCH_CONTAINER}`, espera healthy e
#                           aguarda CPU ociosa (<10% em 2 amostras seguidas de
#                           docker stats, timeout 120s). Isso zera o estado do circuit
#                           breaker (por id de integração) e descarta requests
#                           pendentes da rodada anterior, evitando contaminação.
#   --relaxed-breaker       (default) recria o orquestrador UMA vez no início com o
#   --no-relaxed-breaker    override tests/performance/compose.perf.override.yml, que
#                           define slow-call-duration-threshold=3000 ms (default da
#                           app: 800 ms; o stub responde em ~500 ms e, sob carga, o
#                           breaker abriria por 30 s e derrubaria os flows). Assim o
#                           benchmark mede concorrência, não o ajuste do breaker.
#                           --no-relaxed-breaker não aplica o override (e não o remove).
#
# Circuit breaker relaxado — aplicar/remover manualmente:
#   variável: ORCHINTEGRATIONS_CIRCUITBREAKERCONFIGURATION_SLOWCALLDURATIONTHRESHOLD=3000
#   aplicar:  docker compose -f docker-compose-service-portal.yml \
#               -f tests/performance/compose.perf.override.yml up -d --no-build orchestrator
#   remover:  docker compose -f docker-compose-service-portal.yml up -d --no-build orchestrator
#   ATENÇÃO: ao final o runner NÃO reverte; a stack fica com o override até você remover.
#
# Métrica de negócio: o orquestrador devolve HTTP 200 mesmo com flow FAILED no corpo;
# por isso o k6 exporta workflow_success (HTTP 200 E "status":"SUCCESS"), mostrado como
# "Sucesso (flows)". Latência só é comparável quando Sucesso = 100%.
#
# Variáveis de ambiente: ORCH_CONTAINER (portal-orchestrator), NETWORK,
# K6_IMAGE, COMPOSE_PROJECT (service-portal), COMPOSE_ENV_FILE (caminho do .env quando rodar de um worktree sem .env), IDLE_CPU_MAX (10, % de CPU para
# considerar ocioso), IDLE_TIMEOUT (120, s), POOL_CORE/POOL_MAX/POOL_QUEUE/POOL_POLICY (informativo no
# relatório; default 200/200/ver application.yml/CallerRunsPolicy),
# POOL_METRIC_NOTE (nome da métrica Micrometer do pool v2, opcional).
#
# Exemplos:
#   ./tests/performance/run-perf-test.sh
#   ./tests/performance/run-perf-test.sh --skip-setup --scenario spike --versions v2,v3
#   ./tests/performance/run-perf-test.sh --scenario load,stress --cooldown 30

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RAW_DIR="${REPO_ROOT}/docs/performance/raw"
RESULTS_FILE="${REPO_ROOT}/docs/performance/RESULTS-v1-v2-v3.md"
NETWORK="${NETWORK:-service-portal_portal}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:latest}"
ORCH_CONTAINER="${ORCH_CONTAINER:-portal-orchestrator}"

POOL_CORE="${POOL_CORE:-200}"
POOL_MAX="${POOL_MAX:-200}"
POOL_QUEUE="${POOL_QUEUE:-limitada (ver orchestrator.platform-pool.queue-capacity)}"
POOL_POLICY="${POOL_POLICY:-CallerRunsPolicy}"
POOL_METRIC_NOTE="${POOL_METRIC_NOTE:-}"

SKIP_SETUP=false
SCENARIOS="all"
VERSIONS_CSV="v1,v2,v3"
WARMUP="15s"
COOLDOWN=20
REPEATS=2
STATS=true
STATS_INTERVAL=5
RESTART=true
RELAXED_BREAKER=true
COMPOSE_PROJECT="${COMPOSE_PROJECT:-service-portal}"
IDLE_CPU_MAX="${IDLE_CPU_MAX:-10}"
IDLE_TIMEOUT="${IDLE_TIMEOUT:-120}"
BREAKER_ENV_VAR="ORCHINTEGRATIONS_CIRCUITBREAKERCONFIGURATION_SLOWCALLDURATIONTHRESHOLD"
BREAKER_OVERRIDE_FILE="${SCRIPT_DIR}/compose.perf.override.yml"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-setup)     SKIP_SETUP=true; shift ;;
        --scenario)       SCENARIOS="$2"; shift 2 ;;
        --versions)       VERSIONS_CSV="$2"; shift 2 ;;
        --warmup)         WARMUP="$2"; shift 2 ;;
        --cooldown)       COOLDOWN="$2"; shift 2 ;;
        --repeats)        REPEATS="$2"; shift 2 ;;
        --no-stats)       STATS=false; shift ;;
        --stats-interval) STATS_INTERVAL="$2"; shift 2 ;;
        --no-restart)     RESTART=false; shift ;;
        --relaxed-breaker)    RELAXED_BREAKER=true; shift ;;
        --no-relaxed-breaker) RELAXED_BREAKER=false; shift ;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
done

[[ "${REPEATS}" =~ ^[1-9][0-9]*$ ]] || { echo "--repeats inválido: ${REPEATS}"; exit 1; }
IFS=',' read -r -a VERSIONS <<< "${VERSIONS_CSV}"
for v in "${VERSIONS[@]}"; do
    [[ "$v" =~ ^v[123]$ ]] || { echo "Versão inválida: $v (use v1, v2, v3)"; exit 1; }
done

# Definição dos cenários: nome|VUs|duração
SCENARIO_DEFS=("baseline|1|30s" "load|20|2m" "stress|50|3m" "spike|150|1m")

scenario_selected() {
    [[ "${SCENARIOS}" == "all" ]] && return 0
    [[ ",${SCENARIOS}," == *",$1,"* ]]
}

mkdir -p "${RAW_DIR}"

HAS_JQ=false
command -v jq >/dev/null 2>&1 && HAS_JQ=true

# ── Helpers ─────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Espera o container do orquestrador ficar healthy (timeout em segundos)
wait_healthy() {
    local timeout="${1:-180}" waited=0 st
    while (( waited < timeout )); do
        st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${ORCH_CONTAINER}" 2>/dev/null || echo missing)"
        [[ "${st}" == "healthy" || "${st}" == "running" ]] && return 0
        sleep 3; waited=$(( waited + 3 ))
    done
    log "AVISO: ${ORCH_CONTAINER} não ficou healthy em ${timeout}s (status: ${st:-?})"
    return 1
}

# Espera CPU ociosa: 2 amostras consecutivas de docker stats < IDLE_CPU_MAX %
wait_idle() {
    local waited=0 ok=0 cpu
    while (( waited < IDLE_TIMEOUT )); do
        cpu="$(docker stats --no-stream --format '{{.CPUPerc}}' "${ORCH_CONTAINER}" 2>/dev/null | tr -d '%' || true)"
        if [[ -n "${cpu}" ]] && awk -v c="${cpu}" -v m="${IDLE_CPU_MAX}" 'BEGIN{exit !(c+0 < m+0)}'; then
            ok=$(( ok + 1 )); (( ok >= 2 )) && return 0
        else
            ok=0
        fi
        sleep 2; waited=$(( waited + 3 ))
    done
    log "AVISO: CPU do ${ORCH_CONTAINER} não ficou < ${IDLE_CPU_MAX}% em ${IDLE_TIMEOUT}s — seguindo"
    return 0
}

# Reinicia o orquestrador (estado limpo do circuit breaker, sem requests pendentes)
restart_orchestrator() {
    [[ "${RESTART}" == true ]] || return 0
    log "reiniciando ${ORCH_CONTAINER} (estado limpo)"
    docker restart "${ORCH_CONTAINER}" >/dev/null
    wait_healthy 180 || true
    wait_idle
}

compose_cmd() {
    ( cd "${REPO_ROOT}" && docker compose -p "${COMPOSE_PROJECT}" ${COMPOSE_ENV_FILE:+--env-file "${COMPOSE_ENV_FILE}"} -f docker-compose-service-portal.yml "$@" )
}

# Recria o orquestrador com o override do breaker (uma vez, no início)
apply_relaxed_breaker() {
    [[ "${RELAXED_BREAKER}" == true ]] || return 0
    log "aplicando override do circuit breaker (${BREAKER_ENV_VAR}=3000) e recriando o orquestrador"
    compose_cmd -f "${BREAKER_OVERRIDE_FILE}" up -d --no-build orchestrator
    wait_healthy 240 || true
    wait_idle
}

# Executa k6. $5 = "measure" (gera log/json) ou "warmup" (descarta saída).
run_k6() {
    local version="$1" vus="$2" duration="$3" label="$4" mode="$5"
    # label = <cenario>-<versao>-r<N>
    local out="${RAW_DIR}/${label}.txt"
    local summary="${label}.json"
    local wvus=$(( vus > 10 ? 10 : vus ))

    if [[ "${mode}" == "warmup" ]]; then
        log "warm-up ${label} — VUS=${wvus} DURATION=${duration}"
        docker run --rm --network "${NETWORK}" \
            -v "${SCRIPT_DIR}:/scripts:ro" \
            -e API_VERSION="${version}" \
            -e VUS="${wvus}" \
            -e DURATION="${duration}" \
            "${K6_IMAGE}" run --quiet /scripts/orchestrator-test.js >/dev/null 2>&1 || true
        return 0
    fi

    log "k6 ${label} — API_VERSION=${version} VUS=${vus} DURATION=${duration}"
    rm -f "${RAW_DIR:?}/${summary:?}"

    # thresholds podem falhar (exit 99) sob saturação: isso é dado, não erro do script
    docker run --rm --network "${NETWORK}" \
        --user "$(id -u):$(id -g)" \
        -v "${SCRIPT_DIR}:/scripts:ro" \
        -v "${RAW_DIR}:/out" \
        -e API_VERSION="${version}" \
        -e VUS="${vus}" \
        -e DURATION="${duration}" \
        "${K6_IMAGE}" run --summary-export "/out/${summary}" /scripts/orchestrator-test.js \
        2>&1 | tee "${out}" || log "k6 terminou com status != 0 (thresholds?) — seguindo"

    log "Resultado salvo em ${out}"
}

# ── Coleta de docker stats ───────────────────────────────────────────────────

STATS_PID=""

start_stats() {
    local file="$1"
    [[ "${STATS}" == true ]] || return 0
    docker inspect "${ORCH_CONTAINER}" >/dev/null 2>&1 || { log "Container ${ORCH_CONTAINER} não encontrado — sem docker stats"; return 0; }
    : > "${file}"
    (
        while true; do
            docker stats --no-stream --format '{{.CPUPerc}};{{.MemUsage}}' "${ORCH_CONTAINER}" >> "${file}" 2>/dev/null || true
            sleep "${STATS_INTERVAL}"
        done
    ) &
    STATS_PID=$!
}

stop_stats() {
    if [[ -n "${STATS_PID}" ]]; then
        kill "${STATS_PID}" 2>/dev/null || true
        wait "${STATS_PID}" 2>/dev/null || true
        STATS_PID=""
    fi
}
trap stop_stats EXIT

# Converte "123.4MiB" / "1.2GiB" / "800kB" em MiB
to_mib() {
    awk -v v="$1" 'BEGIN{
        n=v+0; u=v; gsub(/[0-9.]/,"",u)
        if(u=="GiB")n*=1024; else if(u=="KiB"||u=="kB")n/=1024; else if(u=="B")n/=1048576
        printf "%.0f", n }'
}

# Saída: "cpu_avg% cpu_max% mem_max_MiB" ou "n/a n/a n/a"
stats_summary() {
    local file="$1"
    [[ -s "${file}" ]] || { echo "n/a n/a n/a"; return; }
    local cpu_avg cpu_max mem_max=0 mem usage
    read -r cpu_avg cpu_max < <(cut -d';' -f1 "${file}" | tr -d '%' | \
        awk 'NF{s+=$1;n++; if($1>m)m=$1} END{ if(n) printf "%.0f %.0f\n", s/n, m; else print "n/a n/a" }')
    while IFS=';' read -r _ usage; do
        mem="$(to_mib "$(echo "${usage}" | awk '{print $1}')")"
        (( mem > mem_max )) && mem_max="${mem}"
    done < "${file}"
    echo "${cpu_avg}% ${cpu_max}% ${mem_max}"
}

# ── Parsing do --summary-export (jq ou fallback grep/sed) ────────────────────

# Aceita formato legado (campos planos) e novo (dentro de "values")
json_trend() {   # arquivo métrica campo → valor numérico (ms) ou vazio
    local file="$1" metric="$2" field="$3"
    [[ -s "${file}" ]] || return 0
    if [[ "${HAS_JQ}" == true ]]; then
        jq -r --arg m "${metric}" --arg f "${field}" \
            '.metrics[$m] | (.[$f] // .values[$f]) // empty' "${file}" 2>/dev/null || true
    else
        tr -d ' \n\t' < "${file}" | sed -n "s/.*\"${metric}\":{\([^}]*\)}.*/\1/p" | \
            tr ',' '\n' | grep -F "\"${field}\":" | head -1 | sed 's/.*://' || true
    fi
}

json_count() {   # http_reqs
    local file="$1"
    [[ -s "${file}" ]] || return 0
    if [[ "${HAS_JQ}" == true ]]; then
        jq -r '.metrics.http_reqs | (.count // .values.count) // empty' "${file}" 2>/dev/null || true
    else
        tr -d ' \n\t' < "${file}" | sed -n 's/.*"http_reqs":{\([^}]*\)}.*/\1/p' | \
            tr ',' '\n' | grep -F '"count":' | head -1 | sed 's/.*://' || true
    fi
}

json_fail_rate() {   # http_req_failed → fração 0..1
    local file="$1"
    [[ -s "${file}" ]] || return 0
    if [[ "${HAS_JQ}" == true ]]; then
        jq -r '.metrics.http_req_failed | (.value // .values.rate) // empty' "${file}" 2>/dev/null || true
    else
        # "value" vem depois do objeto aninhado "thresholds" ({...}), então não dá para
        # cortar no primeiro "}": lê a partir do bloco e pega o primeiro value/rate.
        tr -d ' \n\t' < "${file}" | grep -o '"http_req_failed":{.*' | \
            grep -oE '"(value|rate)":[0-9.eE+-]+' | head -1 | sed 's/.*://' || true
    fi
}

json_success_rate() {   # workflow_success → fração 0..1 (vazio se a métrica não existe)
    local file="$1"
    [[ -s "${file}" ]] || return 0
    if [[ "${HAS_JQ}" == true ]]; then
        jq -r '.metrics.workflow_success | (.value // .values.rate) // empty' "${file}" 2>/dev/null || true
    else
        tr -d ' \n\t' < "${file}" | grep -o '"workflow_success":{.*' | \
            grep -oE '"(value|rate)":[0-9.eE+-]+' | head -1 | sed 's/.*://' || true
    fi
}

fmt_ms() { if [[ -n "${1:-}" ]]; then awk -v v="$1" 'BEGIN{printf "%.0f ms", v}'; else echo "n/a"; fi; }
fmt_pct() { if [[ -n "${1:-}" ]]; then awk -v v="$1" 'BEGIN{printf "%.2f%%", v*100}'; else echo "n/a"; fi; }

# razão a/b com "×"; n/a se faltar dado
ratio() {
    local a="${1:-}" b="${2:-}"
    [[ -n "${a}" && -n "${b}" ]] || { echo "n/a"; return; }
    awk -v a="${a}" -v b="${b}" 'BEGIN{ if(b+0>0) printf "%.2f×", a/b; else print "n/a" }'
}

# ── Setup ────────────────────────────────────────────────────────────────────

if [[ "${SKIP_SETUP}" == false ]]; then
    log "Criando/verificando perf-test-flow no Manager…"
    "${SCRIPT_DIR}/setup-perf-flow.sh"
fi

if [[ "${RELAXED_BREAKER}" == true ]]; then apply_relaxed_breaker; fi

# ── Execução dos cenários ────────────────────────────────────────────────────

run_scenario() {
    local name="$1" vus="$2" duration="$3"
    scenario_selected "${name}" || return 0

    log "=== Cenário: ${name} (${vus} VUs × ${duration}) — versões: ${VERSIONS[*]} × ${REPEATS} repetição(ões) ==="
    # Remove raw de execuções anteriores deste cenário/versões (evita misturar repetições antigas)
    local v rep label first=true
    for v in "${VERSIONS[@]}"; do
        find "${RAW_DIR}" -maxdepth 1 -name "${name}-${v}-r*" -delete
    done
    # Repetição no laço externo: v1→v2→v3, depois de novo v1→v2→v3 (reduz viés de ordem/deriva)
    for (( rep = 1; rep <= REPEATS; rep++ )); do
        for v in "${VERSIONS[@]}"; do
            if [[ "${first}" == false && "${COOLDOWN}" -gt 0 ]]; then
                log "cooldown ${COOLDOWN}s"; sleep "${COOLDOWN}"
            fi
            first=false
            label="${name}-${v}-r${rep}"
            restart_orchestrator
            if [[ "${WARMUP}" != "0" ]]; then
                run_k6 "${v}" "${vus}" "${WARMUP}" "${label}" warmup
            fi
            # o warm-up deixa o JIT quente, mas também requests/breaker; recomeça limpo
            if [[ "${WARMUP}" != "0" ]]; then restart_orchestrator; fi
            start_stats "${RAW_DIR}/${label}.stats"
            run_k6 "${v}" "${vus}" "${duration}" "${label}" measure
            stop_stats
        done
    done
    if [[ "${COOLDOWN}" -gt 0 ]]; then log "cooldown ${COOLDOWN}s"; sleep "${COOLDOWN}"; fi
    return 0
}

for def in "${SCENARIO_DEFS[@]}"; do
    IFS='|' read -r n v d <<< "${def}"
    run_scenario "${n}" "${v}" "${d}"
done

# ── Geração do relatório ─────────────────────────────────────────────────────

log "Gerando relatório em ${RESULTS_FILE}…"

RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
HOST_NAME="$(hostname)"

# avg/p95 (mediana das repetições) por cenário/versão, guardados para os speedups
declare -A AVG P95

# Mediana dos números recebidos (ignora vazios); vazio se não houver nenhum
median() {
    local vals=()
    local x
    for x in "$@"; do [[ -n "${x}" ]] && vals+=("${x}"); done
    (( ${#vals[@]} > 0 )) || return 0
    printf '%s\n' "${vals[@]}" | sort -g | awk '{a[NR]=$1} END{ if(NR%2) print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2 }'
}

# Lista os arquivos de uma extensão das repetições de cenário/versão
rep_files() {   # label version ext
    local f
    shopt -s nullglob
    for f in "${RAW_DIR}/${1}-${2}-r"*."${3}"; do echo "${f}"; done
    shopt -u nullglob
}

collect_row() {
    local label="$1" version="$2"
    local files=() f
    while IFS= read -r f; do [[ -s "${f}" ]] && files+=("${f}"); done < <(rep_files "${label}" "${version}" json)
    if (( ${#files[@]} == 0 )); then echo "| ${label} | ${version} | — | — | — | — | — | 0 |"; return; fi
    local avgs=() p95s=() reqs=() errs=() succs=()
    for f in "${files[@]}"; do
        avgs+=("$(json_trend "${f}" http_req_duration avg)")
        p95s+=("$(json_trend "${f}" http_req_duration 'p(95)')")
        reqs+=("$(json_count "${f}")")
        errs+=("$(json_fail_rate "${f}")")
        succs+=("$(json_success_rate "${f}")")
    done
    local avg p95 req err succ
    avg="$(median "${avgs[@]}")"; p95="$(median "${p95s[@]}")"
    req="$(median "${reqs[@]}")"; err="$(median "${errs[@]}")"; succ="$(median "${succs[@]}")"
    AVG["${label}-${version}"]="${avg}"
    P95["${label}-${version}"]="${p95}"
    [[ -n "${req}" ]] && req="$(awk -v v="${req}" 'BEGIN{printf "%.0f", v}')"
    echo "| ${label} | ${version} | $(fmt_ms "${avg}") | $(fmt_ms "${p95}") | ${req:-n/a} | $(fmt_pct "${err}") | $(fmt_pct "${succ}") | ${#files[@]} |"
}

speedup_row() {
    local label="$1"
    echo "| ${label} | $(ratio "${AVG[${label}-v1]:-}" "${AVG[${label}-v2]:-}") | $(ratio "${AVG[${label}-v1]:-}" "${AVG[${label}-v3]:-}") | $(ratio "${AVG[${label}-v2]:-}" "${AVG[${label}-v3]:-}") | $(ratio "${P95[${label}-v2]:-}" "${P95[${label}-v3]:-}") |"
}

stats_row() {
    local label="$1" version="$2" f
    local cas=() cms=() mms=() ca cm mm
    while IFS= read -r f; do
        [[ -s "${f}" ]] || continue
        read -r ca cm mm <<< "$(stats_summary "${f}")"
        cas+=("${ca%\%}"); cms+=("${cm%\%}"); mms+=("${mm}")
    done < <(rep_files "${label}" "${version}" stats)
    (( ${#cas[@]} > 0 )) || return 0
    echo "| ${label} | ${version} | $(median "${cas[@]}")% | $(median "${cms[@]}")% | $(median "${mms[@]}") MiB |"
}

# Cenários presentes no disco (inclui execuções anteriores com --scenario parcial)
REPORT_SCENARIOS=()
for def in "${SCENARIO_DEFS[@]}"; do
    n="${def%%|*}"
    if compgen -G "${RAW_DIR}/${n}-v*-r*.json" >/dev/null; then REPORT_SCENARIOS+=("${n}"); fi
done

{
cat <<HEADER
# Resultados de Performance — Orquestrador v1 × v2 × v3

> Gerado em: ${RUN_DATE} | Host: ${HOST_NAME}

## Configuração do Teste

| Item | Valor |
|---|---|
| Workflow | \`perf-test-flow\` |
| Integrações | 6 × HTTP (mesmo \`order: 1\`, stub WireMock ~500 ms) |
| Modelo v1 | Sequencial — 1 integração por vez |
| Modelo v2 | Paralelo por \`order\` — **threads físicas** em pool fixo compartilhado |
| Modelo v3 | Paralelo por \`order\` — **Java Virtual Threads** (1 por tarefa) |
| Pool v2 (core / max) | ${POOL_CORE} / ${POOL_MAX} (prefixo \`orch-v2-\`) |
| Pool v2 (fila) | ${POOL_QUEUE} |
| Pool v2 (saturação) | ${POOL_POLICY} |
| Métrica do pool (Micrometer) | ${POOL_METRIC_NOTE:-não informada (opcional)} |
| Versões executadas | ${VERSIONS[*]} |
| Warm-up / cooldown | ${WARMUP} / ${COOLDOWN}s |
| Repetições | ${REPEATS} por cenário×versão (mediana), ordem v1→v2→v3 intercalada por repetição |
| Reinício entre execuções | $([[ "${RESTART}" == true ]] && echo "sim — \`docker restart ${ORCH_CONTAINER}\` + healthy + CPU < ${IDLE_CPU_MAX}% antes de cada warm-up e medição" || echo "não (--no-restart): estado do breaker e requests pendentes podem contaminar") |
| Circuit breaker | $([[ "${RELAXED_BREAKER}" == true ]] && echo "**relaxado**: \`slow-call-duration-threshold\` = 3000 ms via \`${BREAKER_ENV_VAR}=3000\` (default da app: 800 ms)" || echo "default da aplicação (override não aplicado pelo runner; \`slow-call-duration-threshold\` = 800 ms salvo configuração manual)") |
| Ferramenta | k6 (Docker \`${K6_IMAGE}\`) |
| Rede Docker | \`${NETWORK}\` |

## Cenários

| Nome | VUs | Duração |
|---|---|---|
HEADER

for def in "${SCENARIO_DEFS[@]}"; do
    IFS='|' read -r n v d <<< "${def}"
    echo "| ${n} | ${v} | ${d} |"
done

cat <<TABLE_HEAD

## Resultados

Valores = **mediana** das repetições (coluna Reps); cada repetição fica em \`docs/performance/raw/<cenario>-<versao>-r<N>.*\`.

| Cenário | Versão | Latência avg | Latência P95 | Total reqs | Erros (HTTP) | Sucesso (flows) | Reps |
|---|---|---|---|---|---|---|---|
TABLE_HEAD

for s in "${REPORT_SCENARIOS[@]}"; do
    for v in v1 v2 v3; do collect_row "${s}" "${v}"; done
done

cat <<SPEED_HEAD

### Speedup (razão entre as medianas de latência avg)

| Cenário | v2 vs v1 | v3 vs v1 | v3 vs v2 (avg) | v3 vs v2 (P95) |
|---|---|---|---|---|
SPEED_HEAD

for s in "${REPORT_SCENARIOS[@]}"; do speedup_row "${s}"; done

cat <<'SPEED_NOTE'

> **A latência só é comparável quando Sucesso (flows) = 100%.** O orquestrador responde
> HTTP 200 mesmo com flow `FAILED` no corpo, então a coluna Erros (HTTP) não revela essas
> falhas; flows falhos (ex.: breaker aberto) distorcem a latência.
> Linhas com Sucesso < 100% devem ser lidas como "versão degradou", não como speedup.
>
> "v2 vs v1" e "v3 vs v1" = quantas vezes a versão é mais rápida que a v1;
> "v3 vs v2" > 1× = v3 mais rápida que a v2. "n/a" = versão não executada.
SPEED_NOTE

STATS_LINES=""
for s in "${REPORT_SCENARIOS[@]}"; do
    for v in v1 v2 v3; do STATS_LINES+="$(stats_row "${s}" "${v}")"$'\n'; done
done
if [[ -n "${STATS_LINES//[$'\n ']/}" ]]; then
cat <<STATS_HEAD

### Recursos do container \`${ORCH_CONTAINER}\` (docker stats, amostras a cada ${STATS_INTERVAL}s; mediana das repetições)

| Cenário | Versão | CPU média | CPU máx | Memória máx |
|---|---|---|---|---|
STATS_HEAD
printf '%s' "${STATS_LINES}"
fi

cat <<ANALYSIS

## Análise

### Expectativas teóricas

| Modelo | 6 steps × 500ms | Motivo |
|---|---|---|
| v1 sequencial | ~3 000 ms | Cada integração espera a anterior terminar |
| v2 threads físicas | ~500 ms | As 6 do mesmo \`order\` disparam juntas, enquanto houver thread livre no pool |
| v3 virtual threads | ~500 ms | As 6 disparam juntas; sem limite prático de threads |

### Interpretação

- **v1** é o piso: latência ≈ soma das integrações, independente do pool.
- **Baseline (1 VU)**: confirma o speedup (~6×) de v2 e v3 sem contenção.
- **Load (20 VUs)**: 20 × 6 = 120 tarefas simultâneas, abaixo do pool de ${POOL_MAX}; v2 e v3 devem ser equivalentes.
- **Stress (50 VUs)**: 50 × 6 = 300 tarefas simultâneas, acima de ${POOL_MAX} threads — a v2 começa a saturar o pool.
- **Spike (150 VUs)**: 900 tarefas simultâneas; a v2 deve degradar conforme a política de saturação (${POOL_POLICY}: execução na thread da request, perdendo paralelismo), enquanto a v3 não depende de pool.
- Se a v3 também degradar, o gargalo provavelmente está fora do modelo de threads (\`block()\` do WebClient em \`HttpIntegrationExecutor\`, limite do WireMock, CPU do host) — registrar e investigar.
- Observação: \`docker stats\` mede o container inteiro; para threads ativas/fila do pool v2 use o Grafana/Prometheus (métricas \`ExecutorServiceMetrics\`).

### Logs brutos

Os logs e summaries de cada execução k6 estão em \`docs/performance/raw/\`:

\`\`\`
$(cd "${RAW_DIR}" && ls ./*.txt ./*.json 2>/dev/null | sed 's|^\./||' || echo "(nenhum log encontrado)")
\`\`\`

## Como reproduzir

\`\`\`bash
# Subir a stack (se não estiver rodando)
docker compose -f docker-compose-service-portal.yml up -d

# Todos os cenários, v1 → v2 → v3
./tests/performance/run-perf-test.sh

# Só o spike, comparando v2 e v3, sem recriar o workflow
./tests/performance/run-perf-test.sh --skip-setup --scenario spike --versions v2,v3
\`\`\`

### Circuit breaker relaxado e reinício

$([[ "${RELAXED_BREAKER}" == true ]] && echo "Esta rodada aplicou o override \`tests/performance/compose.perf.override.yml\` (\`${BREAKER_ENV_VAR}=3000\`). **A stack ficou com o override ativo**; para remover:" || echo "O override do breaker não foi aplicado pelo runner. Para aplicar/remover manualmente:")

\`\`\`bash
# aplicar (slow-call-duration-threshold = 3000 ms)
docker compose -f docker-compose-service-portal.yml -f tests/performance/compose.perf.override.yml up -d --no-build orchestrator
# remover (volta ao default de 800 ms)
docker compose -f docker-compose-service-portal.yml up -d --no-build orchestrator
\`\`\`
ANALYSIS
} > "${RESULTS_FILE}"

log "Relatório gerado: ${RESULTS_FILE}"
log "Benchmark concluído."
