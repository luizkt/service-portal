import http from 'k6/http'
import { check, sleep } from 'k6'

// =====================================================================
// Teste de performance: comparativo v1 (sequencial) x v2 (paralelo) do
// generic-orchestrator. O workflow perf-test-flow tem 6 integrações HTTP
// no MESMO order (1) apontando para o stub lento do WireMock (~500ms cada):
//   - v1: execução sequencial  → ~3000ms por requisição
//   - v2: Java Virtual Threads → ~500ms  por requisição
//
// Parametrização via variáveis de ambiente:
//   API_VERSION  v1 | v2            (default v1)
//   ORCH_URL     base do orquestrador (default http://orchestrator:8080)
//   VUS          usuários virtuais  (default 10)
//   DURATION     duração            (default 30s)
//   FLOW_ID      workflow alvo      (default perf-test-flow)
//
// Execução (via Docker, na rede do compose):
//   docker run --rm --network service-portal_portal \
//     -v "$PWD/tests/performance:/scripts:ro" \
//     -e API_VERSION=v2 -e VUS=10 -e DURATION=30s \
//     grafana/k6 run /scripts/orchestrator-test.js
// =====================================================================

const ORCH_URL = __ENV.ORCH_URL || 'http://orchestrator:8080'
const API_VERSION = __ENV.API_VERSION || 'v1'
const FLOW_ID = __ENV.FLOW_ID || 'perf-test-flow'
const VUS = parseInt(__ENV.VUS || '10', 10)
const DURATION = __ENV.DURATION || '30s'

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ['rate<0.01'], // < 1% de erros de transporte
    http_req_duration: ['p(95)<8000'], // teto generoso; o comparativo é o foco
  },
}

// Login uma única vez no início — evita enviesar o teste com latência de auth.
export function setup() {
  const res = http.post(
    `${ORCH_URL}/api/auth/tokens`,
    JSON.stringify({ username: 'admin', password: 'admin' }),
    { headers: { 'Content-Type': 'application/json' } },
  )
  const token = res.json('token')
  if (!token) {
    throw new Error(`Falha no login do orquestrador (HTTP ${res.status}): ${res.body}`)
  }
  return { token }
}

export default function (data) {
  const url = `${ORCH_URL}/api/${API_VERSION}/flows/${FLOW_ID}/versions/1.0.0/executions`
  const payload = JSON.stringify({ refId: 'PERF001' })
  const params = {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${data.token}`,
    },
  }

  const res = http.post(url, payload, params)

  check(res, {
    'status HTTP 200': (r) => r.status === 200,
    'workflow SUCCESS': (r) => r.body && r.body.includes('"status":"SUCCESS"'),
    'não é 5xx': (r) => r.status < 500,
  })

  sleep(0.5)
}
