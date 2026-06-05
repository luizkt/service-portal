#!/bin/bash
# Cria o workflow perf-test-flow (6 integrações HTTP no mesmo order, stub lento
# /slow do WireMock ~500ms) usado pelo teste de carga k6 (orchestrator-test.js).
# Idempotente: 409 (já existe) é tratado como sucesso.
#
# Uso: ./tests/performance/setup-perf-flow.sh
set -euo pipefail

MGR_URL="${MGR_URL:-http://localhost:8082}"
ORCH_URL="${ORCH_URL:-http://localhost:8080}"
REDIS_CONTAINER="${REDIS_CONTAINER:-portal-redis}"

MGR_TOKEN=$(curl -s -X POST "$MGR_URL/api/auth/tokens" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

[ -n "$MGR_TOKEN" ] || { echo "Falha ao obter token do Manager"; exit 1; }

read -r -d '' YAML <<'EOF' || true
flow:
  id: perf-test-flow
  version: "1.0.0"
  description: "Performance test - 6 HTTP integrations at order 1 (slow stub 500ms)"
  active: true
  contract:
    fields:
      - name: refId
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
  integrations:
    - id: perf-1
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P1", method: GET, timeout: 10000 }
    - id: perf-2
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P2", method: GET, timeout: 10000 }
    - id: perf-3
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P3", method: GET, timeout: 10000 }
    - id: perf-4
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P4", method: GET, timeout: 10000 }
    - id: perf-5
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P5", method: GET, timeout: 10000 }
    - id: perf-6
      order: 1
      type: HTTP
      continueOnError: false
      http: { url: "http://api.exemplo.com/slow/P6", method: GET, timeout: 10000 }
EOF

CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$MGR_URL/manager/flows" \
    -H "Content-Type: text/plain" \
    -H "Authorization: Bearer $MGR_TOKEN" \
    --data-raw "$YAML")

case "$CODE" in
    201) echo "perf-test-flow criado (201)" ;;
    409) echo "perf-test-flow já existe (409 — ok)" ;;
    *)   echo "Falha ao criar perf-test-flow (HTTP $CODE)"; exit 1 ;;
esac

# Garante que o orquestrador recarregue o workflow (evita servir cache vazio/stale).
docker exec "$REDIS_CONTAINER" redis-cli FLUSHALL >/dev/null 2>&1 \
    && echo "Cache Redis do orquestrador limpo" \
    || echo "Aviso: não foi possível limpar o Redis (container $REDIS_CONTAINER)"
