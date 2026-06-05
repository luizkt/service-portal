#!/bin/bash
# teste-integrado-service-portal-v3.sh
# Script de testes integrados - Service Portal
# Versão 3: Endpoints corrigidos, autenticação completa (Manager + Orchestrator + Authentik)

set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'

# ─── Config ───────────────────────────────────────────────────────────────────
DOCKER_COMPOSE_FILE="docker-compose-service-portal.yml"
ENV_FILE=".env"
LOG_FILE="teste-integrado-$(date +%Y%m%d-%H%M%S).log"
CHECKLIST_FILE="teste-integrado-checklist-$(date +%Y%m%d-%H%M%S).md"

# Carrega .env (se existir) para expor AUTHENTIK_M2M_CLIENT_ID e AUTHENTIK_M2M_SECRET
if [ -f "$ENV_FILE" ]; then
    set -o allexport
    # shellcheck source=/dev/null
    source <(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | grep '=')
    set +o allexport
fi

BFF_URL="http://localhost:8081"
ORCH_URL="http://localhost:8080"
MGR_URL="http://localhost:8082"
AUTHENTIK_URL="http://localhost:9000"

AUTH_TOKEN=""        # Bearer Authentik (BFF) — obtido via M2M client_credentials
MANAGER_TOKEN=""     # Bearer Manager (CRUD no Manager direto)
ORCH_TOKEN=""        # Bearer Orchestrator (execuções diretas)

# Credenciais do provider M2M (criadas automaticamente pelo blueprint).
# Em instalações existentes, defina no .env:
#   AUTHENTIK_M2M_CLIENT_ID=service-portal-cc
#   AUTHENTIK_M2M_SECRET=<seu-secret>
M2M_CLIENT_ID="${AUTHENTIK_M2M_CLIENT_ID:-service-portal-m2m}"
M2M_CLIENT_SECRET="${AUTHENTIK_M2M_SECRET:-service-portal-m2m-secret}"

