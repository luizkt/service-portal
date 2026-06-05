# PLAN: Dados de exemplo no `init-mongo.js`

## Contexto

O `init-mongo.js` atualmente cria apenas as collections e os índices. Sem dados de exemplo, o ambiente local começa vazio — o desenvolvedor precisa criar manualmente workflows, contracts, integrations e validations antes de testar qualquer coisa.

O objetivo é inserir documentos de exemplo coerentes entre si ao inicializar o MongoDB, permitindo que a stack suba pronta para desenvolvimento e testes sem nenhuma configuração manual.

> **Dependência:** Este plano assume que a pendência #2 (mover `mongodb-workflows/` para o Manager) já foi implementada. O arquivo editado é `service-portal-manager/mongodb-manager/init-mongo.js` (novo caminho) e o database é `service-portal-manager`. Se a pendência #2 ainda não foi feita, o arquivo está em `generic-orchestrator/mongodb-workflows/init-mongo.js` e o database é `generic-orchestrator`.

---

## Escopo

| Arquivo | Mudança |
|---|---|
| `service-portal-manager/mongodb-manager/init-mongo.js` | Adicionar `insertOne()` para as 4 collections após criação dos índices |
| `wiremock/mappings/` | Adicionar `clients-credit-get.json` para o endpoint `/clients/{id}/credit` (usado pela validation `check-credit-limit`) |

---

## Dados de exemplo

Os dados são extraídos do `generic-orchestrator/docs/example-flow.yml`, que é a fonte de verdade do fluxo de demonstração.

### `contracts` — `create-order`

| Campo | Valor |
|---|---|
| `contractId` | `"create-order"` |
| `version` | `1` |
| `fields` | `clientId` (STRING, obrigatório, NOT_BLANK + PATTERN `^[A-Z0-9]{6,20}$`) e `amount` (DECIMAL, obrigatório, POSITIVE) |

### `integrations` — `validate-client` e `save-order`

| Campo | `validate-client` | `save-order` |
|---|---|---|
| `integrationId` | `"validate-client"` | `"save-order"` |
| `version` | `1` | `1` |
| `type` | `"HTTP"` | `"HTTP"` |
| `url` | `"http://api.exemplo.com/clients/{{contract.clientId}}"` | `"http://api.exemplo.com/orders"` |
| `method` | `"GET"` | `"POST"` |
| `headers` | `{"Content-Type": "application/json"}` | `{"Content-Type": "application/json"}` |
| `timeout` | `5000` | `5000` |
| `bodyTemplate` | `null` | `{"clientId":"{{contract.clientId}}","amount":"{{contract.amount}}","status":"CREATED"}` |
| `responseBody` | Exemplo simulado pelo WireMock | Exemplo: `{"id": "ORD-001", "status": "CREATED"}` |

### `validations` — `check-credit-limit`

| Campo | Valor |
|---|---|
| `validationId` | `"check-credit-limit"` |
| `version` | `1` |
| `type` | `"HTTP"` |
| `url` | `"http://api.exemplo.com/clients/{{contract.clientId}}/credit"` |
| `method` | `"GET"` |
| `headers` | `{"Content-Type": "application/json"}` |
| `timeout` | `5000` |
| `responseBody` | Exemplo: `{"clientId": "ABC123", "creditLimit": 5000.00, "available": 3200.00}` |

### `workflows` — `create-order-v1`

| Campo | Valor |
|---|---|
| `flowId` | `"create-order-v1"` |
| `version` | `"1.0.0"` |
| `description` | `"Order creation flow"` |
| `active` | `true` |
| `yamlContent` | YAML completo do `docs/example-flow.yml` (ver abaixo) |
| `contract` | `{id: "create-order", version: 1}` |
| `integrationRefs` | `[{id: "validate-client", version: 1}, {id: "save-order", version: 1}]` |
| `validationRefs` | `[{id: "check-credit-limit", version: 1}]` |

---

## Implementação

### 1. Atualizar `init-mongo.js`

Adicionar os inserts logo após os `createIndex()` de cada collection. O arquivo completo ficará assim:

