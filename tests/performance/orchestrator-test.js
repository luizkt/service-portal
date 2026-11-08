import http from 'k6/http'
import { check, sleep } from 'k6'
import { Rate } from 'k6/metrics'

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
//   MIN_SUCCESS  fração mínima de SUCCESS (default 0.99)
//   P95_MAX_MS   teto do p95 em ms  (default 8000)
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
// Limiares de aprovação. O stress usa valores frouxos: ele existe para achar a saturação, não para aprovar.
const MIN_SUCCESS = parseFloat(__ENV.MIN_SUCCESS || '0.99')
const P95_MAX_MS = parseInt(__ENV.P95_MAX_MS || '8000', 10)

// Fração de execuções com "status":"SUCCESS" no corpo. O orquestrador responde 200 mesmo quando o
// fluxo falha (status FAILED), então http_req_failed sozinho não enxerga circuito aberto, timeout
// de integração etc. Sem este limiar a carga "passa" medindo respostas de erro rápidas.
const workflowSuccess = new Rate('workflow_success')

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ['rate<0.01'], // < 1% de erros de transporte
    http_req_duration: [`p(95)<${P95_MAX_MS}`], // teto generoso; o comparativo é o foco
    // Aborta cedo: depois de 10s, SUCCESS abaixo do mínimo invalida a medição.
    workflow_success: [{ threshold: `rate>${MIN_SUCCESS}`, abortOnFail: true, delayAbortEval: '10s' }],
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

  const success = !!res.body && res.body.includes('"status":"SUCCESS"')
  workflowSuccess.add(success)

  check(res, {
    'status HTTP 200': (r) => r.status === 200,
    'workflow SUCCESS': () => success,
    'não é 5xx': (r) => r.status < 500,
  })

  sleep(0.5)
}