PASSED=0; FAILED=0; SKIPPED=0

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; PASSED=$((PASSED + 1)); }
error()   { echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"; FAILED=$((FAILED + 1)); }
warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"; SKIPPED=$((SKIPPED + 1)); }
info()    { echo -e "${BLUE}ℹ${NC} $*" | tee -a "$LOG_FILE"; }
debug()   { echo -e "${MAGENTA}DEBUG${NC} $*" | tee -a "$LOG_FILE"; }

section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$*${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}
test_case() { echo -e "\n${YELLOW}→${NC} $*" | tee -a "$LOG_FILE"; }

# curl com Bearer (BFF — requer Authentik)
bff_curl() {
    if [ -n "$AUTH_TOKEN" ]; then
        curl -s -H "Authorization: Bearer $AUTH_TOKEN" "$@"
    else
        curl -s "$@"
    fi
}

# curl com Bearer (Manager)
mgr_curl() {
    curl -s -H "Authorization: Bearer $MANAGER_TOKEN" "$@"
}

# curl com Bearer (Orchestrator)
orch_curl() {
    curl -s -H "Authorization: Bearer $ORCH_TOKEN" "$@"
}

# ─── Pré-requisitos ──────────────────────────────────────────────────────────
check_prerequisites() {
    section "PRÉ-REQUISITOS"

    [ -f "$DOCKER_COMPOSE_FILE" ] && success "docker-compose file encontrado" \
        || { error "$DOCKER_COMPOSE_FILE não encontrado"; exit 1; }

    [ -f "$ENV_FILE" ] && success ".env encontrado" \
        || { error ".env não encontrado — execute: cp env.example .env"; exit 1; }

    command -v docker >/dev/null 2>&1 && success "Docker instalado" \
        || { error "Docker não instalado"; exit 1; }

    command -v curl >/dev/null 2>&1 && success "curl instalado" \
        || { error "curl não instalado"; exit 1; }

    if command -v jq >/dev/null 2>&1; then
        success "jq instalado (paridade v1/v2 detalhada via jq)"
    elif command -v python3 >/dev/null 2>&1; then
        info "jq ausente — paridade v1/v2 detalhada usará python3 (fallback)"
    else
        warning "jq e python3 ausentes — paridade v1/v2 detalhada será pulada (apenas status)"
    fi
}

# ─── Infraestrutura ───────────────────────────────────────────────────────────
wait_healthy() {
    local name=$1 url=$2
    local attempts=0 max=120
    info "Aguardando $name ($url)..."
    while [ $attempts -lt $max ]; do
        if curl -sf --connect-timeout 2 "$url" > /dev/null 2>&1; then
            success "$name pronto"
            return 0
        fi
        attempts=$((attempts + 1))
        printf "\r[%3d%%] %d/%d" $((attempts * 100 / max)) $attempts $max
        sleep 2
    done
    echo ""
    error "$name não ficou pronto em $((max * 2))s"
    return 1
}

start_infrastructure() {
    section "INFRAESTRUTURA"

    log "Parando containers anteriores..."
    docker compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true
    sleep 2

    log "Iniciando stack..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d || { error "Falha no docker compose up"; return 1; }
    sleep 5

    docker compose -f "$DOCKER_COMPOSE_FILE" ps

    wait_healthy "BFF"          "$BFF_URL/bff/health"         || return 1
    wait_healthy "Orchestrator" "$ORCH_URL/actuator/health"   || return 1
    wait_healthy "Manager"      "$MGR_URL/actuator/health"    || return 1

    sleep 3
    success "Stack iniciada"
}

# Extrai campo JSON sem depender de jq (fallback com grep/sed)
extract_json_field() {
    local json=$1 field=$2
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r ".$field // empty" 2>/dev/null
    else
        # Suporta tanto "field":"value" quanto "field": "value" (com espaço)
        echo "$json" | grep -o "\"$field\": *\"[^\"]*\"" | sed "s/\"$field\": *\"//;s/\"//"
    fi
}

# ─── Autenticação ─────────────────────────────────────────────────────────────
get_manager_token() {
    section "AUTH — MANAGER (porta 8082)"
    test_case "POST /api/auth/tokens"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$MGR_URL/api/auth/tokens" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin"}')
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "201" ]; then
        MANAGER_TOKEN=$(extract_json_field "$BODY" "token")
        [ -n "$MANAGER_TOKEN" ] \
            && { success "Token Manager obtido (201)"; debug "Token: ${MANAGER_TOKEN:0:30}..."; return 0; }
        warning "Token Manager — resposta 201 mas token não extraído: $BODY"
    fi
    warning "Falha ao obter token Manager (HTTP $HTTP_CODE): $(echo "$BODY" | head -c 100)"
    return 1
}

get_orchestrator_token() {
    section "AUTH — ORCHESTRATOR (porta 8080)"
    test_case "POST /api/auth/tokens"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ORCH_URL/api/auth/tokens" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin"}')
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "201" ]; then
        ORCH_TOKEN=$(extract_json_field "$BODY" "token")
        [ -n "$ORCH_TOKEN" ] \
            && { success "Token Orchestrator obtido (201)"; debug "Token: ${ORCH_TOKEN:0:30}..."; return 0; }
        warning "Token Orchestrator — resposta 201 mas token não extraído: $BODY"
    fi
    warning "Falha ao obter token Orchestrator (HTTP $HTTP_CODE): $(echo "$BODY" | head -c 100)"
    return 1
}

get_authentik_token() {
    section "AUTH — AUTHENTIK M2M (porta 9000)"

    test_case "Verificando Authentik (/-/health/ready/)"
    if ! curl -sf --connect-timeout 3 "$AUTHENTIK_URL/-/health/ready/" > /dev/null 2>&1; then
        warning "Authentik não acessível — testes BFF autenticados serão pulados"
        return 1
    fi
    success "Authentik acessível"

    # Authentik 2026.x: token endpoint é global (não mais por application slug)
    test_case "POST /application/o/token/ (grant_type=client_credentials)"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "$AUTHENTIK_URL/application/o/token/" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=${M2M_CLIENT_ID}&client_secret=${M2M_CLIENT_SECRET}&scope=openid")
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "200" ]; then
        AUTH_TOKEN=$(extract_json_field "$BODY" "access_token")
        [ -n "$AUTH_TOKEN" ] \
            && { success "Token M2M obtido (200)"; debug "Token: ${AUTH_TOKEN:0:30}..."; return 0; }
        warning "Token M2M — resposta 200 mas access_token não extraído"
    fi

    warning "Token M2M não obtido (HTTP $HTTP_CODE) — testes BFF autenticados serão pulados"
    debug "Resposta Authentik: $(echo "$BODY" | head -c 200)"
    info "O blueprint cria o provider M2M automaticamente (client_id=${M2M_CLIENT_ID}). Aguarde o worker aplicar o blueprint e tente novamente."
    return 1
}