```javascript
db = db.getSiblingDB('service-portal-manager');

// --- Collections e índices ---

db.createCollection('workflows');
db.createCollection('integrations');
db.createCollection('contracts');
db.createCollection('validations');

db.workflows.createIndex({ "flowId": 1, "version": 1 }, { unique: true, sparse: true });
db.integrations.createIndex({ "integrationId": 1, "version": 1 }, { unique: true, sparse: true });
db.contracts.createIndex({ "contractId": 1, "version": 1 }, { unique: true, sparse: true });
db.validations.createIndex({ "validationId": 1, "version": 1 }, { unique: true, sparse: true });

// --- Dados de exemplo ---

var now = new Date();

// Contract: create-order
db.contracts.insertOne({
    contractId: "create-order",
    version: 1,
    active: true,
    fields: [
        {
            name: "clientId",
            type: "STRING",
            required: true,
            validations: [
                { type: "NOT_BLANK" },
                { type: "PATTERN", value: "^[A-Z0-9]{6,20}$", message: "Invalid clientId" }
            ]
        },
        {
            name: "amount",
            type: "DECIMAL",
            required: true,
            validations: [
                { type: "POSITIVE" }
            ]
        }
    ],
    createdAt: now,
    updatedAt: now,
    _class: "com.serviceportal.manager.domain.ContractDocument"
});

// Integration: validate-client
db.integrations.insertOne({
    integrationId: "validate-client",
    version: 1,
    active: true,
    type: "HTTP",
    url: "http://api.exemplo.com/clients/{{contract.clientId}}",
    method: "GET",
    headers: { "Content-Type": "application/json" },
    timeout: 5000,
    bodyTemplate: null,
    responseBody: {
        clientId: "{{request.pathSegments.[1]}}",
        name: "WireMock Simulated Client",
        document: "12345678910",
        documentType: "CPF",
        active: true,
        createdAt: "2026-01-01T10:00:00Z"
    },
    createdAt: now,
    updatedAt: now,
    _class: "com.serviceportal.manager.domain.IntegrationDocument"
});

// Integration: save-order
db.integrations.insertOne({
    integrationId: "save-order",
    version: 1,
    active: true,
    type: "HTTP",
    url: "http://api.exemplo.com/orders",
    method: "POST",
    headers: { "Content-Type": "application/json" },
    timeout: 5000,
    bodyTemplate: '{"clientId":"{{contract.clientId}}","amount":"{{contract.amount}}","status":"CREATED"}',
    responseBody: {
        id: "ORD-001",
        clientId: "ABC123",
        amount: 150.00,
        status: "CREATED"
    },
    createdAt: now,
    updatedAt: now,
    _class: "com.serviceportal.manager.domain.IntegrationDocument"
});

// Validation: check-credit-limit
db.validations.insertOne({
    validationId: "check-credit-limit",
    version: 1,
    active: true,
    type: "HTTP",
    url: "http://api.exemplo.com/clients/{{contract.clientId}}/credit",
    method: "GET",
    headers: { "Content-Type": "application/json" },
    timeout: 5000,
    bodyTemplate: null,
    responseBody: {
        clientId: "{{request.pathSegments.[1]}}",
        creditLimit: 5000.00,
        available: 3200.00,
        currency: "BRL"
    },
    createdAt: now,
    updatedAt: now,
    _class: "com.serviceportal.manager.domain.ValidationDocument"
});

// Workflow: create-order-v1
var yamlContent = [
    'flow:',
    '  id: "create-order-v1"',
    '  description: "Order creation flow"',
    '  version: "1.0.0"',
    '  active: true',
    '',
    '  contract:',
    '    fields:',
    '      - name: "clientId"',
    '        type: STRING',
    '        required: true',
    '        validations:',
    '          - type: NOT_BLANK',
    '          - type: PATTERN',
    '            value: "^[A-Z0-9]{6,20}$"',
    '            message: "Invalid clientId"',
    '      - name: "amount"',
    '        type: DECIMAL',
    '        required: true',
    '        validations:',
    '          - type: POSITIVE',
    '',
    '  integrations:',
    '    - id: "validate-client"',
    '      order: 1',
    '      type: HTTP',
    '      continueOnError: false',
    '      http:',
    '        url: "http://api.exemplo.com/clients/{{contract.clientId}}"',
    '        method: GET',
    '        headers:',
    '          Content-Type: "application/json"',
    '        timeout: 5000',
    '',
    '    - id: "save-order"',
    '      order: 2',
    '      type: HTTP',
    '      continueOnError: false',
    '      http:',
    '        url: "http://api.exemplo.com/orders"',
    '        method: POST',
    '        headers:',
    '          Content-Type: "application/json"',
    '        bodyTemplate: |',
    '          {"clientId":"{{contract.clientId}}","amount":"{{contract.amount}}","status":"CREATED"}',
    '        timeout: 5000',
    '        responseMapping:',
    '          targetField: "orderId"',
    '          sourceField: "id"',
    '',
    '    - id: "notify-rabbit"',
    '      order: 3',
    '      type: QUEUE',
    '      provider: RABBITMQ',
    '      continueOnError: true',
    '      queue:',
    '        exchange: "orders.exchange"',
    '        routingKey: "order.created"',
    '        messageTemplate: |',
    '          {"event":"ORDER_CREATED","orderId":"{{integrations.save-order.orderId}}"}',
    '        persistent: true',
    '',
    '  validations:',
    '    - id: "check-credit-limit"',
    '      order: 1',
    '      type: HTTP',
    '      continueOnError: false',
    '      http:',
    '        url: "http://api.exemplo.com/clients/{{contract.clientId}}/credit"',
    '        method: GET',
    '        headers:',
    '          Content-Type: "application/json"',
    '        timeout: 5000'
].join('\n');

db.workflows.insertOne({
    flowId: "create-order-v1",
    version: "1.0.0",
    description: "Order creation flow",
    active: true,
    yamlContent: yamlContent,
    contract: { id: "create-order", version: 1 },
    integrationRefs: [
        { id: "validate-client", version: 1 },
        { id: "save-order", version: 1 }
    ],
    validationRefs: [
        { id: "check-credit-limit", version: 1 }
    ],
    createdAt: now,
    updatedAt: now,
    _class: "com.serviceportal.manager.domain.FlowDocument"
});

print('[init-mongo] Database service-portal-manager initialized with collections, indexes, and example data.');
```

