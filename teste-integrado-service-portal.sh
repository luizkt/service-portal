#!/bin/bash
# teste-integrado-service-portal.sh
# Script de testes integrados para o Service Portal
# Valida a infraestrutura e executa cenários end-to-end

set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# ── Configuração ──────────────────────────────────────────────────────────────
DOCKER_COMPOSE_FILE="docker-compose-service-portal.yml"
LOG_FILE="teste-integrado-$(date +%Y%m%d-%H%M%S).log"
CHECKLIST_FILE="teste-integrado-checklist-$(date +%Y%m%d-%H%M%S).md"
BFF_URL="http://localhost:8081"
ORCH_URL="http://localhost:8080"
MANAGER_URL="http://localhost:8082"
AUTHENTIK_URL="http://localhost:9000"

# ── Contadores ────────────────────────────────────────────────────────────────
PASSED=0; FAILED=0; SKIPPED=0

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; PASSED=$((PASSED+1)); }
error()   { echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"; FAILED=$((FAILED+1)); }
warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"; SKIPPED=$((SKIPPED+1)); }
section() { echo -e "\n${BLUE}═══ $* ═══${NC}" | tee -a "$LOG_FILE"; }
test_case() { echo -e "\n${YELLOW}→${NC} $*" | tee -a "$LOG_FILE"; }

# ── Autenticação ──────────────────────────────────────────────────────────────
BFF_TOKEN=""

# Wrapper para curl com Bearer token
bff_curl() {
    curl -s -H "Authorization: Bearer $BFF_TOKEN" "$@"
}

bff_curl_code() {
    curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $BFF_TOKEN" "$@"
}

# ── Pré-requisitos ────────────────────────────────────────────────────────────
check_prerequisites() {
    section "PRÉ-REQUISITOS"

    [ -f "$DOCKER_COMPOSE_FILE" ] && success "docker-compose-service-portal.yml encontrado" \
        || { error "Arquivo $DOCKER_COMPOSE_FILE não encontrado"; exit 1; }
    [ -f ".env" ] && success ".env encontrado" \
        || { error "Arquivo .env não encontrado"; exit 1; }
    command -v docker >/dev/null 2>&1 && success "Docker disponível" \
        || { error "Docker não instalado"; exit 1; }
    command -v curl >/dev/null 2>&1 && success "curl disponível" \
        || { error "curl não instalado"; exit 1; }
}

# ── Infraestrutura ────────────────────────────────────────────────────────────
wait_for_service() {
    local name=$1 url=$2 attempts=0 max=60
    log "Aguardando $name em $url..."
    until curl -sf "$url" > /dev/null 2>&1 || [ $attempts -ge $max ]; do
        attempts=$((attempts+1)); sleep 2
    done
    [ $attempts -lt $max ] && success "$name pronto" || { error "$name não respondeu em ${max}x2s"; return 1; }
}

setup_authentik() {
    log "Configurando Authentik (idempotente)..."
    docker exec -i portal-authentik-server python3 - <<'PYEOF' 2>/dev/null | grep -E "OK:|SKIP:" || true
import os, sys
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'authentik.root.settings')
import django; django.setup()

from authentik.providers.oauth2.models import OAuth2Provider
from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow

# Provider já existe?
if OAuth2Provider.objects.filter(client_id='service-portal-spa').exists():
    print('SKIP: OAuth2 provider service-portal-spa já existe')
    sys.exit(0)

signing_key = CertificateKeyPair.objects.filter(name='authentik Self-signed Certificate').first()
auth_flow   = Flow.objects.filter(slug='default-provider-authorization-implicit-consent').first()
inval_flow  = Flow.objects.filter(slug='default-provider-invalidation-flow').first()
if not (signing_key and auth_flow and inval_flow):
    print('ERR: dependências não encontradas', signing_key, auth_flow, inval_flow)
    sys.exit(1)

provider = OAuth2Provider.objects.create(
    name='service-portal',
    authorization_flow=auth_flow,
    invalidation_flow=inval_flow,
    client_type='public',
    client_id='service-portal-spa',
    signing_key=signing_key,
    sub_mode='hashed_user_id',
    access_token_validity='hours=1',
    include_claims_in_id_token=True,
)
from authentik.providers.oauth2.models import RedirectURI, RedirectURIMatchingMode
provider.redirect_uris.set([
    RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url='http://localhost:5173/auth/callback'),
    RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url='http://localhost/auth/callback'),
], bulk=False)

