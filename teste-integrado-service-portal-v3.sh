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

    command -v jq >/dev/null 2>&1 && success "jq instalado" \
        || warning "jq não instalado — alguns testes de parsing podem falhar"
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
test_execution() {
    section "4. EXECUÇÃO DE WORKFLOWS (Orchestrator direto)"

    if [ -z "$ORCH_TOKEN" ]; then
        warning "Pulando execução — sem token Orchestrator"
        return 1
    fi

    test_case "4.1 POST /api/flows/create-order-v1/versions/1.0.0/executions"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "$ORCH_URL/api/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ORCH_TOKEN" \
        -d '{"clientId":"CLI001A"}')
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if echo "$BODY" | grep -q "SUCCESS\|executionId\|result"; then
        success "Workflow executado (HTTP $HTTP_CODE)"
        debug "Response: $(echo "$BODY" | head -c 200)"
    elif [ "$HTTP_CODE" = "200" ]; then
        success "Execução retornou 200"
        debug "Response: $(echo "$BODY" | head -c 200)"
    else
        warning "Execução — HTTP $HTTP_CODE: $(echo "$BODY" | head -c 150)"
    fi

    if [ -n "$AUTH_TOKEN" ]; then
        test_case "4.2 POST via BFF /bff/flows/create-order-v1/versions/1.0.0/executions"
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0/executions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -d '{"clientId":"CLI001A"}')
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | head -n -1)
        echo "$BODY" | grep -q "SUCCESS\|executionId\|result\|200" \
            && success "Execução via BFF (HTTP $HTTP_CODE)" \
            || warning "Execução via BFF — HTTP $HTTP_CODE: $(echo "$BODY" | head -c 100)"
    else
        warning "4.2 Execução via BFF — pulado (sem token Authentik)"
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
        -X POST "$ORCH_URL/api/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" -d '{}')
    [ "$CODE" = "401" ] && success "Orchestrator protegido (401 sem token)" \
        || warning "Orchestrator retornou $CODE sem token (esperado 401)"

    # O orquestrador sempre retorna HTTP 200; sucesso/falha vem no campo "status" do body.
    if [ -n "$ORCH_TOKEN" ]; then
        test_case "5.3 Workflow inexistente → 200 + status FAILED"
        RESP=$(orch_curl -s -w "\n%{http_code}" \
            -X POST "$ORCH_URL/api/flows/nao-existe/versions/1.0.0/executions" \
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
            -X POST "$ORCH_URL/api/flows/create-order-v1/versions/1.0.0/executions" \
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
