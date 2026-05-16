# Plano de Teste Integrado — Service Portal

Foco: jornada do usuário no portal — cadastro, gestão e execução de workflows com cada tipo de integração disponível.

**Pré-requisito:** todos os serviços no ar via `docker compose -f docker-compose-service-portal.yml up -d`.

```
Frontend (:80) → BFF (:8081) → [Manager (:8082) para CRUD + Orquestrador (:8080) para execução]
                    ↓
         MongoDB + Redis + RabbitMQ + Kafka + LocalStack (SQS)
```

> **Formato:** Todos os YAMLs, endpoints e payloads estão em **INGLÊS** (refactor recente).
> **Auth:** BFF autentica internamente no orquestrador (server-to-server) com JWT HS512.
> **CRUD:** Migrado para o service-portal-manager; orquestrador apenas executa (cache Redis 1h).
> **Endpoints:** Padrão REST com sub-recursos — `/flows/{flowId}/versions/{version}/executions`

---

## Índice

1. [Saúde do sistema](#1-saúde-do-sistema)
2. [Server Driven UI — menu e navegação](#2-server-driven-ui--menu-e-navegação)
3. [CRUD de workflows (Manager)](#3-crud-de-workflows-manager)
4. [Execução — workflow HTTP](#4-execução--workflow-http)
5. [Execução — workflow QUEUE RabbitMQ](#5-execução--workflow-queue-rabbitmq)
6. [Execução — workflow QUEUE Kafka](#6-execução--workflow-queue-kafka)
7. [Execução — workflow QUEUE SQS](#7-execução--workflow-queue-sqs)
8. [Execução — workflow completo (todos os tipos)](#8-execução--workflow-completo-todos-os-tipos)
9. [Cenários negativos e validações de contrato](#9-cenários-negativos-e-validações-de-contrato)

---

## Workflows de referência

Os YAMLs abaixo são usados nos testes. Cadastre-os via `POST /bff/flows` antes de executar cada seção (todos em **inglês**).

### WF-HTTP — validação via chamada HTTP

```yaml
flow:
  flowId: "test-http"
  version: "1.0.0"
  description: "Test workflow — HTTP integration"
  active: true

  contract:
    fields:
      - name: "clientId"
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
          - type: PATTERN
            value: "^[A-Z0-9]{6,20}$"
            message: "Invalid clientId"

  integrations:
    - id: "fetch-client"
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
```

### WF-RABBITMQ — publicação em fila RabbitMQ

```yaml
flow:
  flowId: "test-rabbitmq"
  version: "1.0.0"
  description: "Test workflow — RabbitMQ integration"
  active: true

  contract:
    fields:
      - name: "orderId"
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK

  integrations:
    - id: "notify-rabbitmq"
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
```

### WF-KAFKA — publicação em tópico Kafka

```yaml
flow:
  flowId: "test-kafka"
  version: "1.0.0"
  description: "Test workflow — Kafka integration"
  active: true

  contract:
    fields:
      - name: "orderId"
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK

  integrations:
    - id: "track-kafka"
      order: 1
      type: QUEUE
      provider: KAFKA
      continueOnError: false
      queue:
        topic: "orders.created"
        messageTemplate: |
          {"event":"ORDER_CREATED","orderId":"{{contract.orderId}}"}
```

### WF-SQS — publicação em fila SQS (LocalStack)

```yaml
flow:
  flowId: "test-sqs"
  version: "1.0.0"
  description: "Test workflow — SQS integration"
  active: true

  contract:
    fields:
      - name: "orderId"
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK

  integrations:
    - id: "notify-sqs"
      order: 1
      type: QUEUE
      provider: SQS
      continueOnError: false
      queue:
        queueUrl: "http://localhost:4566/000000000000/orders-test"
        messageTemplate: |
          {"event":"ORDER_CREATED","orderId":"{{contract.orderId}}"}
```

### WF-COMPLETO — todos os tipos em sequência (baseado no example-flow.yml)

```yaml
flow:
  flowId: "create-order-v1"
  version: "1.0.0"
  description: "Complete workflow — HTTP + RabbitMQ + Kafka + SQS"
  active: true

  contract:
    fields:
      - name: "clientId"
        type: STRING
        required: true
        validations:
          - type: NOT_BLANK
          - type: PATTERN
            value: "^[A-Z0-9]{6,20}$"
            message: "Invalid clientId"
      - name: "amount"
        type: DECIMAL
        required: true
        validations:
          - type: POSITIVE

  integrations:
    - id: "validate-client"
      order: 1
      type: HTTP
      continueOnError: false
      http:
        url: "http://api.exemplo.com/clients/{{contract.clientId}}"
        method: GET
        headers:
          Accept: "application/json"
        timeout: 5000
        responseMapping:
          sourceField: "name"
          targetField: "clientName"

    - id: "notify-rabbitmq"
      order: 2
      type: QUEUE
      provider: RABBITMQ
      continueOnError: true
      queue:
        exchange: "orders.exchange"
        routingKey: "order.created"
        persistent: true
        messageTemplate: |
          {"event":"ORDER_CREATED","clientId":"{{contract.clientId}}","amount":"{{contract.amount}}"}

    - id: "track-kafka"
      order: 3
      type: QUEUE
      provider: KAFKA
      continueOnError: true
      queue:
        topic: "orders.created"
        messageTemplate: |
          {"event":"ORDER_CREATED","clientId":"{{contract.clientId}}","amount":"{{contract.amount}}"}

    - id: "notify-sqs"
      order: 4
      type: QUEUE
      provider: SQS
      continueOnError: true
      queue:
        queueUrl: "http://localhost:4566/000000000000/orders-test"
        messageTemplate: |
          {"event":"ORDER_CREATED","clientId":"{{contract.clientId}}","amount":"{{contract.amount}}"}
```

---

## 1. Saúde do sistema

Objetivo: confirmar que todos os serviços estão no ar antes de qualquer teste.

| # | Teste | Como executar | Resultado esperado |
|---|-------|---------------|-------------------|
| 1.1 | Health do BFF | `GET http://localhost:8081/bff/health` | `200 OK` |
| 1.2 | Health do Orquestrador | `GET http://localhost:8080/actuator/health` | `200 OK`, status `UP` |
| 1.3 | Health do Manager | `GET http://localhost:8082/actuator/health` | `200 OK`, status `UP` |
| 1.4 | MongoDB acessível | `docker exec -it <mongo> mongosh --eval "db.adminCommand('ping')"` | `{ ok: 1 }` |
| 1.5 | Redis acessível | `docker exec -it <redis> redis-cli ping` | `PONG` |
| 1.6 | RabbitMQ Management UI | Abrir `http://localhost:15672` (guest/guest) | Painel carrega |
| 1.7 | Kafka acessível | `docker exec -it <kafka> kafka-topics --bootstrap-server localhost:9092 --list` | Sem erro |
| 1.8 | LocalStack SQS | `aws --endpoint-url=http://localhost:4566 sqs list-queues` | Sem erro |
| 1.9 | Frontend carrega | Abrir `http://localhost` no browser | Página inicial renderiza |

---

## 2. Server Driven UI — menu e navegação

Objetivo: validar que o BFF entrega o menu correto e que o frontend renderiza dinamicamente.

| # | Teste | Como executar | Resultado esperado |
|---|-------|---------------|-------------------|
| 2.1 | BFF retorna menu | `GET http://localhost:8081/bff/menu` | JSON com item `flow-manager` contendo `id`, `label`, `icon`, `uiSchemaUrl` |
| 2.2 | BFF retorna schema da feature | `GET http://localhost:8081/bff/features/flow-manager/ui-schema` | JSON com `featureId: "flow-manager"`, `type: "flow-manager"`, `title` |
| 2.3 | Sidebar renderiza o item | Abrir o frontend (http://localhost), observar sidebar | Item "Flow Manager" visível |
| 2.4 | Clicar no item carrega a feature | Clicar em "Flow Manager" | Área principal exibe a tabela de fluxos |
| 2.5 | Feature type desconhecido | Forçar `GET /bff/features/inexistente/ui-schema` | BFF retorna erro ou schema com type não mapeado; frontend exibe "componente não encontrado" |

---

## 3. CRUD de workflows (Manager)

Objetivo: validar o ciclo completo de criação, leitura, atualização e desativação de um workflow via BFF (que delega ao Manager).

Usar o YAML **WF-HTTP** como payload nos testes abaixo (em **inglês**).

### 3.1 Criar workflow

```bash
curl -X POST http://localhost:8081/bff/flows \
  -H "Content-Type: text/plain" \
  --data-binary @wf-http.yml
```

**Resultado esperado:** `201 Created` com o workflow persistido no MongoDB via Manager.

**Verificar no MongoDB:**
```js
db.workflows.findOne({ flowId: "test-http" })
// deve retornar o documento com active: true e yamlContent preenchido
```

### 3.2 Listar workflows (paginado)

```bash
curl "http://localhost:8081/bff/flows?page=0&size=20"
```

**Resultado esperado:** JSON com `content` (array de workflows), `totalElements`, `totalPages`.

**No frontend:** abrir o FlowManager e confirmar que o workflow aparece na tabela.

### 3.3 Buscar workflow por ID e versão

```bash
curl http://localhost:8081/bff/flows/test-http/versions/1.0.0
```

**Resultado esperado:** `200 OK` com os dados completos do workflow (sem `yamlContent`).

### 3.4 Obter YAML cru do workflow

```bash
curl http://localhost:8081/bff/flows/test-http/versions/1.0.0/yaml
```

**Resultado esperado:** `200 OK` com `Content-Type: application/x-yaml` — YAML cru do workflow.

### 3.5 Atualizar workflow

Alterar o campo `description` no YAML e enviar:

```bash
curl -X PUT http://localhost:8081/bff/flows/test-http/versions/1.0.0 \
  -H "Content-Type: text/plain" \
  --data-binary @wf-http-updated.yml
```

**Resultado esperado:** `200 OK`. Buscar novamente (3.3 ou 3.4) e confirmar que `description` foi atualizada.

### 3.6 Desativar workflow

```bash
curl -X DELETE http://localhost:8081/bff/flows/test-http/versions/1.0.0
```

**Resultado esperado:** `200 OK`. Workflow não deve mais aparecer na listagem (soft-delete: `active: false` no MongoDB). **No frontend:** confirmar que sumiu da tabela.

### 3.7 Recriar para os próximos testes

Após 3.6, recriar o workflow para os testes de execução (repetir 3.1).

---

## 4. Execução — workflow HTTP

**Pré-requisito:** WF-HTTP cadastrado e ativo em `test-http`, versão `1.0.0`.

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/flows/test-http/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLI001A"}'
```

**Resultado esperado:**
```json
{
  "executionId": "<uuid>",
  "flowId": "test-http",
  "status": "SUCCESS",
  "result": {
    "fetch-client": {
      "clientName": "Client Name from API"
    }
  },
  "startedAt": "<timestamp>",
  "completedAt": "<timestamp>"
}
```

**Pontos a validar:**
- `status` é `SUCCESS`
- `result.fetch-client.clientName` preenchido com dado real da API externa
- `responseMapping` funcionou: campo `name` do response mapeado para `clientName`
- Timestamps presentes e coerentes

### Cenário — serviço HTTP retorna erro com `continueOnError: false`

Alterar temporariamente a URL para uma inválida (ex: `/clients/INVALID`) e re-executar.

**Resultado esperado:** `status: FAILURE` ou `ERROR`, execução interrompida no passo `fetch-client`.

---

## 5. Execução — workflow QUEUE RabbitMQ

**Pré-requisito:** WF-RABBITMQ cadastrado, exchange `orders.exchange` criada no RabbitMQ.

**Criar a exchange/fila antes do teste:**
```bash
# via Management UI (http://localhost:15672) ou rabbitmqadmin
# criar exchange: orders.exchange (type: direct)
# criar fila: orders-created
# fazer binding: orders.exchange → orders-created (routingKey: order.created)
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/flows/test-rabbitmq/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"orderId":"ORD-001"}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "result": {
    "notify-rabbitmq": {
      "provider": "RABBITMQ",
      "integrationId": "notify-rabbitmq",
      "published": true
    }
  }
}
```

**Verificar no RabbitMQ:**
- Acessar `http://localhost:15672` → Queues → `orders-created`
- Confirmar mensagem na fila com conteúdo `{"event":"ORDER_CREATED","orderId":"ORD-001",...}`

---

## 6. Execução — workflow QUEUE Kafka

**Pré-requisito:** WF-KAFKA cadastrado, tópico `orders.created` existente.

**Criar o tópico:**
```bash
docker exec -it <kafka-container> \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic orders.created --partitions 1 --replication-factor 1
```

**Abrir consumer para monitorar:**
```bash
docker exec -it <kafka-container> \
  kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic orders.created --from-beginning
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/flows/test-kafka/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"orderId":"ORD-001"}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "result": {
    "track-kafka": {
      "provider": "KAFKA",
      "integrationId": "track-kafka",
      "topic": "orders.created",
      "partition": 0,
      "offset": "<numero>",
      "published": true
    }
  }
}
```

**Verificar no consumer:** mensagem `{"event":"ORDER_CREATED","orderId":"ORD-001"}` deve aparecer.

---

## 7. Execução — workflow QUEUE SQS

**Pré-requisito:** WF-SQS cadastrado, fila criada no LocalStack.

**Criar a fila no LocalStack:**
```bash
aws --endpoint-url=http://localhost:4566 \
  sqs create-queue --queue-name orders-test
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/flows/test-sqs/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"orderId":"ORD-001"}'
```

**Resultado esperado:** `status: SUCCESS`, `published: true`.

**Verificar na fila:**
```bash
aws --endpoint-url=http://localhost:4566 \
  sqs receive-message \
  --queue-url http://localhost:4566/000000000000/orders-test
```
Deve retornar a mensagem com o corpo correto.

---

## 8. Execução — workflow completo (todos os tipos)

**Pré-requisito:** WF-COMPLETO (`create-order-v1`) cadastrado + infraestrutura dos testes 4 a 7 pronta.

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLI001A","amount":499.90}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "result": {
    "validate-client": {
      "clientName": "..."
    },
    "notify-rabbitmq": { "published": true },
    "track-kafka": { "published": true, "topic": "orders.created" },
    "notify-sqs": { "published": true }
  }
}
```

**Pontos a validar em sequência:**
1. Passo HTTP (`validate-client`) executado primeiro — response mapeado no contexto
2. Passo RabbitMQ (`notify-rabbitmq`) usou `{{contract.clientId}}` e `{{contract.amount}}` corretamente
3. Passo Kafka (`track-kafka`) publicou no tópico correto
4. Passo SQS (`notify-sqs`) publicou na fila LocalStack
5. `continueOnError: true` nos passos de queue — falha em um não interrompe os seguintes

**Cenário — falha isolada em queue com `continueOnError: true`**

Derrubar o RabbitMQ temporariamente e re-executar. O esperado é:
- Passo `notify-rabbitmq` falha
- Passos `track-kafka` e `notify-sqs` continuam e são executados
- `status` geral indica execução parcial (verificar comportamento atual do orquestrador)

---

## 9. Cenários negativos e validações de contrato

### 9.1 Payload inválido — campo obrigatório ausente

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"amount":100.00}'
```

**Esperado:** `400 Bad Request` com mensagem indicando que `clientId` é obrigatório.

### 9.2 Payload inválido — PATTERN não respeitado

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"id inválido!","amount":100.00}'
```

**Esperado:** `400 Bad Request` com mensagem `"Invalid clientId"` (definida no PATTERN do contrato).

### 9.3 Payload inválido — tipo errado

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLI001A","amount":"not-a-number"}'
```

**Esperado:** `400 Bad Request` indicando tipo inválido para `amount`.

### 9.4 Payload inválido — valor não positivo (POSITIVE)

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLI001A","amount":-50.00}'
```

**Esperado:** `400 Bad Request`.

### 9.5 Workflow inexistente

```bash
curl -X POST http://localhost:8081/bff/flows/inexistent/versions/1.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Esperado:** `404 Not Found`.

### 9.6 Versão inexistente

```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/versions/99.0.0/executions \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLI001A","amount":100.00}'
```

**Esperado:** `404 Not Found` — não existe workflow com `flowId: create-order-v1` e `version: 99.0.0`.

### 9.7 YAML inválido no cadastro

```bash
curl -X POST http://localhost:8081/bff/flows \
  -H "Content-Type: text/plain" \
  -d 'invalid: yaml: syntax: :::'
```

**Esperado:** `400 Bad Request` com mensagem de parse error.

### 9.8 Cadastrar workflow com ID e versão duplicados

Enviar o mesmo YAML duas vezes via `POST /bff/flows`.

**Esperado:** segundo `POST` retorna erro de conflito (verificar comportamento — pode ser `409 Conflict` ou atualização silenciosa).

---

## Checklist de execução

```
[ ] 1. Saúde do sistema — todos os serviços no ar (BFF, Orquestrador, Manager, MongoDB, Redis, RabbitMQ, Kafka, LocalStack)
[ ] 2. Server Driven UI — menu e navegação OK (endpoints /bff/menu e /bff/features/{id}/ui-schema)
[ ] 3. CRUD completo (Manager via BFF) — criar, listar, buscar, obter YAML, atualizar, desativar
[ ] 4. Execução HTTP — cenário feliz + erro com continueOnError: false
[ ] 5. Execução RabbitMQ — mensagem na fila confirmada
[ ] 6. Execução Kafka — mensagem no tópico confirmada
[ ] 7. Execução SQS — mensagem na fila LocalStack confirmada
[ ] 8. Execução completa — todos os passos em sequência + referência entre passos (e.g., {{contract.x}})
[ ] 9. Cenários negativos — validações de contrato, erros de roteamento, payloads inválidos
[ ] 10. Persistência — workflows salvos no MongoDB via Manager, cache Redis no Orquestrador
```

---

## Tarefas de teste

### Script de validação automática

Um script `teste-integrado-service-portal.sh` foi criado para automatizar parte dos testes:
- Sobe o docker-compose
- Valida saúde do sistema
- Cria workflows de teste
- Executa cenários básicos
- Gera relatório em Markdown

**Como usar:**
```bash
./teste-integrado-service-portal.sh
```

Gera logs em `teste-integrado-<timestamp>.log` e checklist em `teste-integrado-checklist-<timestamp>.md`.

### Cenários a testar manualmente (WireMock)

Os testes acima usam `api.exemplo.com` (alias WireMock). Verifique que:
1. `GET /clients/{clientId}` retorna `{ "name": "Client Name", ... }` (mapping em `wiremock/mappings/`)
2. Responses são templates via WireMock, simulando APIs externas reais
3. Retry + Circuit Breaker funcionam (teste com WireMock derrubado)

### Cenários para implementar (future)

Se quiser adicionar testes integrados para:
- **Validação de contrato avançada** (ex: custom validators)
- **Cache Redis** (verificar warm-up e TTL)
- **Auth de usuário final** (Authentik + PKCE)

Preencha um formulário como abaixo:

**Cenário a testar:**
(descrição)

**Componente alvo:**
(ex: generic-orchestrator, service-portal-bff, service-portal-manager, service-portal-frontend)

**Arquivo(s) relevante(s):**
(caminhos)

**Validação esperada:**
(ex: status HTTP, conteúdo de resposta, estado do MongoDB)