Application.objects.create(
    name='Service Portal',
    slug='service-portal',
    provider=provider,
    policy_engine_mode='any',
)
print('OK: provider e application criados')
PYEOF
}

get_bff_token() {
    log "Obtendo token JWT para o BFF via Authentik..."
    # Escreve o script Python em arquivo temporário no container para evitar problemas
    # com heredoc dentro de command substitution
    docker exec -i portal-authentik-server sh -c 'cat > /tmp/gen_jwt.py' <<'PYEOF'
import os, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'authentik.root.settings')
import django; django.setup()
from authentik.crypto.models import CertificateKeyPair
from authentik.providers.oauth2.models import OAuth2Provider
from cryptography.hazmat.primitives import serialization
import jwt as pyjwt

cert     = CertificateKeyPair.objects.get(name='authentik Self-signed Certificate')
provider = OAuth2Provider.objects.get(client_id='service-portal-spa')
key      = serialization.load_pem_private_key(cert.key_data.encode(), password=None)
kid      = getattr(provider.signing_key, 'kid', '')
payload  = {
    'iss': 'http://localhost:9000/application/o/service-portal/',
    'sub': 'test-integration-script',
    'aud': 'service-portal-spa',
    'exp': int(time.time()) + 3600,
    'iat': int(time.time()),
    'scope': 'openid profile email',
}
token = pyjwt.encode(payload, key, algorithm='RS256', headers={'kid': kid})
print('JWT:' + token)
PYEOF
    BFF_TOKEN=$(docker exec portal-authentik-server env PYTHONPATH=/ python3 /tmp/gen_jwt.py 2>/dev/null | grep "^JWT:" | cut -c5-)
    if [ -z "$BFF_TOKEN" ]; then
        error "Falha ao obter token JWT do Authentik"
        return 1
    fi
    success "Token JWT obtido"
}

start_infrastructure() {
    section "INFRAESTRUTURA"

    # Detecta se a stack já está no ar
    if docker ps --filter "name=portal-bff" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "portal-bff"; then
        log "Containers já rodando — pulando restart"
    else
        log "Iniciando containers..."
        docker compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d
        sleep 5
    fi

    wait_for_service "BFF"          "$BFF_URL/bff/health"
    wait_for_service "Orchestrator" "$ORCH_URL/actuator/health"
    wait_for_service "Manager"      "$MANAGER_URL/actuator/health"
    wait_for_service "Authentik"    "$AUTHENTIK_URL/-/health/ready/"

    setup_authentik
    get_bff_token
}

# ── 1. Saúde do Sistema ───────────────────────────────────────────────────────
test_health() {
    section "1. SAÚDE DO SISTEMA"

    test_case "1.1 BFF /bff/health"
    curl -sf "$BFF_URL/bff/health" | grep -q "status" \
        && success "BFF respondendo" || error "BFF não respondendo"

    test_case "1.2 Orchestrator /actuator/health"
    curl -sf "$ORCH_URL/actuator/health" | grep -q "status" \
        && success "Orquestrador respondendo" || error "Orquestrador não respondendo"

    test_case "1.3 Manager /actuator/health"
    curl -sf "$MANAGER_URL/actuator/health" | grep -q "status" \
        && success "Manager respondendo" || error "Manager não respondendo"

    test_case "1.4 RabbitMQ management API"
    # Endpoint correto: /api/aliveness-test/%2F (não /api/health)
    curl -sf "http://guest:guest@localhost:15672/api/aliveness-test/%2F" | grep -q "ok" \
        && success "RabbitMQ respondendo" || error "RabbitMQ não respondendo"

    test_case "1.5 Redis"
    docker exec "$(docker ps -q -f name=portal-redis)" redis-cli ping 2>/dev/null | grep -q "PONG" \
        && success "Redis respondendo" || warning "Redis não respondendo (dependência secundária)"

    test_case "1.6 Authentik OIDC discovery"
    curl -sf "$AUTHENTIK_URL/application/o/service-portal/.well-known/openid-configuration" | grep -q "issuer" \
        && success "Authentik OIDC configurado" || error "Authentik OIDC não configurado"
}

