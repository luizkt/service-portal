# Plano de Teste Integrado — Service Portal

Foco: jornada do usuário no portal — cadastro, gestão e execução de workflows com cada tipo de integração disponível.

**Pré-requisito:** todos os serviços no ar via `docker compose up -d` + BFF e frontend rodando.

```
Frontend (:5173) → BFF (:8081) → Orquestrador (:8080) → MongoDB + Brokers
```

> Auth de usuário final (Authentik) ainda não está integrado ao frontend.
> Os testes abaixo assumem que o BFF aceita requisições sem token de usuário
> e autentica internamente no orquestrador (server-to-server).

---

## Índice

1. [Saúde do sistema](#1-saúde-do-sistema)
2. [Server Driven UI — menu e navegação](#2-server-driven-ui--menu-e-navegação)
3. [CRUD de workflows](#3-crud-de-workflows)
4. [Execução — workflow HTTP](#4-execução--workflow-http)
5. [Execução — workflow DATABASE](#5-execução--workflow-database)
6. [Execução — workflow QUEUE RabbitMQ](#6-execução--workflow-queue-rabbitmq)
7. [Execução — workflow QUEUE Kafka](#7-execução--workflow-queue-kafka)
8. [Execução — workflow QUEUE SQS](#8-execução--workflow-queue-sqs)
9. [Execução — workflow completo (todos os tipos)](#9-execução--workflow-completo-todos-os-tipos)
10. [Cenários negativos e validações de contrato](#10-cenários-negativos-e-validações-de-contrato)

---

## Workflows de referência

Os YAMLs abaixo são usados nos testes. Cadastre-os via `POST /bff/flows` antes de executar cada seção.

### WF-HTTP — validação via chamada HTTP

```yaml
fluxo:
  id: "teste-http"
  descricao: "Workflow de teste — integração HTTP"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "clienteId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK
          - tipo: PATTERN
            valor: "^[A-Z0-9]{6,20}$"
            mensagem: "clienteId inválido"

  integracoes:
    - id: "buscar-cliente"
      ordem: 1
      tipo: HTTP
      continuarEmErro: false
      http:
        url: "https://jsonplaceholder.typicode.com/users/1"
        metodo: GET
        headers:
          Accept: "application/json"
        timeout: 5000
        mapeamentoResposta:
          campoOrigem: "name"
          campoDestino: "nomeCliente"
```

### WF-DATABASE — persistência no MongoDB

```yaml
fluxo:
  id: "teste-database"
  descricao: "Workflow de teste — integração DATABASE"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "clienteId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK
      - nome: "valor"
        tipo: DECIMAL
        obrigatorio: true
        validacoes:
          - tipo: POSITIVE

  integracoes:
    - id: "salvar-pedido"
      ordem: 1
      tipo: DATABASE
      continuarEmErro: false
      database:
        operacao: INSERT
        colecao: "pedidos-teste"
        documentoTemplate: |
          {"clienteId":"{{contrato.clienteId}}","valor":"{{contrato.valor}}","status":"CRIADO","ts":"{{now()}}"}
        mapeamentoResposta:
          campoOrigem: "_id"
          campoDestino: "pedidoId"
```

### WF-RABBITMQ — publicação em fila RabbitMQ

```yaml
fluxo:
  id: "teste-rabbitmq"
  descricao: "Workflow de teste — integração QUEUE RabbitMQ"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "pedidoId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK

  integracoes:
    - id: "rabbitmq-notifier"
      ordem: 1
      tipo: QUEUE
      provider: RABBITMQ
      continuarEmErro: false
      queue:
        exchange: "pedidos.exchange"
        routingKey: "pedido.criado"
        persistente: true
        mensagemTemplate: |
          {"evento":"PEDIDO_CRIADO","pedidoId":"{{contrato.pedidoId}}","ts":"{{now()}}"}
```

### WF-KAFKA — publicação em tópico Kafka

```yaml
fluxo:
  id: "teste-kafka"
  descricao: "Workflow de teste — integração QUEUE Kafka"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "pedidoId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK

  integracoes:
    - id: "kafka-user-tracking"
      ordem: 1
      tipo: QUEUE
      provider: KAFKA
      continuarEmErro: false
      queue:
        topic: "pedidos.criados"
        mensagemTemplate: |
          {"evento":"PEDIDO_CRIADO","pedidoId":"{{contrato.pedidoId}}"}
```

### WF-SQS — publicação em fila SQS (LocalStack)

```yaml
fluxo:
  id: "teste-sqs"
  descricao: "Workflow de teste — integração QUEUE SQS"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "pedidoId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK

  integracoes:
    - id: "notificar-sqs"
      ordem: 1
      tipo: QUEUE
      provider: SQS
      continuarEmErro: false
      queue:
        queueUrl: "http://localhost:4566/000000000000/pedidos-teste"
        mensagemTemplate: |
          {"evento":"PEDIDO_CRIADO","pedidoId":"{{contrato.pedidoId}}"}
```

### WF-COMPLETO — todos os tipos em sequência (baseado no example-flow.yml)

```yaml
fluxo:
  id: "criar-pedido-v1"
  descricao: "Fluxo completo — HTTP + DATABASE + RabbitMQ + Kafka + SQS"
  versao: "1.0.0"
  ativo: true

  contrato:
    campos:
      - nome: "clienteId"
        tipo: STRING
        obrigatorio: true
        validacoes:
          - tipo: NOT_BLANK
          - tipo: PATTERN
            valor: "^[A-Z0-9]{6,20}$"
            mensagem: "clienteId inválido"
      - nome: "valor"
        tipo: DECIMAL
        obrigatorio: true
        validacoes:
          - tipo: POSITIVE

  integracoes:
    - id: "validar-cliente"
      ordem: 1
      tipo: HTTP
      continuarEmErro: false
      http:
        url: "https://jsonplaceholder.typicode.com/users/1"
        metodo: GET
        headers:
          Accept: "application/json"
        timeout: 5000

    - id: "salvar-pedido"
      ordem: 2
      tipo: DATABASE
      continuarEmErro: false
      database:
        operacao: INSERT
        colecao: "pedidos"
        documentoTemplate: |
          {"clienteId":"{{contrato.clienteId}}","valor":"{{contrato.valor}}","status":"CRIADO"}
        mapeamentoResposta:
          campoDestino: "pedidoId"
          campoOrigem: "_id"

    - id: "rabbitmq-notifier"
      ordem: 3
      tipo: QUEUE
      provider: RABBITMQ
      continuarEmErro: true
      queue:
        exchange: "pedidos.exchange"
        routingKey: "pedido.criado"
        mensagemTemplate: |
          {"evento":"PEDIDO_CRIADO","pedidoId":"{{integracoes.salvar-pedido.pedidoId}}"}
        persistente: true

    - id: "kafka-user-tracking"
      ordem: 4
      tipo: QUEUE
      provider: KAFKA
      continuarEmErro: true
      queue:
        topic: "pedidos.criados"
        mensagemTemplate: |
          {"pedidoId":"{{integracoes.salvar-pedido.pedidoId}}"}

    - id: "notificar-sqs"
      ordem: 5
      tipo: QUEUE
      provider: SQS
      continuarEmErro: true
      queue:
        queueUrl: "http://localhost:4566/000000000000/pedidos-teste"
        mensagemTemplate: |
          {"pedidoId":"{{integracoes.salvar-pedido.pedidoId}}"}
```

---

## 1. Saúde do sistema

Objetivo: confirmar que todos os serviços estão no ar antes de qualquer teste.

| # | Teste | Como executar | Resultado esperado |
|---|-------|---------------|-------------------|
| 1.1 | Health do BFF | `GET http://localhost:8081/bff/health` | `200 OK` |
| 1.2 | Health do orquestrador | `GET http://localhost:8080/actuator/health` | `200 OK`, status `UP` |
| 1.3 | MongoDB acessível | `docker exec -it <mongo> mongosh --eval "db.adminCommand('ping')"` | `{ ok: 1 }` |
| 1.4 | RabbitMQ Management UI | Abrir `http://localhost:15672` (guest/guest) | Painel carrega |
| 1.5 | Kafka acessível | `docker exec -it <kafka> kafka-topics --bootstrap-server localhost:9092 --list` | Sem erro |
| 1.6 | LocalStack SQS | `aws --endpoint-url=http://localhost:4566 sqs list-queues` | Sem erro |
| 1.7 | Frontend carrega | Abrir `http://localhost:5173` no browser | Página inicial renderiza |

---

## 2. Server Driven UI — menu e navegação

Objetivo: validar que o BFF entrega o menu correto e que o frontend renderiza dinamicamente.

| # | Teste | Como executar | Resultado esperado |
|---|-------|---------------|-------------------|
| 2.1 | BFF retorna menu | `GET http://localhost:8081/bff/menu` | JSON com item `flow-manager` contendo `id`, `label`, `icon`, `uiSchemaUrl` |
| 2.2 | BFF retorna schema da feature | `GET http://localhost:8081/bff/ui/flow-manager` | JSON com `featureId: "flow-manager"`, `type: "flow-manager"`, `title` |
| 2.3 | Sidebar renderiza o item | Abrir o frontend, observar sidebar | Item "Gerenciador de Fluxos" visível |
| 2.4 | Clicar no item carrega a feature | Clicar em "Gerenciador de Fluxos" | Área principal exibe o FlowManager (tabela de fluxos ou tela vazia) |
| 2.5 | Feature type desconhecido | Forçar `GET /bff/ui/inexistente` | BFF retorna erro ou schema com type não mapeado; frontend exibe "componente não encontrado" |

---

## 3. CRUD de workflows

Objetivo: validar o ciclo completo de criação, leitura, atualização e desativação de um workflow via BFF.

Usar o YAML **WF-HTTP** como payload nos testes abaixo.

### 3.1 Criar workflow

```bash
curl -X POST http://localhost:8081/bff/flows \
  -H "Content-Type: text/plain" \
  --data-binary @wf-http.yml
```

**Resultado esperado:** `201 Created` com o workflow persistido no MongoDB.

**Verificar no MongoDB:**
```js
db.workflows.findOne({ id: "teste-http" })
// deve retornar o documento com ativo: true
```

### 3.2 Listar workflows

```bash
curl http://localhost:8081/bff/flows
```

**Resultado esperado:** array JSON contendo o workflow `teste-http` com campos `id`, `descricao`, `versao`, `ativo`.

**No frontend:** abrir o FlowManager e confirmar que o workflow aparece na tabela.

### 3.3 Buscar workflow por ID

```bash
curl http://localhost:8081/bff/flows/teste-http
```

**Resultado esperado:** `200 OK` com os dados completos do workflow.

### 3.4 Atualizar workflow

Alterar o campo `descricao` no YAML e enviar:

```bash
curl -X PUT http://localhost:8081/bff/flows/teste-http \
  -H "Content-Type: text/plain" \
  --data-binary @wf-http-atualizado.yml
```

**Resultado esperado:** `200 OK`. Buscar novamente e confirmar que `descricao` foi atualizada.

### 3.5 Desativar workflow

```bash
curl -X DELETE http://localhost:8081/bff/flows/teste-http
```

**Resultado esperado:** `200 OK`. Workflow não deve mais aparecer na listagem (`ativo: false` no MongoDB). **No frontend:** confirmar que sumiu da tabela.

### 3.6 Recriar para os próximos testes

Após 3.5, recriar o workflow para os testes de execução (repetir 3.1).

---

## 4. Execução — workflow HTTP

**Pré-requisito:** WF-HTTP cadastrado e ativo.

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/teste-http \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "CLI001A"}'
```

**Resultado esperado:**
```json
{
  "executionId": "<uuid>",
  "flowId": "teste-http",
  "status": "SUCCESS",
  "resultado": {
    "buscar-cliente": {
      "nomeCliente": "Leanne Graham"
    }
  },
  "iniciadoEm": "<timestamp>",
  "finalizadoEm": "<timestamp>"
}
```

**Pontos a validar:**
- `status` é `SUCCESS`
- `resultado.buscar-cliente.nomeCliente` preenchido com dado real da API externa
- `mapeamentoResposta` funcionou: campo `name` do response mapeado para `nomeCliente`
- Timestamps presentes e coerentes

### Cenário — serviço HTTP retorna erro com `continuarEmErro: false`

Alterar temporariamente a URL para uma inválida e re-executar.

**Resultado esperado:** `status: FAILURE` ou `ERROR`, execução interrompida no passo `buscar-cliente`.

---

## 5. Execução — workflow DATABASE

**Pré-requisito:** WF-DATABASE cadastrado e ativo.

### Cenário feliz — INSERT

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/teste-database \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "CLI001A", "valor": 299.90}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "resultado": {
    "salvar-pedido": {
      "pedidoId": "<ObjectId gerado>"
    }
  }
}
```

**Verificar no MongoDB:**
```js
db.getCollection("pedidos-teste").find().sort({ _id: -1 }).limit(1)
// deve retornar o documento recém inserido
```

**Pontos a validar:**
- `pedidoId` retornado no resultado (mapeamento de `_id` para `pedidoId` funcionou)
- Documento presente na collection `pedidos-teste` com `status: "CRIADO"`
- Campo `ts` preenchido com timestamp via `{{now()}}`

### Cenário — FIND_ONE após INSERT

Criar um segundo workflow de consulta para buscar o documento inserido e validar o `filtroTemplate`.

---

## 6. Execução — workflow QUEUE RabbitMQ

**Pré-requisito:** WF-RABBITMQ cadastrado, exchange `pedidos.exchange` criada no RabbitMQ.

**Criar a exchange/fila antes do teste:**
```bash
# via Management UI (http://localhost:15672) ou rabbitmqadmin
# criar exchange: pedidos.exchange (type: direct)
# criar fila: pedidos-criados
# fazer binding: pedidos.exchange → pedidos-criados (routingKey: pedido.criado)
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/teste-rabbitmq \
  -H "Content-Type: application/json" \
  -d '{"pedidoId": "PED-001"}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "resultado": {
    "rabbitmq-notifier": {
      "provider": "RABBITMQ",
      "integrationId": "rabbitmq-notifier",
      "published": true
    }
  }
}
```

**Verificar no RabbitMQ:**
- Acessar `http://localhost:15672` → Queues → `pedidos-criados`
- Confirmar mensagem na fila com conteúdo `{"evento":"PEDIDO_CRIADO","pedidoId":"PED-001",...}`

---

## 7. Execução — workflow QUEUE Kafka

**Pré-requisito:** WF-KAFKA cadastrado, tópico `pedidos.criados` existente.

**Criar o tópico:**
```bash
docker exec -it <kafka-container> \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic pedidos.criados --partitions 1 --replication-factor 1
```

**Abrir consumer para monitorar:**
```bash
docker exec -it <kafka-container> \
  kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic pedidos.criados --from-beginning
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/teste-kafka \
  -H "Content-Type: application/json" \
  -d '{"pedidoId": "PED-001"}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "resultado": {
    "kafka-user-tracking": {
      "provider": "KAFKA",
      "integrationId": "kafka-user-tracking",
      "topic": "pedidos.criados",
      "partition": 0,
      "offset": "<numero>",
      "published": true
    }
  }
}
```

**Verificar no consumer:** mensagem `{"evento":"PEDIDO_CRIADO","pedidoId":"PED-001"}` deve aparecer.

---

## 8. Execução — workflow QUEUE SQS

**Pré-requisito:** WF-SQS cadastrado, fila criada no LocalStack.

**Criar a fila no LocalStack:**
```bash
aws --endpoint-url=http://localhost:4566 \
  sqs create-queue --queue-name pedidos-teste
```

### Cenário feliz

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/teste-sqs \
  -H "Content-Type: application/json" \
  -d '{"pedidoId": "PED-001"}'
```

**Resultado esperado:** `status: SUCCESS`, `published: true`.

**Verificar na fila:**
```bash
aws --endpoint-url=http://localhost:4566 \
  sqs receive-message \
  --queue-url http://localhost:4566/000000000000/pedidos-teste
```
Deve retornar a mensagem com o corpo correto.

---

## 9. Execução — workflow completo (todos os tipos)

**Pré-requisito:** WF-COMPLETO (`criar-pedido-v1`) cadastrado + infraestrutura dos testes 4 a 8 pronta.

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/criar-pedido-v1 \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "CLI001A", "valor": 499.90}'
```

**Resultado esperado:**
```json
{
  "status": "SUCCESS",
  "resultado": {
    "validar-cliente": { ... },
    "salvar-pedido": { "pedidoId": "<id>" },
    "rabbitmq-notifier": { "published": true },
    "kafka-user-tracking": { "published": true, "topic": "pedidos.criados" },
    "notificar-sqs": { "published": true }
  }
}
```

**Pontos a validar em sequência:**
1. Passo HTTP executado primeiro — response mapeado no contexto
2. Passo DATABASE usou `{{contrato.clienteId}}` corretamente — documento no MongoDB
3. Passo RabbitMQ usou `{{integracoes.salvar-pedido.pedidoId}}` — referência entre passos funcionou
4. Passo Kafka publicou no tópico correto
5. Passo SQS publicou na fila LocalStack
6. `continuarEmErro: true` nos passos de queue — falha em um não interrompe os seguintes

**Cenário — falha isolada em queue com `continuarEmErro: true`**

Derrubar o RabbitMQ temporariamente e re-executar. O esperado é:
- Passo `rabbitmq-notifier` falha
- Passos `kafka-user-tracking` e `notificar-sqs` continuam e são executados
- `status` geral indica execução parcial (verificar comportamento atual do orquestrador)

---

## 10. Cenários negativos e validações de contrato

### 10.1 Payload inválido — campo obrigatório ausente

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/criar-pedido-v1 \
  -H "Content-Type: application/json" \
  -d '{"valor": 100.00}'
```

**Esperado:** `400 Bad Request` com mensagem indicando que `clienteId` é obrigatório.

### 10.2 Payload inválido — PATTERN não respeitado

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/criar-pedido-v1 \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "id inválido!", "valor": 100.00}'
```

**Esperado:** `400 Bad Request` com mensagem `"clienteId inválido"` (definida no PATTERN do contrato).

### 10.3 Payload inválido — tipo errado

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/criar-pedido-v1 \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "CLI001A", "valor": "nao-e-numero"}'
```

**Esperado:** `400 Bad Request` indicando tipo inválido para `valor`.

### 10.4 Payload inválido — valor não positivo (POSITIVE)

```bash
-d '{"clienteId": "CLI001A", "valor": -50.00}'
```

**Esperado:** `400 Bad Request`.

### 10.5 Workflow inexistente

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v1/fluxo-inexistente \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Esperado:** `404 Not Found`.

### 10.6 Versão errada

```bash
curl -X POST http://localhost:8081/bff/orchestrate/v99/criar-pedido-v1 \
  -H "Content-Type: application/json" \
  -d '{"clienteId": "CLI001A", "valor": 100.00}'
```

**Esperado:** `404 Not Found` — não existe workflow com `id: criar-pedido-v1` e `versao: v99`.

### 10.7 YAML inválido no cadastro

```bash
curl -X POST http://localhost:8081/bff/flows \
  -H "Content-Type: text/plain" \
  -d 'yaml: isto: nao: e: valido: :::'
```

**Esperado:** `400 Bad Request` com mensagem de parse error.

### 10.8 Cadastrar workflow com ID duplicado

Enviar o mesmo YAML duas vezes.

**Esperado:** segundo `POST` retorna erro de conflito (verificar comportamento atual — pode ser `409 Conflict` ou atualização silenciosa).

---

## Checklist de execução

```
[ ] 1. Saúde do sistema — todos os serviços no ar
[ ] 2. Server Driven UI — menu e navegação OK
[ ] 3. CRUD completo — criar, listar, buscar, atualizar, desativar
[ ] 4. Execução HTTP — cenário feliz + erro com continuarEmErro: false
[ ] 5. Execução DATABASE — INSERT + mapeamento de _id
[ ] 6. Execução RabbitMQ — mensagem na fila confirmada
[ ] 7. Execução Kafka — mensagem no tópico confirmada
[ ] 8. Execução SQS — mensagem na fila LocalStack confirmada
[ ] 9. Execução completa — todos os passos em sequência + referência entre passos
[ ] 10. Cenários negativos — validações de contrato e erros de roteamento
```

---

## Tarefa desta sessão (para usar com o Claude)

> Preencha quando for pedir implementação de algum cenário de teste.

**Cenário a implementar:**
(ex: teste unitário Java para o cenário 10.1 — campo obrigatório ausente)

**Componente alvo:**
(ex: `generic-orchestrator` — `FlowValidationService`)

**Arquivos relevantes:**
(cole os arquivos ou liste os caminhos)

**O que não quero que mude:**
(ex: não usar Mockito para esse caso, usar apenas JUnit 5)