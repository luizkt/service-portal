import http from 'k6/http'
import { check, sleep } from 'k6'
import { Rate } from 'k6/metrics'

// =====================================================================
// Teste de performance: comparativo v1 (sequencial) x v2 (threads físicas) x
// v3 (virtual threads) do generic-orchestrator. O workflow perf-test-flow tem 6 integrações HTTP
// no MESMO order (1) apontando para o stub lento do WireMock (~500ms cada):
//   - v1: execução sequencial  → ~3000ms por requisição
//   - v2: threads físicas (pool fixo compartilhado) → ~500ms por requisição,
//         degrada ao saturar o pool (6 tarefas/req; pool default 200)
//   - v3: Java Virtual Threads (1 por tarefa) → ~500ms por requisição
//
// Parametrização via variáveis de ambiente:
//   API_VERSION  v1 | v2 | v3       (default v1)
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
//     -e API_VERSION=v3 -e VUS=10 -e DURATION=30s \
//     grafana/k6 run /scripts/orchestrator-test.js
// =====================================================================

// O orquestrador responde HTTP 200 mesmo quando o flow termina FAILED (o status vem no
// corpo), então http_req_failed NÃO enxerga falhas de negócio. workflow_success é true
// somente com HTTP 200 E "status":"SUCCESS" no corpo; a latência só é comparável entre
// versões quando workflow_success = 100%.
const workflowSuccess = new Rate('workflow_success')

const ORCH_URL = __ENV.ORCH_URL || 'http://orchestrator:8080'
const API_VERSION = __ENV.API_VERSION || 'v1'
const FLOW_ID = __ENV.FLOW_ID || 'perf-test-flow'
if (!['v1', 'v2', 'v3'].includes(API_VERSION)) {
  throw new Error(`API_VERSION inválida: ${API_VERSION} (use v1, v2 ou v3)`)
}
const VUS = parseInt(__ENV.VUS || '10', 10)
const DURATION = __ENV.DURATION || '30s'
// Limiares de aprovação. Stress e spike usam valores frouxos: existem para achar a saturação, não para aprovar.
const MIN_SUCCESS = parseFloat(__ENV.MIN_SUCCESS || '0.99')
const P95_MAX_MS = parseInt(__ENV.P95_MAX_MS || '8000', 10)

export const options = {
  // setup() faz login; após execuções pesadas o orquestrador pode demorar a responder
  setupTimeout: '120s',
  vus: VUS,
  duration: DURATION,
  // Tag aplicada a todas as métricas/checks para facilitar a comparação.
  tags: { version: API_VERSION },
  thresholds: {
    http_req_failed: ['rate<0.01'], // < 1% de erros de transporte
    http_req_duration: [`p(95)<${P95_MAX_MS}`], // teto generoso; o comparativo é o foco
    // Falha a execução se o fluxo falha (circuito aberto, timeout de integração etc.).
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

  workflowSuccess.add(res.status === 200 && !!res.body && res.body.includes('"status":"SUCCESS"'), {
    version: API_VERSION,
  })

  check(res, {
    'status HTTP 200': (r) => r.status === 200,
    'workflow SUCCESS': (r) => r.body && r.body.includes('"status":"SUCCESS"'),
    'não é 5xx': (r) => r.status < 500,
  })

  sleep(0.5)
}
