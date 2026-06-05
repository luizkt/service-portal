# PLAN: Teste de Performance Orquestrador (v1 vs v2) com k6

## Contexto
A implementação do endpoint v2 no `generic-orchestrator` utiliza **Java Virtual Threads** para disparar integrações de mesma ordem em paralelo. Para justificar essa arquitetura, precisamos quantificar o ganho de vazão (throughput) e a redução de latência sob carga, comparando o modelo sequencial (v1) com o paralelo (v2).

## Objetivos
1.  **Comparativo de Latência**: Validar a redução do tempo de resposta em workflows com múltiplos passos I/O-bound.
2.  **Escalabilidade**: Identificar até quantos usuários simultâneos (VUs) o orquestrador suporta antes de degradar a performance.
3.  **Eficiência de Recursos**: Monitorar o consumo de CPU e Memória (Virtual Threads devem ser mais leves que Platform Threads para alta concorrência).

## Ferramentas e Infraestrutura
-   **k6**: Motor de teste de carga (escrito em Go, scripts em JS).
-   **WireMock**: Configurado com `fixedDelayMilliseconds` de 500ms para simular chamadas de rede reais.
-   **Docker Stats / Portainer**: Para monitoramento visual de recursos durante o teste.

## Cenários de Teste

### 1. Baseline (Carga Baixa)
- 1 VU (Virtual User) executando 10 iterações.
- Objetivo: Confirmar os tempos mínimos (v1: ~3s vs v2: ~0.5s para um fluxo de 6 passos).

### 2. Load Test (Carga Sustentada)
- 20 VUs simultâneos durante 2 minutos.
- Objetivo: Observar o comportamento do pool de conexões e a latência P95.

### 3. Stress Test (Ponto de Ruptura)
- Ramp-up de 0 a 100 VUs em 5 minutos.
- Objetivo: Identificar quando o sistema começa a retornar erros (5xx) ou quando a latência v2 se iguala à v1 por saturação de CPU.

## Detalhes Técnicos do Script k6

O script deverá ser criado em `tests/performance/orchestrator-test.js` e seguir esta estrutura:

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
    thresholds: {
        http_req_failed: ['rate<0.01'], // Erros menores que 1%
        http_req_duration: ['p(95)<4000'], // 95% das reqs abaixo de 4s
    },
};

export default function () {
    const version = __ENV.API_VERSION || 'v1';
    const url = `http://localhost:8080/api/${version}/flows/perf-test-flow/versions/1.0.0/executions`;
    
    const payload = JSON.stringify({ clientId: "PERF_001", amount: 100 });
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${__ENV.TOKEN}`
        },
    };

    const res = http.post(url, payload, params);
    
    check(res, {
        'status is 200': (r) => r.status === 200,
        'status is not 500': (r) => r.status !== 500,
    });
    
    sleep(1);
}
```

## Preparação dos Dados
1.  **Workflow de Teste**: Criar o `perf-test-flow` com 6 integrações HTTP de `order: 1`.
2.  **WireMock**: Adicionar um mapping genérico para responder em 500ms para qualquer ID de teste.
3.  **Auth**: O script k6 deve realizar o login uma única vez no início (`setup`) para não enviesar o teste de execução com latência de auth.

## Resultados Esperados

| Métrica | v1 (Sequencial) | v2 (Virtual Threads) |
|---|---|---|
| **Latência (6 steps @ 500ms)** | ~3000ms | ~550ms |
| **Throughput (20 VUs)** | ~6 req/s | ~35 req/s |
| **Comportamento CPU** | Picos altos (thread blocking) | Estável / Linear |

## Próximos Passos
1. Instalar k6 localmente ou via Docker.
2. Criar o diretório `tests/performance`.
3. Implementar o workflow de teste no Manager.
4. Executar e documentar os resultados em `docs/performance/RESULTS-v1-vs-v2.md`.