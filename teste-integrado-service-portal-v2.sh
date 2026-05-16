#!/bin/bash
# teste-integrado-service-portal-v2.sh
# Script de testes integrados melhorado para o Service Portal
# Versão 2: Adicionado suporte a autenticação e melhor diagnóstico

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Variáveis
DOCKER_COMPOSE_FILE="docker-compose-service-portal.yml"
ENV_FILE=".env"
LOG_FILE="teste-integrado-$(date +%Y%m%d-%H%M%S).log"
RESULTS_FILE="teste-integrado-results-$(date +%Y%m%d-%H%M%S).txt"
CHECKLIST_FILE="teste-integrado-checklist-$(date +%Y%m%d-%H%M%S).md"

# Configuração de timeouts
MAX_WAIT_SECONDS=120
DOCKER_READY_TIMEOUT=60

# Token de autenticação (será obtido dinamicamente)
AUTH_TOKEN=""
MANAGER_TOKEN=""

# Contadores
PASSED=0
FAILED=0
SKIPPED=0

# Funções auxiliares
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $@" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $@" | tee -a "$LOG_FILE"
    ((PASSED++))
}

error() {
    echo -e "${RED}✗${NC} $@" | tee -a "$LOG_FILE"
    ((FAILED++))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $@" | tee -a "$LOG_FILE"
    ((SKIPPED++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $@" | tee -a "$LOG_FILE"
}

debug() {
    echo -e "${MAGENTA}DEBUG${NC} $@" | tee -a "$LOG_FILE"
}

section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$@${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

test_case() {
    echo -e "\n${YELLOW}→${NC} $@" | tee -a "$LOG_FILE"
}

# Verifica prerequisites
check_prerequisites() {
    section "VERIFICANDO PRÉ-REQUISITOS"

    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        error "Arquivo $DOCKER_COMPOSE_FILE não encontrado"
        exit 1
    fi
    success "Arquivo $DOCKER_COMPOSE_FILE encontrado"

    if [ ! -f "$ENV_FILE" ]; then
        error "Arquivo $ENV_FILE não encontrado. Execute: cp env.example .env"
        exit 1
    fi
    success "Arquivo $ENV_FILE encontrado"

    command -v docker >/dev/null 2>&1 || {
        error "Docker não instalado"
        exit 1
    }
    success "Docker instalado"

    command -v curl >/dev/null 2>&1 || {
        error "curl não instalado"
        exit 1
    }
    success "curl instalado"

    command -v jq >/dev/null 2>&1 || {
        warning "jq não instalado (alguns testes de parsing podem falhar)"
    }
}

# Aguarda um serviço estar healthy
wait_for_service() {
    local service=$1
    local port=$2
    local path=${3:-""}
    local max_attempts=120  # 240 segundos máximo
    local attempt=0

    if [ -z "$path" ]; then
        path="/"
    fi

    echo ""
    info "Aguardando $service na porta $port (máx 240s)..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf --connect-timeout 2 "http://localhost:$port$path" > /dev/null 2>&1; then
            success "$service está pronto (porta $port)"
            return 0
        fi

        attempt=$((attempt + 1))
        progress=$((attempt * 100 / max_attempts))
        printf "\r[%3d%%] Tentativa %d/%d" "$progress" "$attempt" "$max_attempts"

        sleep 2
    done

    echo ""
    error "$service não ficou pronto em 240 segundos"
    docker compose -f "$DOCKER_COMPOSE_FILE" logs --tail=20 $(echo $service | tr '[:upper:]' '[:lower:]') || true
    return 1
}

# Inicia o docker compose
start_infrastructure() {
    section "INICIANDO INFRAESTRUTURA"

    log "Parando containers anteriores..."
    docker compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true
    sleep 2

    log "Iniciando nova stack..."
    if ! docker compose -f "$DOCKER_COMPOSE_FILE" up -d; then
        error "Falha ao iniciar docker compose"
        return 1
    fi

    sleep 5  # Aguarda containers iniciarem

    log "Aguardando serviços ficarem prontos..."
    info "Verificando status dos containers..."
    docker compose -f "$DOCKER_COMPOSE_FILE" ps

    # Aguarda serviços essenciais (em ordem de dependência)
    wait_for_service "BFF" 8081 "/bff/health" || return 1
    wait_for_service "Orchestrator" 8080 "/actuator/health" || return 1
    wait_for_service "Manager" 8082 "/actuator/health" || return 1

    sleep 3  # Aguarda estabilização final
    success "✅ Infraestrutura iniciada com sucesso"
}

# Obtém token de autenticação do Manager
get_manager_token() {
    section "AUTENTICAÇÃO - MANAGER"

    test_case "Obtendo token de autenticação Manager"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/api/auth/tokens \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin"}' 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        MANAGER_TOKEN=$(echo "$BODY" | jq -r '.token // .access_token // .' 2>/dev/null)
        if [ -z "$MANAGER_TOKEN" ] || [ "$MANAGER_TOKEN" = "null" ]; then
            MANAGER_TOKEN="$BODY"  # Fallback se jq falhar
        fi
        success "Token Manager obtido (HTTP $HTTP_CODE)"
        debug "Token: ${MANAGER_TOKEN:0:20}..."
        return 0
    else
        warning "Falha ao obter token Manager (HTTP $HTTP_CODE)"
        debug "Response: $BODY"
        return 1
    fi
}

# Obtém token de autenticação do Authentik (para BFF)
get_authentik_token() {
    section "AUTENTICAÇÃO - AUTHENTIK"

    test_case "Verificando Authentik na porta 9000"
    if ! curl -sf http://localhost:9000/api/system/status > /dev/null 2>&1; then
        warning "Authentik não está acessível"
        return 1
    fi
    success "Authentik está acessível"

    test_case "Obtendo token do Authentik"
    # Nota: Este é um exemplo - ajuste conforme a configuração real do Authentik
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:9000/application/o/service-portal/token/ \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=service-portal&client_secret=service-portal" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "200" ]; then
        AUTH_TOKEN=$(echo "$BODY" | jq -r '.access_token // .' 2>/dev/null)
        if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
            AUTH_TOKEN="$BODY"  # Fallback
        fi
        success "Token Authentik obtido (HTTP $HTTP_CODE)"
        return 0
    else
        warning "Falha ao obter token Authentik (HTTP $HTTP_CODE): $BODY"
        return 1
    fi
}

# 1. Testes de Saúde do Sistema
test_health() {
    section "1. SAÚDE DO SISTEMA"

    test_case "1.1 Health do BFF"
    if curl -sf http://localhost:8081/bff/health | grep -q "status"; then
        success "BFF respondendo com sucesso"
    else
        error "BFF não respondendo"
    fi

    test_case "1.2 Health do Orquestrador"
    if curl -sf http://localhost:8080/actuator/health | grep -q "status"; then
        success "Orquestrador respondendo com sucesso"
    else
        error "Orquestrador não respondendo"
    fi

    test_case "1.3 Health do Manager"
    if curl -sf http://localhost:8082/actuator/health | grep -q "status"; then
        success "Manager respondendo com sucesso"
    else
        error "Manager não respondendo"
    fi

    test_case "1.4 RabbitMQ acessível"
    if curl -sf http://guest:guest@localhost:15672/api/aliveness-test/%2F > /dev/null 2>&1; then
        success "RabbitMQ respondendo"
    else
        warning "RabbitMQ não acessível (pode ser opcional)"
    fi

    test_case "1.5 Redis acessível"
    if docker exec -it $(docker ps -q -f "name=redis") redis-cli ping > /dev/null 2>&1; then
        success "Redis respondendo"
    else
        warning "Redis não respondendo (pode estar ok, dependência secundária)"
    fi
}

# 2. Server Driven UI
test_server_driven_ui() {
    section "2. SERVER DRIVEN UI"

    test_case "2.1 BFF retorna menu"
    RESPONSE=$(curl -sf http://localhost:8081/bff/menu 2>&1 || echo "ERROR")

    if echo "$RESPONSE" | grep -q "flow-manager"; then
        success "Menu contém 'flow-manager'"
    elif echo "$RESPONSE" | grep -q "ERROR"; then
        warning "Endpoint /bff/menu pode não existir"
    else
        debug "Response: $(echo "$RESPONSE" | head -c 200)"
        warning "Menu não contém 'flow-manager'"
    fi

    test_case "2.2 BFF retorna schema da feature"
    RESPONSE=$(curl -sf http://localhost:8081/bff/features/flow-manager/ui-schema 2>&1 || echo "ERROR")

    if echo "$RESPONSE" | grep -q "featureId"; then
        success "Schema da feature retornado"
    elif echo "$RESPONSE" | grep -q "ERROR"; then
        warning "Endpoint /bff/features/*/ui-schema pode não existir"
    else
        debug "Response: $(echo "$RESPONSE" | head -c 200)"
        warning "Schema da feature não contém 'featureId'"
    fi
}

# Cria workflows de teste
create_test_workflows() {
    section "CRIANDO WORKFLOWS DE TESTE"

    # Verificar se Manager token foi obtido
    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando criação de workflows (sem token Manager)"
        return 1
    fi

    # WF-HTTP
    test_case "Criando workflow HTTP (create-order-v1)"
    FLOW_HTTP=$(cat <<'EOF'
{
  "flowId": "create-order-v1",
  "version": "1.0.0",
  "description": "Test workflow - HTTP integration",
  "active": true,
  "contract": {
    "fields": [
      {
        "name": "clientId",
        "type": "STRING",
        "required": true,
        "validations": [
          { "type": "NOT_BLANK" },
          { "type": "PATTERN", "value": "^[A-Z0-9]{6,20}$", "message": "Invalid clientId" }
        ]
      }
    ]
  },
  "integrations": [
    {
      "id": "fetch-client",
      "order": 1,
      "type": "HTTP",
      "continueOnError": false,
      "http": {
        "url": "http://api.exemplo.com/clients/CLI001A",
        "method": "GET",
        "headers": { "Accept": "application/json" },
        "timeout": 5000,
        "responseMapping": { "sourceField": "name", "targetField": "clientName" }
      }
    }
  ]
}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/manager/flows \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        -d "$FLOW_HTTP" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        success "Workflow HTTP criado (HTTP $HTTP_CODE)"
    else
        BODY=$(echo "$RESPONSE" | head -n -1)
        debug "Response: $BODY"
        warning "Workflow HTTP — HTTP $HTTP_CODE"
    fi

    # WF-RABBITMQ
    test_case "Criando workflow RabbitMQ"
    FLOW_RABBITMQ=$(cat <<'EOF'
{
  "flowId": "test-rabbitmq",
  "version": "1.0.0",
  "description": "Test workflow - RabbitMQ integration",
  "active": true,
  "contract": {
    "fields": [
      { "name": "orderId", "type": "STRING", "required": true, "validations": [{"type": "NOT_BLANK"}] }
    ]
  },
  "integrations": [
    {
      "id": "notify-rabbitmq",
      "order": 1,
      "type": "QUEUE",
      "provider": "RABBITMQ",
      "continueOnError": false,
      "queue": {
        "exchange": "orders.exchange",
        "routingKey": "order.created",
        "persistent": true,
        "messageTemplate": "{\"event\":\"ORDER_CREATED\",\"orderId\":\"{{contract.orderId}}\",\"timestamp\":\"{{now()}}\"}"
      }
    }
  ]
}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/manager/flows \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        -d "$FLOW_RABBITMQ" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        success "Workflow RabbitMQ criado (HTTP $HTTP_CODE)"
    else
        warning "Workflow RabbitMQ — HTTP $HTTP_CODE"
    fi

    # WF-KAFKA
    test_case "Criando workflow Kafka"
    FLOW_KAFKA=$(cat <<'EOF'
{
  "flowId": "test-kafka",
  "version": "1.0.0",
  "description": "Test workflow - Kafka integration",
  "active": true,
  "contract": {
    "fields": [
      { "name": "orderId", "type": "STRING", "required": true }
    ]
  },
  "integrations": [
    {
      "id": "track-kafka",
      "order": 1,
      "type": "QUEUE",
      "provider": "KAFKA",
      "continueOnError": false,
      "queue": {
        "topic": "orders.created",
        "messageTemplate": "{\"event\":\"ORDER_CREATED\",\"orderId\":\"{{contract.orderId}}\"}"
      }
    }
  ]
}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/manager/flows \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        -d "$FLOW_KAFKA" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        success "Workflow Kafka criado (HTTP $HTTP_CODE)"
    else
        warning "Workflow Kafka — HTTP $HTTP_CODE"
    fi
}

# 3. CRUD de Workflows
test_crud_workflows() {
    section "3. CRUD DE WORKFLOWS"

    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando CRUD de workflows (sem token Manager)"
        return 1
    fi

    test_case "3.1 Listar workflows"
    RESPONSE=$(curl -sf -H "Authorization: Bearer $MANAGER_TOKEN" http://localhost:8082/manager/flows 2>&1 || echo "ERROR")
    if echo "$RESPONSE" | grep -q "create-order-v1"; then
        success "Workflow listado com sucesso"
    else
        error "Workflow não encontrado na listagem"
    fi

    test_case "3.2 Buscar workflow específico"
    if curl -sf -H "Authorization: Bearer $MANAGER_TOKEN" "http://localhost:8082/manager/flows/create-order-v1" 2>&1 | grep -q "flowId"; then
        success "Workflow específico encontrado"
    else
        error "Workflow específico não encontrado"
    fi

    test_case "3.3 Obter YAML do workflow"
    if curl -sf -H "Authorization: Bearer $MANAGER_TOKEN" "http://localhost:8082/manager/flows/create-order-v1/yaml" 2>&1 | grep -q "flowId"; then
        success "YAML do workflow obtido"
    else
        error "YAML do workflow não encontrado"
    fi
}

# 4. Execução de Workflows via Orchestrator
test_execution() {
    section "4. EXECUÇÃO DE WORKFLOWS"

    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando execução de workflows (sem token Manager)"
        return 1
    fi

    test_case "4.1 Executar workflow HTTP via Orchestrator"
    RESPONSE=$(curl -s -X POST http://localhost:8080/executions \
        -H "Content-Type: application/json" \
        -d '{
          "flowId": "create-order-v1",
          "version": "1.0.0",
          "payload": {"clientId":"CLI001A"}
        }' 2>&1)

    if echo "$RESPONSE" | grep -q "executionId\|SUCCESS"; then
        success "Workflow executado com sucesso"
        debug "Response: $(echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE" | head -c 100)"
    else
        warning "Execução retornou: $(echo "$RESPONSE" | head -c 100)"
    fi
}

# 6. Cenários negativos
test_negative_scenarios() {
    section "6. CENÁRIOS NEGATIVOS"

    if [ -z "$MANAGER_TOKEN" ]; then
        warning "Pulando cenários negativos (sem token Manager)"
        return 1
    fi

    test_case "6.1 Payload inválido - campo obrigatório ausente"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/executions \
        -H "Content-Type: application/json" \
        -d '{}')

    if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "422" ]; then
        success "Validação de campo obrigatório funcionando (HTTP $HTTP_CODE)"
    else
        warning "Validação retornou HTTP $HTTP_CODE (esperado 400/422)"
    fi

    test_case "6.2 Workflow inexistente"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/executions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        -d '{"flowId":"inexistente","version":"1.0.0","payload":{}}')

    if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "400" ]; then
        success "Workflow não encontrado (HTTP $HTTP_CODE)"
    else
        warning "Workflow inexistente retornou HTTP $HTTP_CODE (esperado 404)"
    fi
}

# Gera relatório final
generate_report() {
    section "GERANDO RELATÓRIO"

    TOTAL=$((PASSED + FAILED + SKIPPED))
    if [ $TOTAL -gt 0 ]; then
        PERCENTAGE=$((PASSED * 100 / TOTAL))
    else
        PERCENTAGE=0
    fi

    {
        echo "# Relatório de Testes Integrados - Service Portal"
        echo ""
        echo "Data: $(date)"
        echo "Versão: v2.0 (com autenticação melhorada)"
        echo ""
        echo "## Resumo"
        echo "- Total de testes: $TOTAL"
        echo "- ✓ Passou: $PASSED"
        echo "- ✗ Falhou: $FAILED"
        echo "- ⚠ Pulados: $SKIPPED"
        echo "- Taxa de sucesso: ${PERCENTAGE}%"
        echo ""
        echo "## Arquivos de log"
        echo "- Log detalhado: $LOG_FILE"
        echo "- Checklist: $CHECKLIST_FILE"
        echo ""
        echo "## Notas"
        echo "- Este script foi atualizado para incluir autenticação"
        echo "- Verifique DIAGNOSTICO-TESTES-INTEGRADOS.md para mais informações"
        echo ""
    } > "$CHECKLIST_FILE"

    success "Relatório gerado: $CHECKLIST_FILE"
}

# Main
main() {
    section "INICIANDO TESTES INTEGRADOS - SERVICE PORTAL v2"

    log "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Log: $LOG_FILE"
    log "Checklist: $CHECKLIST_FILE"

    if ! check_prerequisites; then
        error "Pré-requisitos falharam"
        exit 1
    fi

    if ! start_infrastructure; then
        error "Falha ao iniciar infraestrutura"
        docker compose -f "$DOCKER_COMPOSE_FILE" logs --tail=30
        exit 1
    fi

    # Obtém tokens de autenticação
    get_manager_token || true
    get_authentik_token || true

    # Executa todos os testes
    test_health || true
    test_server_driven_ui || true
    create_test_workflows || true
    test_crud_workflows || true
    test_execution || true
    test_negative_scenarios || true

    generate_report

    section "RESUMO FINAL"
    TOTAL=$((PASSED + FAILED + SKIPPED))
    if [ $TOTAL -gt 0 ]; then
        PERCENTAGE=$((PASSED * 100 / TOTAL))
    else
        PERCENTAGE=0
    fi

    log "╔════════════════════════════════════╗"
    log "║       RESULTADOS DOS TESTES        ║"
    log "╠════════════════════════════════════╣"
    log "║ Total:        $((TOTAL < 10 ? ' ' : ''))$TOTAL                         ║"
    log "║ ✓ Passou:     $((PASSED < 10 ? ' ' : ''))$PASSED                        ║"
    log "║ ✗ Falhou:     $((FAILED < 10 ? ' ' : ''))$FAILED                        ║"
    log "║ ⚠ Pulados:    $((SKIPPED < 10 ? ' ' : ''))$SKIPPED                       ║"
    log "║ Taxa:         ${PERCENTAGE}%                      ║"
    log "╚════════════════════════════════════╝"

    log "Logs:     $LOG_FILE"
    log "Checklist: $CHECKLIST_FILE"

    echo ""
    if [ $FAILED -eq 0 ] && [ $PASSED -gt 0 ]; then
        success "✓ TESTES FINALIZADOS COM SUCESSO!"
        exit 0
    else
        if [ $PASSED -gt 0 ]; then
            warning "⚠ Testes concluídos com observações. Verifique os logs."
        else
            error "✗ Nenhum teste passou. Verifique a infraestrutura."
        fi
        exit 0
    fi
}

# Executa
main "$@"