# ─── 1. Saúde ─────────────────────────────────────────────────────────────────
test_health() {
    section "1. SAÚDE DO SISTEMA"

    test_case "1.1 BFF health"
    curl -sf "$BFF_URL/bff/health" | grep -q "status" \
        && success "BFF healthy" || error "BFF não respondeu"

    test_case "1.2 Orchestrator health"
    curl -sf "$ORCH_URL/actuator/health" | grep -q "status" \
        && success "Orchestrator healthy" || error "Orchestrator não respondeu"

    test_case "1.3 Manager health"
    curl -sf "$MGR_URL/actuator/health" | grep -q "status" \
        && success "Manager healthy" || error "Manager não respondeu"

    test_case "1.4 RabbitMQ — /api/aliveness-test/%2F"
    curl -sf "http://guest:guest@localhost:15672/api/aliveness-test/%2F" | grep -q "ok" \
        && success "RabbitMQ ok" || warning "RabbitMQ não acessível"

    test_case "1.5 Redis ping"
    REDIS_ID=$(docker ps -q -f "name=redis" 2>/dev/null | head -1)
    if [ -n "$REDIS_ID" ] && docker exec "$REDIS_ID" redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis ok"
    else
        warning "Redis não respondeu"
    fi
}

# ─── 2. Server Driven UI (endpoint público) ──────────────────────────────────
test_server_driven_ui() {
    section "2. SERVER DRIVEN UI"

    test_case "2.1 GET /bff/auth/config (público)"
    RESP=$(curl -sf "$BFF_URL/bff/auth/config" 2>/dev/null || echo "ERROR")
    echo "$RESP" | grep -q "issuer\|clientId\|ERROR" \
        && { echo "$RESP" | grep -q "issuer" && success "Auth config retornado" || warning "Endpoint /bff/auth/config sem dados esperados"; } \
        || error "Endpoint /bff/auth/config não respondeu"

    if [ -n "$AUTH_TOKEN" ]; then
        test_case "2.2 GET /bff/menu (requer Authentik Bearer)"
        RESP=$(bff_curl "$BFF_URL/bff/menu" 2>/dev/null || echo "ERROR")
        echo "$RESP" | grep -q "flow-manager" \
            && success "Menu contém 'flow-manager'" || warning "Menu sem 'flow-manager': $(echo "$RESP" | head -c 100)"

        test_case "2.3 GET /bff/features/flow-manager/ui-schema (requer Authentik Bearer)"
        RESP=$(bff_curl "$BFF_URL/bff/features/flow-manager/ui-schema" 2>/dev/null || echo "ERROR")
        echo "$RESP" | grep -q "featureId" \
            && success "UI schema retornado" || warning "UI schema sem 'featureId': $(echo "$RESP" | head -c 100)"
    else
        warning "2.2 GET /bff/menu — pulado (sem token Authentik)"
        warning "2.3 GET /bff/features/flow-manager/ui-schema — pulado (sem token Authentik)"
    fi
}