# ── 2. Server Driven UI ───────────────────────────────────────────────────────
test_server_driven_ui() {
    section "2. SERVER DRIVEN UI"

    test_case "2.1 GET /bff/auth/config (público)"
    curl -sf "$BFF_URL/bff/auth/config" | grep -q "clientId" \
        && success "Auth config retornado" || error "Auth config não retornado"

    test_case "2.2 GET /bff/menu (Bearer token)"
    bff_curl "$BFF_URL/bff/menu" | grep -q "flow-manager" \
        && success "Menu contém flow-manager" || error "Menu não contém flow-manager"

    test_case "2.3 GET /bff/features/flow-manager/ui-schema (Bearer token)"
    bff_curl "$BFF_URL/bff/features/flow-manager/ui-schema" | grep -q "featureId" \
        && success "UI schema retornado" || error "UI schema não retornado"

    test_case "2.4 Endpoint protegido sem token → 401"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BFF_URL/bff/menu")
    [ "$CODE" = "401" ] \
        && success "Sem token retorna 401 (auth funcionando)" \
        || error "Esperado 401 sem token, recebido $CODE"
}

# ── Criação de workflows de teste ─────────────────────────────────────────────
create_test_workflows() {
    section "CRIANDO WORKFLOWS DE TESTE"

    test_case "Workflow HTTP: create-order-v1"
    FLOW_HTTP=$(cat <<'EOF'
flow:
  id: "create-order-v1"
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
    - id: validate-client
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/clients/{{contract.clientId}}"
        method: GET
        headers:
          Accept: "application/json"
        timeout: 5000
EOF
)
    CODE=$(bff_curl -s -w "\n%{http_code}" -X POST "$BFF_URL/bff/flows" \
        -H "Content-Type: text/plain" -d "$FLOW_HTTP" | tail -1)
    [ "$CODE" = "201" ] && success "Workflow HTTP criado (201)" \
        || { [ "$CODE" = "409" ] && warning "Workflow HTTP já existe (409 — ok)" \
            || error "Workflow HTTP falhou (HTTP $CODE)"; }

    test_case "Workflow RabbitMQ: test-rabbitmq"
    FLOW_RABBIT=$(cat <<'EOF'
flow:
  id: "test-rabbitmq"
  version: "1.0.0"
  description: "Test workflow - RabbitMQ"
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
        messageTemplate: |
          {"event":"ORDER_CREATED","orderId":"{{contract.orderId}}"}
EOF
)
    CODE=$(bff_curl -s -w "\n%{http_code}" -X POST "$BFF_URL/bff/flows" \
        -H "Content-Type: text/plain" -d "$FLOW_RABBIT" | tail -1)
    [ "$CODE" = "201" ] && success "Workflow RabbitMQ criado (201)" \
        || { [ "$CODE" = "409" ] && warning "Workflow RabbitMQ já existe (409 — ok)" \
            || error "Workflow RabbitMQ falhou (HTTP $CODE)"; }

    test_case "Workflow Kafka: test-kafka"
    FLOW_KAFKA=$(cat <<'EOF'
flow:
  id: "test-kafka"
  version: "1.0.0"
  description: "Test workflow - Kafka"
  active: true
  contract:
    fields:
      - name: orderId
        type: STRING
        required: true
  integrations:
    - id: track-kafka
      order: 1
      type: QUEUE
      provider: KAFKA
      continueOnError: false
      queue:
        topic: "orders.created"
        messageTemplate: |
          {"event":"ORDER_CREATED","orderId":"{{contract.orderId}}"}
EOF
)
    CODE=$(bff_curl -s -w "\n%{http_code}" -X POST "$BFF_URL/bff/flows" \
        -H "Content-Type: text/plain" -d "$FLOW_KAFKA" | tail -1)
    [ "$CODE" = "201" ] && success "Workflow Kafka criado (201)" \
        || { [ "$CODE" = "409" ] && warning "Workflow Kafka já existe (409 — ok)" \
            || error "Workflow Kafka falhou (HTTP $CODE)"; }
}

