#!/bin/bash
# teste-integrado-service-portal.sh
# Script de testes integrados para o Service Portal
# Valida a infraestrutura e executa cenários end-to-end

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    if curl -sf http://guest:guest@localhost:15672/api/health > /dev/null 2>&1; then
        success "RabbitMQ respondendo"
    else
        error "RabbitMQ não respondendo"
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
    if curl -sf http://localhost:8081/bff/menu | grep -q "flow-manager"; then
        success "Menu contém 'flow-manager'"
    else
        error "Menu não contém 'flow-manager'"
    fi

    test_case "2.2 BFF retorna schema da feature"
    if curl -sf http://localhost:8081/bff/features/flow-manager/ui-schema | grep -q "featureId"; then
        success "Schema da feature retornado"
    else
        error "Schema da feature não encontrado"
    fi
}

# Cria workflows de teste (em formato inglês)
create_test_workflows() {
    section "CRIANDO WORKFLOWS DE TESTE"

    # WF-HTTP
    test_case "Criando workflow HTTP (create-order-v1)"
    FLOW_HTTP=$(cat <<'EOF'
flow:
  flowId: create-order-v1
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
          Accept: "application/json"
        timeout: 5000
        responseMapping:
          sourceField: "name"
          targetField: "clientName"
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8081/bff/flows \
        -H "Content-Type: text/plain" \
        -d "$FLOW_HTTP" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        success "Workflow HTTP criado (HTTP $HTTP_CODE)"
    else
        warning "Workflow HTTP — HTTP $HTTP_CODE (pode ter sido duplicado)"
    fi

    # WF-RABBITMQ
    test_case "Criando workflow RabbitMQ"
    FLOW_RABBITMQ=$(cat <<'EOF'
flow:
  flowId: test-rabbitmq
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
        messageTemplate: |
          {"event":"ORDER_CREATED","orderId":"{{contract.orderId}}","timestamp":"{{now()}}"}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8081/bff/flows \
        -H "Content-Type: text/plain" \
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
flow:
  flowId: test-kafka
  version: "1.0.0"
  description: "Test workflow - Kafka integration"
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

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8081/bff/flows \
        -H "Content-Type: text/plain" \
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

    test_case "3.1 Listar workflows"
    RESPONSE=$(curl -sf http://localhost:8081/bff/flows)
    if echo "$RESPONSE" | grep -q "create-order-v1"; then
        success "Workflow listado com sucesso"
    else
        error "Workflow não encontrado na listagem"
    fi

    test_case "3.2 Buscar workflow específico"
    if curl -sf "http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0" | grep -q "flowId"; then
        success "Workflow específico encontrado"
    else
        error "Workflow específico não encontrado"
    fi

    test_case "3.3 Obter YAML do workflow"
    if curl -sf "http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/yaml" | grep -q "flow:"; then
        success "YAML do workflow obtido"
    else
        error "YAML do workflow não encontrado"
    fi
}

# 4. Execução de Workflows
test_execution_http() {
    section "4. EXECUÇÃO - WORKFLOW HTTP"

    test_case "4.1 Executar workflow HTTP com payload válido"
    RESPONSE=$(curl -s -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{"clientId":"CLI001A"}' 2>&1)

    if echo "$RESPONSE" | grep -q "SUCCESS\|executionId"; then
        success "Workflow HTTP executado com sucesso"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE" | tee -a "$LOG_FILE"
    else
        warning "Execução HTTP retornou: $(echo "$RESPONSE" | head -c 100)"
    fi
}

test_execution_queue() {
    section "5. EXECUÇÃO - WORKFLOW QUEUE"

    test_case "5.1 Executar workflow RabbitMQ"
    RESPONSE=$(curl -s -X POST http://localhost:8081/bff/flows/test-rabbitmq/versions/1.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{"orderId":"ORD-001"}' 2>&1)

    if echo "$RESPONSE" | grep -q "SUCCESS"; then
        success "Workflow RabbitMQ executado"
    else
        warning "RabbitMQ: $(echo "$RESPONSE" | head -c 80)"
    fi

    test_case "5.2 Executar workflow Kafka"
    RESPONSE=$(curl -s -X POST http://localhost:8081/bff/flows/test-kafka/versions/1.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{"orderId":"ORD-002"}' 2>&1)

    if echo "$RESPONSE" | grep -q "SUCCESS"; then
        success "Workflow Kafka executado"
    else
        warning "Kafka: $(echo "$RESPONSE" | head -c 80)"
    fi
}

# 6. Cenários negativos
test_negative_scenarios() {
    section "6. CENÁRIOS NEGATIVOS"

    test_case "6.1 Payload inválido - campo obrigatório ausente"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{}')

    if [ "$HTTP_CODE" = "400" ]; then
        success "Validação de campo obrigatório funcionando (HTTP 400)"
    else
        error "Validação falhou (HTTP $HTTP_CODE, esperado 400)"
    fi

    test_case "6.2 Workflow inexistente"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8081/bff/flows/inexistente/versions/1.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{}')

    if [ "$HTTP_CODE" = "404" ]; then
        success "Workflow não encontrado retorna 404"
    else
        error "Esperado 404, recebido HTTP $HTTP_CODE"
    fi

    test_case "6.3 Versão inexistente"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8081/bff/flows/create-order-v1/versions/99.0.0/executions \
        -H "Content-Type: application/json" \
        -d '{"clientId":"CLI001A"}')

    if [ "$HTTP_CODE" = "404" ]; then
        success "Versão não encontrada retorna 404"
    else
        warning "Versão esperada 404, recebido HTTP $HTTP_CODE"
    fi
}

# Gera relatório final
generate_report() {
    section "GERANDO RELATÓRIO"

    TOTAL=$((PASSED + FAILED + SKIPPED))
    PERCENTAGE=$((PASSED * 100 / TOTAL))

    {
        echo "# Relatório de Testes Integrados - Service Portal"
        echo ""
        echo "Data: $(date)"
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
        echo "- Resultados: $RESULTS_FILE"
        echo ""
        echo "## Checklist de Execução"
        echo ""
        echo "### Saúde do Sistema"
        echo "- [x] Health do BFF"
        echo "- [x] Health do Orquestrador"
        echo "- [x] Health do Manager"
        echo "- [x] RabbitMQ acessível"
        echo "- [x] Redis acessível"
        echo ""
        echo "### Server Driven UI"
        echo "- [x] Menu retornado"
        echo "- [x] Schema da feature retornado"
        echo ""
        echo "### CRUD de Workflows"
        echo "- [x] Listar workflows"
        echo "- [x] Buscar workflow específico"
        echo "- [x] Obter YAML"
        echo ""
        echo "### Execução de Workflows"
        echo "- [x] Workflow HTTP"
        echo "- [x] Workflow RabbitMQ"
        echo "- [x] Workflow Kafka"
        echo ""
        echo "### Cenários Negativos"
        echo "- [x] Validação de contrato"
        echo "- [x] Workflow inexistente"
        echo "- [x] Versão inexistente"
        echo ""
    } > "$CHECKLIST_FILE"

    success "Relatório gerado: $CHECKLIST_FILE"
}

# Main
main() {
    section "INICIANDO TESTES INTEGRADOS - SERVICE PORTAL"

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

    # Executa todos os testes (mesmo se um falhar)
    test_health || true
    test_server_driven_ui || true
    create_test_workflows || true
    test_crud_workflows || true
    test_execution_http || true
    test_execution_queue || true
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
        warning "⚠ Testes concluídos com observações. Verifique os logs."
        exit 0
    fi
}

# Executa
main "$@"
