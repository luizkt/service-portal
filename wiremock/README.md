# WireMock — Simulador de APIs externas

Container WireMock usado pelo `generic-orchestrator` para simular APIs HTTP externas em desenvolvimento e testes integrados.

## Como funciona

No `docker-compose-service-portal.yml`, o serviço `wiremock` recebe **aliases de rede** que permitem aos demais containers chamá-lo pelo hostname público da API simulada — sem alterar URLs nos workflows.

| Alias na rede `portal` | Origem (workflow) |
|---|---|
| `api.exemplo.com` | URLs `http://api.exemplo.com/...` em `docs/example-flow.yml` |

Quando o orquestrador resolve `http://api.exemplo.com/clientes/ABC123`, o DNS interno do Docker direciona a chamada ao container WireMock (porta 8080).

## Estrutura

```
wiremock/
├── mappings/                       # Stubs (matchers + responses)
│   ├── clientes-get-by-id.json     # GET /clientes/{[A-Z0-9]{6,20}} → 200
│   └── clientes-get-not-found.json # GET /clientes/* → 404 (fallback, prioridade 10)
└── __files/                        # Arquivos referenciados via "bodyFileName"
```

Ambas as pastas são montadas em `/home/wiremock/mappings` e `/home/wiremock/__files` no container.

## Mappings atuais

### `GET /clientes/{clienteId}` (200)

Retorna um cliente fictício para `clienteId` que case com o padrão `[A-Z0-9]{6,20}` — exatamente o regex que o `criar-pedido-v1` exige no contrato:

```bash
curl -i http://localhost:18080/clientes/ABC123
# HTTP/1.1 200 OK
# Content-Type: application/json
# {"clienteId":"ABC123","nome":"Cliente Simulado WireMock", ...}
```

O template `{{request.pathSegments.[1]}}` (Handlebars do WireMock) ecoa o `clienteId` recebido na resposta.

### `GET /clientes/*` (404)

Fallback com `priority: 10` (mais alta = menor prioridade). Captura qualquer GET em `/clientes/...` que **não** case com o padrão acima:

```bash
curl -i http://localhost:18080/clientes/foo
# HTTP/1.1 404 Not Found
# {"error":"NOT_FOUND","message":"Cliente não encontrado"}
```

## Adicionando novos mappings

1. Criar `wiremock/mappings/<nome>.json` (sintaxe oficial do WireMock).
2. Se a resposta for um arquivo grande, salvar em `wiremock/__files/` e referenciar via `"bodyFileName"`.
3. `docker compose restart wiremock` (ou usar `POST /__admin/mappings/reset` na admin API).

Documentação completa: <https://wiremock.org/docs/stubbing/>.

## Acesso direto (debug)

Por padrão a porta admin/HTTP do WireMock é exposta em `localhost:18080` (configurável via `WIREMOCK_PORT` no `.env`):

```bash
# Listar todos os stubs ativos
curl http://localhost:18080/__admin/mappings | jq

# Ver as últimas requisições recebidas
curl http://localhost:18080/__admin/requests | jq
```