### 2. Adicionar WireMock mapping para `/clients/{id}/credit`

O endpoint `check-credit-limit` chama `http://api.exemplo.com/clients/{clientId}/credit`, que não tem mapping no WireMock ainda.

Criar `wiremock/mappings/clients-credit-get.json`:

```json
{
    "request": {
        "method": "GET",
        "urlPathPattern": "/clients/([A-Z0-9]{6,20})/credit"
    },
    "response": {
        "status": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "jsonBody": {
            "clientId": "{{request.pathSegments.[1]}}",
            "creditLimit": 5000.00,
            "available": 3200.00,
            "currency": "BRL"
        },
        "transformers": ["response-template"]
    }
}
```

---

## Arquivos críticos

| Arquivo | Mudança |
|---|---|
| `service-portal-manager/mongodb-manager/init-mongo.js` | Adicionar inserts para contracts, integrations, validations e workflows |
| `wiremock/mappings/clients-credit-get.json` | **Novo** — simula endpoint de crédito usado pela validation |

---

## Considerações

- **`_class`**: O campo `_class` é necessário para que o Spring Data MongoDB desserialize corretamente os documentos para as classes Kotlin. Deve corresponder ao fully-qualified class name.
- **Idempotência**: O script é executado apenas quando o volume MongoDB está vazio (`docker-entrypoint-initdb.d/` só roda no primeiro boot). Não há risco de duplicatas.
- **YAML simplificado no workflow**: O `yamlContent` do exemplo inclui apenas as integrações HTTP e uma QUEUE (Rabbit), omitindo Kafka e SQS para manter o YAML enxuto no exemplo. O arquivo `docs/example-flow.yml` continua como referência completa para testes.

---

## Verificação

1. **Destruir volumes e recriar** (necessário para o script rodar novamente):
   ```bash
   docker compose -f docker-compose-service-portal.yml down -v
   docker compose -f docker-compose-service-portal.yml up -d
   ```

2. **Verificar dados inseridos**:
   ```bash
   docker exec portal-mongodb mongosh service-portal-manager --eval \
     "printjson({
       workflows: db.workflows.countDocuments(),
       integrations: db.integrations.countDocuments(),
       contracts: db.contracts.countDocuments(),
       validations: db.validations.countDocuments()
     })"
   # Esperado: { workflows: 1, integrations: 2, contracts: 1, validations: 1 }
   ```

3. **Verificar via API do Manager** (com token):
   ```bash
   TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

   curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8082/manager/flows | \
     grep -o '"flowId":"[^"]*"'
   # Esperado: "flowId":"create-order-v1"
   ```

4. **Verificar WireMock** para o novo mapping:
   ```bash
   curl -s "http://localhost:18080/clients/ABC123/credit"
   # Esperado: {"clientId":"ABC123","creditLimit":5000.0,"available":3200.0,"currency":"BRL"}
   ```

5. **Executar workflow de exemplo** para validar integração ponta a ponta:
   ```bash
   ORCH_TOKEN=$(curl -s -X POST http://localhost:8080/api/auth/tokens \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

   curl -s -X POST \
     "http://localhost:8080/api/flows/create-order-v1/versions/1.0.0/executions" \
     -H "Authorization: Bearer $ORCH_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"clientId":"ABC123","amount":150.00}'
   # Esperado: resposta JSON com campos result e validations
   ```