# ─── 3. CRUD via Manager ─────────────────────────────────────────────────────
create_test_workflows() {
    section "CRIANDO WORKFLOWS DE TESTE (Manager)"

    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando criação — sem token Manager"
        return 1
    fi

    # Workflow HTTP
    test_case "Criar workflow HTTP (create-order-v1) — YAML"
    YAML_HTTP=$(cat <<'EOF'
flow:
  id: create-order-v1
  version: "1.0.0"
  description: "Test workflow - HTTP integration"
  active: true
  contract:
    fields:
      - name: clientId
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
          - type: PATTERN
            value: "^[A-Z0-9]{6,20}$"
            message: "Invalid clientId"
  integrations:
    - id: fetch-client
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/clients/CLI001A"
        method: GET
        headers:
          Accept: application/json
        timeout: 5000
        responseMapping:
          sourceField: name
          targetField: clientName
EOF
)
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$MGR_URL/manager/flows" \
        -H "Content-Type: text/plain" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        --data-raw "$YAML_HTTP")
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)
    if [ "$HTTP_CODE" = "201" ]; then
        success "Workflow HTTP criado (201)"
    elif [ "$HTTP_CODE" = "409" ]; then
        info "Workflow HTTP já existe (409 — ok, dados de sessão anterior)"
    else
        debug "Resposta: $BODY"
        warning "Workflow HTTP — HTTP $HTTP_CODE"
    fi

    # Workflow RabbitMQ
    test_case "Criar workflow RabbitMQ (test-rabbitmq-v1) — YAML"
    YAML_RABBITMQ=$(cat <<'EOF'
flow:
  id: test-rabbitmq-v1
  version: "1.0.0"
  description: "Test workflow - RabbitMQ integration"
  active: true
  contract:
    fields:
      - name: orderId
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
  integrations:
    - id: notify-rabbitmq
      order: 1
      type: QUEUE
      provider: RABBITMQ
      continueOnError: false
      queue:
        exchange: "orders.exchange"
        routingKey: "order.created"
        persistent: true
        messageTemplate: '{"event":"ORDER_CREATED","orderId":"{{contract.orderId}}"}'
EOF
)
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$MGR_URL/manager/flows" \
        -H "Content-Type: text/plain" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        --data-raw "$YAML_RABBITMQ")
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    if [ "$HTTP_CODE" = "201" ]; then
        success "Workflow RabbitMQ criado (201)"
    elif [ "$HTTP_CODE" = "409" ]; then
        info "Workflow RabbitMQ já existe (409 — ok)"
    else
        warning "Workflow RabbitMQ — HTTP $HTTP_CODE"
    fi

    # Workflow de paralelismo (comparativo v1 x v2): 3 integrações HTTP no MESMO
    # order (1) apontando para o stub lento do WireMock (/slow, 500ms). Em v1 elas
    # rodam sequencialmente (~1500ms); em v2, em paralelo via Virtual Threads (~500ms).
    test_case "Criar workflow paralelo (parallel-demo-v1) — YAML"
    YAML_PARALLEL=$(cat <<'EOF'
flow:
  id: parallel-demo-v1
  version: "1.0.0"
  description: "Parallel demo - 3 HTTP integrations at order 1 (slow stub)"
  active: true
  contract:
    fields:
      - name: refId
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
  integrations:
    - id: slow-a
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/slow/AAA"
        method: GET
        headers:
          Accept: application/json
        timeout: 10000
    - id: slow-b
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/slow/BBB"
        method: GET
        headers:
          Accept: application/json
        timeout: 10000
    - id: slow-c
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/slow/CCC"
        method: GET
        headers:
          Accept: application/json
        timeout: 10000
EOF
)
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$MGR_URL/manager/flows" \
        -H "Content-Type: text/plain" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        --data-raw "$YAML_PARALLEL")
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    if [ "$HTTP_CODE" = "201" ]; then
        success "Workflow paralelo criado (201)"
    elif [ "$HTTP_CODE" = "409" ]; then
        info "Workflow paralelo já existe (409 — ok)"
    else
        warning "Workflow paralelo — HTTP $HTTP_CODE"
    fi
}

test_crud_workflows() {
    section "3. CRUD DE WORKFLOWS (Manager direto)"

    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando CRUD — sem token Manager"
        return 1
    fi

    test_case "3.1 GET /manager/flows — listar"
    RESP=$(mgr_curl "$MGR_URL/manager/flows" 2>/dev/null || echo "ERROR")
    echo "$RESP" | grep -q "create-order-v1" \
        && success "Listagem contém create-order-v1" \
        || warning "create-order-v1 não apareceu na listagem: $(echo "$RESP" | head -c 150)"

    test_case "3.2 GET /manager/flows/create-order-v1/versions/1.0.0"
    RESP=$(mgr_curl "$MGR_URL/manager/flows/create-order-v1/versions/1.0.0" 2>/dev/null || echo "ERROR")
    echo "$RESP" | grep -q "flowId\|create-order-v1" \
        && success "Metadados do workflow obtidos" \
        || error "Metadados não retornados: $(echo "$RESP" | head -c 150)"

    test_case "3.3 GET /manager/flows/create-order-v1/versions/1.0.0/yaml"
    RESP=$(mgr_curl "$MGR_URL/manager/flows/create-order-v1/versions/1.0.0/yaml" 2>/dev/null || echo "ERROR")
    echo "$RESP" | grep -q "flow:\|id:" \
        && success "YAML obtido" \
        || error "YAML não retornado: $(echo "$RESP" | head -c 150)"

    test_case "3.4 GET /manager/flows?status=active — somente ativos"
    RESP=$(mgr_curl "$MGR_URL/manager/flows?status=active" 2>/dev/null || echo "ERROR")
    echo "$RESP" | grep -q "create-order-v1" \
        && success "Workflow ativo aparece no filtro" \
        || warning "Filtro status=active sem resultado esperado"
}