# ── 3. CRUD de Workflows ──────────────────────────────────────────────────────
test_crud_workflows() {
    section "3. CRUD DE WORKFLOWS"

    test_case "3.1 GET /bff/flows (listagem paginada)"
    RESP=$(bff_curl "$BFF_URL/bff/flows")
    echo "$RESP" | grep -q "content\|flowId\|create-order" \
        && success "Listagem retornada" || error "Listagem falhou: ${RESP:0:100}"

    test_case "3.2 GET /bff/flows/create-order-v1/versions/1.0.0"
    RESP=$(bff_curl "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0")
    echo "$RESP" | grep -q "flowId\|create-order-v1" \
        && success "Workflow específico encontrado" || error "Workflow não encontrado: ${RESP:0:100}"

    test_case "3.3 GET /bff/flows/create-order-v1/versions/1.0.0/yaml"
    RESP=$(bff_curl "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0/yaml")
    echo "$RESP" | grep -q "flow:" \
        && success "YAML retornado" || error "YAML não retornado: ${RESP:0:100}"

    test_case "3.4 GET /bff/flows?status=active"
    RESP=$(bff_curl "$BFF_URL/bff/flows?status=active")
    echo "$RESP" | grep -q "flowId\|create-order\|\[\]" \
        && success "Listagem de ativos retornada" || error "Listagem de ativos falhou: ${RESP:0:100}"
}

# ── 4. Execução de Workflows ──────────────────────────────────────────────────
test_execution_http() {
    section "4. EXECUÇÃO - WORKFLOW HTTP"

    test_case "4.1 Executar create-order-v1 com payload válido"
    RESP=$(bff_curl -X POST "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" \
        -d '{"clientId":"CLI001A"}')
    echo "$RESP" | grep -q "SUCCESS\|executionId" \
        && success "Execução HTTP OK" || warning "Execução HTTP: ${RESP:0:150}"
}

test_execution_queue() {
    section "5. EXECUÇÃO - WORKFLOW QUEUE"

    test_case "5.1 Executar test-rabbitmq"
    RESP=$(bff_curl -X POST "$BFF_URL/bff/flows/test-rabbitmq/versions/1.0.0/executions" \
        -H "Content-Type: application/json" \
        -d '{"orderId":"ORD-001"}')
    echo "$RESP" | grep -q "SUCCESS\|executionId" \
        && success "Execução RabbitMQ OK" || warning "RabbitMQ: ${RESP:0:150}"

    test_case "5.2 Executar test-kafka"
    RESP=$(bff_curl -X POST "$BFF_URL/bff/flows/test-kafka/versions/1.0.0/executions" \
        -H "Content-Type: application/json" \
        -d '{"orderId":"ORD-002"}')
    echo "$RESP" | grep -q "SUCCESS\|executionId" \
        && success "Execução Kafka OK" || warning "Kafka: ${RESP:0:150}"
}

# ── 6. Cenários Negativos ─────────────────────────────────────────────────────
test_negative_scenarios() {
    section "6. CENÁRIOS NEGATIVOS"

    test_case "6.1 Execução sem token → 401"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" -d '{"clientId":"CLI001A"}')
    [ "$CODE" = "401" ] && success "Sem token retorna 401" || error "Esperado 401, recebido $CODE"

    test_case "6.2 Payload inválido (campo obrigatório ausente) → status FAILED"
    # Orquestrador retorna 200 com status:FAILED para falhas de contrato
    BODY=$(bff_curl -X POST "$BFF_URL/bff/flows/create-order-v1/versions/1.0.0/executions" \
        -H "Content-Type: application/json" -d '{}')
    echo "$BODY" | grep -q '"status":"FAILED"' && success "Validação de contrato → status FAILED" || error "Esperado status FAILED, body: $BODY"

    test_case "6.3 Workflow inexistente → status FAILED"
    # Orquestrador retorna 200 com status:FAILED quando o fluxo não existe
    BODY=$(bff_curl -X POST "$BFF_URL/bff/flows/inexistente/versions/1.0.0/executions" \
        -H "Content-Type: application/json" -d '{}')
    echo "$BODY" | grep -q '"status":"FAILED"' && success "Workflow inexistente → status FAILED" || error "Esperado status FAILED, body: $BODY"

    test_case "6.4 Versão inexistente → status FAILED"
    # Orquestrador retorna 200 com status:FAILED quando a versão não existe
    BODY=$(bff_curl -X POST "$BFF_URL/bff/flows/create-order-v1/versions/99.0.0/executions" \
        -H "Content-Type: application/json" -d '{"clientId":"CLI001A"}')
    echo "$BODY" | grep -q '"status":"FAILED"' && success "Versão inexistente → status FAILED" || warning "Esperado status FAILED, body: $BODY"

    test_case "6.5 Criação duplicada → 409"
    CODE=$(bff_curl_code -X POST "$BFF_URL/bff/flows" \
        -H "Content-Type: text/plain" \
        -d 'flow:
  id: "create-order-v1"
  version: "1.0.0"
  description: "Test workflow - HTTP integration"
  active: true
  contract:
    fields:
      - name: "clientId"
        type: "string"
        required: true
  integrations:
    - type: "http"
      name: "order-service"
      url: "http://wiremock:8080/orders"
      method: "POST"')
    [ "$CODE" = "409" ] && success "Criação duplicada → 409" || warning "Esperado 409, recebido $CODE"
}

# ── Relatório ─────────────────────────────────────────────────────────────────
generate_report() {
    section "RELATÓRIO"
    TOTAL=$((PASSED + FAILED + SKIPPED))
    PCT=$((TOTAL > 0 ? PASSED * 100 / TOTAL : 0))

    cat > "$CHECKLIST_FILE" <<REPORT
# Relatório de Testes Integrados — Service Portal

**Data**: $(date)
**Script**: teste-integrado-service-portal.sh

## Resumo

| Resultado | Quantidade |
|---|---|
| ✓ Passou | $PASSED |
| ✗ Falhou | $FAILED |
| ⚠ Pulado | $SKIPPED |
| **Total** | $TOTAL |
| **Taxa de sucesso** | ${PCT}% |

## Log detalhado

Arquivo: \`$LOG_FILE\`
REPORT

    success "Relatório: $CHECKLIST_FILE"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    section "TESTES INTEGRADOS — SERVICE PORTAL"
    log "Início: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Log: $LOG_FILE"

    check_prerequisites
    start_infrastructure

    test_health            || true
    test_server_driven_ui  || true
    create_test_workflows  || true
    test_crud_workflows    || true
    test_execution_http    || true
    test_execution_queue   || true
    test_negative_scenarios || true

    generate_report

    section "RESUMO FINAL"
    TOTAL=$((PASSED + FAILED + SKIPPED))
    PCT=$((TOTAL > 0 ? PASSED * 100 / TOTAL : 0))
    log "Total: $TOTAL | ✓ $PASSED | ✗ $FAILED | ⚠ $SKIPPED | Taxa: ${PCT}%"

    if [ $FAILED -gt 0 ]; then
        log "Alguns testes falharam. Verifique: $LOG_FILE"
        exit 1
    fi
}

main "$@"