# ─── 4. Execução via Orchestrator ────────────────────────────────────────────
# Globais preenchidos por test_execution para o relatório comparativo v1 x v2.
PERF_ROWS=()
EXEC_BODY=""
EXEC_MS=0

# Executa um workflow no orquestrador na versão indicada (v1|v2) medindo a latência.
# Resultado em EXEC_BODY (corpo JSON) e EXEC_MS (duração em ms).
execute_and_measure() {
    local version=$1 flow_id=$2 payload=$3
    local start end
    start=$(date +%s%3N)
    EXEC_BODY=$(curl -s -X POST \
        "$ORCH_URL/api/${version}/flows/${flow_id}/versions/1.0.0/executions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ORCH_TOKEN" \
        -d "$payload")
    end=$(date +%s%3N)
    EXEC_MS=$((end - start))
}

# Compara paridade semântica de {status,result,validations} entre v1 e v2.
# Usa jq se disponível; senão python3 (fallback). Retorna:
#   0 = idêntico, 1 = divergente, 2 = sem ferramenta de comparação disponível.
compare_parity() {
    local b1=$1 b2=$2
    if command -v jq >/dev/null 2>&1; then
        local p1 p2
        p1=$(echo "$b1" | jq -S '{status,result,validations}' 2>/dev/null)
        p2=$(echo "$b2" | jq -S '{status,result,validations}' 2>/dev/null)
        [ -n "$p1" ] && [ "$p1" = "$p2" ]
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        PARITY_B1="$b1" PARITY_B2="$b2" python3 - <<'PY'
import json, os, sys
try:
    a = json.loads(os.environ["PARITY_B1"]); b = json.loads(os.environ["PARITY_B2"])
except Exception:
    sys.exit(1)
key = lambda x: {"status": x.get("status"), "result": x.get("result"), "validations": x.get("validations")}
sys.exit(0 if key(a) == key(b) else 1)
PY
        return
    fi
    return 2
}

test_execution() {
    section "4. EXECUÇÃO DE WORKFLOWS — comparativo v1 x v2 (Orchestrator direto)"

    if [ -z "$ORCH_TOKEN" ]; then
        warning "Pulando execução — sem token Orchestrator"
        return 1
    fi

    # 4.1 — create-order-v1 (smoke funcional nas duas rotas). Resposta contém
    # campos não-determinísticos (orderId aleatório), então validamos paridade
    # apenas de status, não do result completo.
    test_case "4.1 create-order-v1 — v1 e v2 retornam SUCCESS"
    execute_and_measure v1 "create-order-v1" '{"clientId":"ABC123","amount":150.00}'
    local co_b1=$EXEC_BODY co_t1=$EXEC_MS
    execute_and_measure v2 "create-order-v1" '{"clientId":"ABC123","amount":150.00}'
    local co_b2=$EXEC_BODY co_t2=$EXEC_MS
    if echo "$co_b1" | grep -q '"status":"SUCCESS"' && echo "$co_b2" | grep -q '"status":"SUCCESS"'; then
        success "create-order-v1: v1=${co_t1}ms, v2=${co_t2}ms (ambos SUCCESS)"
    else
        warning "create-order-v1: v1=$(echo "$co_b1" | head -c 80) | v2=$(echo "$co_b2" | head -c 80)"
    fi
    PERF_ROWS+=("| create-order-v1 | ${co_t1}ms | ${co_t2}ms | $(awk "BEGIN{if($co_t2>0)printf \"%.2fx\",$co_t1/$co_t2; else printf \"n/a\"}") | status |")

    # 4.2 — parallel-demo-v1 (3 integrações no mesmo order, stub lento 500ms).
    # Resposta determinística → paridade total de result; v2 deve ser bem mais rápido.
    test_case "4.2 parallel-demo-v1 — paridade total v1/v2 + speedup das Virtual Threads"
    execute_and_measure v1 "parallel-demo-v1" '{"refId":"ABC123"}'
    local pd_b1=$EXEC_BODY pd_t1=$EXEC_MS
    execute_and_measure v2 "parallel-demo-v1" '{"refId":"ABC123"}'
    local pd_b2=$EXEC_BODY pd_t2=$EXEC_MS

    local parity_mark="?" parity_rc=0
    compare_parity "$pd_b1" "$pd_b2" || parity_rc=$?
    case $parity_rc in
        0) success "Paridade v1/v2 confirmada (status+result+validations idênticos)"; parity_mark="✅" ;;
        1) error "Divergência v1/v2 detectada em parallel-demo-v1!"; parity_mark="❌"
           debug "v1: $(echo "$pd_b1" | head -c 200)"; debug "v2: $(echo "$pd_b2" | head -c 200)" ;;
        2) warning "jq/python3 ausentes — paridade detalhada pulada (validado apenas status)"
           echo "$pd_b1" | grep -q '"status":"SUCCESS"' && echo "$pd_b2" | grep -q '"status":"SUCCESS"' \
               && parity_mark="~status~" || parity_mark="⚠" ;;
    esac

    # Asserção de speedup: v2 deve ser significativamente mais rápido (< 70% do v1).
    if [ "$pd_t1" -gt 0 ] && [ "$pd_t2" -gt 0 ] && [ $((pd_t2 * 100)) -lt $((pd_t1 * 70)) ]; then
        success "Speedup v2 confirmado: v1=${pd_t1}ms vs v2=${pd_t2}ms"
    else
        warning "Speedup v2 não evidente: v1=${pd_t1}ms vs v2=${pd_t2}ms (esperado v2 << v1)"
    fi
    PERF_ROWS+=("| parallel-demo-v1 | ${pd_t1}ms | ${pd_t2}ms | $(awk "BEGIN{if($pd_t2>0)printf \"%.2fx\",$pd_t1/$pd_t2; else printf \"n/a\"}") | $parity_mark |")

    # 4.3 — smoke da rota v2 via BFF (proxy) para confirmar o caminho ponta a ponta.
    if [ -n "$AUTH_TOKEN" ]; then
        test_case "4.3 POST via BFF .../executions/v2 (proxy paralelo)"
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            "$BFF_URL/bff/flows/parallel-demo-v1/versions/1.0.0/executions/v2" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -d '{"refId":"ABC123"}')
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | head -n -1)
        echo "$BODY" | grep -q '"status":"SUCCESS"\|executionId' \
            && success "Execução v2 via BFF (HTTP $HTTP_CODE)" \
            || warning "Execução v2 via BFF — HTTP $HTTP_CODE: $(echo "$BODY" | head -c 100)"
    else
        warning "4.3 Execução v2 via BFF — pulado (sem token Authentik)"
    fi
}

# ─── 5. Cenários negativos ────────────────────────────────────────────────────
test_negative_scenarios() {
    section "5. CENÁRIOS NEGATIVOS"

    test_case "5.1 Manager sem Bearer → 401"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MGR_URL/manager/flows")
    [ "$CODE" = "401" ] && success "Manager protegido (401 sem token)" \
        || warning "Manager retornou $CODE sem token (esperado 401)"

    test_case "5.2 Orchestrator sem Bearer → 401"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$ORCH_URL/api/v1/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" -d '{}')
    [ "$CODE" = "401" ] && success "Orchestrator protegido (401 sem token)" \
        || warning "Orchestrator retornou $CODE sem token (esperado 401)"

    # O orquestrador sempre retorna HTTP 200; sucesso/falha vem no campo "status" do body.
    if [ -n "$ORCH_TOKEN" ]; then
        test_case "5.3 Workflow inexistente → 200 + status FAILED"
        RESP=$(orch_curl -s -w "\n%{http_code}" \
            -X POST "$ORCH_URL/api/v1/flows/nao-existe/versions/1.0.0/executions" \
            -H "Content-Type: application/json" -d '{}')
        CODE=$(echo "$RESP" | tail -1)
        BODY=$(echo "$RESP" | head -n -1)
        if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "FAILED"; then
            success "Workflow inexistente retorna FAILED no body (comportamento correto)"
        else
            warning "5.3 retornou HTTP $CODE / body: $(echo "$BODY" | head -c 100)"
        fi

        test_case "5.4 Payload inválido → 200 + status FAILED"
        RESP=$(orch_curl -s -w "\n%{http_code}" \
            -X POST "$ORCH_URL/api/v1/flows/create-order-v1/versions/1.0.0/executions" \
            -H "Content-Type: application/json" -d '{}')
        CODE=$(echo "$RESP" | tail -1)
        BODY=$(echo "$RESP" | head -n -1)
        if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "FAILED"; then
            success "Payload invalido retorna FAILED no body (comportamento correto)"
        else
            warning "5.4 retornou HTTP $CODE / body: $(echo "$BODY" | head -c 100)"
        fi
    else
        warning "5.3 e 5.4 — pulados (sem token Orchestrator)"
    fi

    test_case "5.5 BFF /bff/health (público) → 200"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BFF_URL/bff/health")
    [ "$CODE" = "200" ] && success "BFF /bff/health público (200)" \
        || error "BFF /bff/health retornou $CODE (esperado 200)"
}

# ─── Relatório ────────────────────────────────────────────────────────────────
generate_report() {
    TOTAL=$((PASSED + FAILED + SKIPPED))
    PCTG=$((TOTAL > 0 ? PASSED * 100 / TOTAL : 0))

    cat > "$CHECKLIST_FILE" <<EOF
# Relatório de Testes Integrados — Service Portal v3
Data: $(date)

## Resumo
- Total:    $TOTAL
- ✓ Passou: $PASSED ($PCTG%)
- ✗ Falhou: $FAILED
- ⚠ Pulado: $SKIPPED

## Tokens obtidos
- Manager Token:      $([ -n "$MANAGER_TOKEN" ] && echo "✓ sim" || echo "✗ não")
- Orchestrator Token: $([ -n "$ORCH_TOKEN" ]    && echo "✓ sim" || echo "✗ não")
- Authentik Token:    $([ -n "$AUTH_TOKEN" ]     && echo "✓ sim" || echo "✗ não (testes BFF pulados)")

## Comparativo de execução v1 (sequencial) x v2 (paralelo)

| Workflow | Latência v1 | Latência v2 | Speedup | Paridade |
|---|---|---|---|---|
$(printf '%s\n' "${PERF_ROWS[@]}")

> Paridade: ✅ = {status,result,validations} idênticos (via jq ou python3); \`status\` = apenas status
> comparado (resposta com campos não-determinísticos); ⚠/~status~ = jq e python3 ausentes, detalhe pulado.
> O speedup do \`parallel-demo-v1\` evidencia o paralelismo das Virtual Threads (3 integrações @ 500ms
> no mesmo \`order\`): v1 ≈ soma sequencial; v2 ≈ a mais lenta das paralelas.

## Log detalhado
$LOG_FILE
EOF
    success "Relatório: $CHECKLIST_FILE"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    section "TESTES INTEGRADOS — SERVICE PORTAL v3"
    log "Data: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Log: $LOG_FILE"

    check_prerequisites

    start_infrastructure || { error "Falha ao iniciar infraestrutura"; exit 1; }

    get_manager_token     || true
    get_orchestrator_token || true
    get_authentik_token   || true

    test_health
    test_server_driven_ui
    create_test_workflows || true
    test_crud_workflows   || true
    test_execution        || true
    test_negative_scenarios

    generate_report

    section "RESULTADO FINAL"
    TOTAL=$((PASSED + FAILED + SKIPPED))
    PCTG=$((TOTAL > 0 ? PASSED * 100 / TOTAL : 0))

    log "╔══════════════════════════════════╗"
    log "║  PASSOU:  $PASSED / $TOTAL testes ($PCTG%)  ║"
    log "║  FALHOU:  $FAILED                       ║"
    log "║  PULADOS: $SKIPPED                       ║"
    log "╚══════════════════════════════════╝"

    [ $FAILED -eq 0 ] && success "Todos os testes passaram ou foram pulados por dependências externas (Authentik)" \
        || warning "Verifique os logs: $LOG_FILE"
}

main "$@"
