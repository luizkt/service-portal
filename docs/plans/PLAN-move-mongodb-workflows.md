# PLAN: Mover `mongodb-workflows/` do orquestrador para o Manager

## Contexto

O `generic-orchestrator` deixou de acessar o MongoDB diretamente — todo acesso à collection `workflows` (e às collections `integrations`, `contracts`, `validations`) é feito via API REST do `service-portal-manager`. Ainda assim, o script de inicialização do banco (`init-mongo.js`) reside em `generic-orchestrator/mongodb-workflows/`, o que cria uma inconsistência de responsabilidade: o orquestrador "dono" do script que inicializa o banco de um serviço do qual não depende mais.

O objetivo é mover o script para dentro do Manager e renomear o database de `generic-orchestrator` para `service-portal-manager`, alinhando nomenclatura com o serviço responsável.

---

## Escopo

| Arquivo | Mudança |
|---|---|
| `generic-orchestrator/mongodb-workflows/init-mongo.js` | **Excluído** (pasta movida) |
| `service-portal-manager/mongodb-manager/init-mongo.js` | **Criado** (conteúdo atualizado com novo nome de DB) |
| `docker-compose-service-portal.yml` (raiz) | Volume mount do MongoDB + defaults `MONGODB_DATABASE` |
| `service-portal-manager/docker-compose.yml` | Volume mount + comentário + default `MONGODB_DATABASE` |
| `generic-orchestrator/AGENTS.md` | Remover menção ao script de init Mongo |
| `service-portal-manager/AGENTS.md` | Adicionar seção sobre `mongodb-manager/` |
| `generic-orchestrator/README.md` | Remover menção ao script de init Mongo (se houver) |
| `service-portal-manager/README.md` | Adicionar seção sobre o script de init |

---

## Implementação passo a passo

### 1. Criar `service-portal-manager/mongodb-manager/init-mongo.js`

Conteúdo do novo script — apenas muda o nome do database:

```javascript
db = db.getSiblingDB('service-portal-manager');

db.createCollection('workflows');
db.createCollection('integrations');
db.createCollection('contracts');
db.createCollection('validations');

db.workflows.createIndex({ "flowId": 1, "version": 1 }, { unique: true, sparse: true });
db.integrations.createIndex({ "integrationId": 1, "version": 1 }, { unique: true, sparse: true });
db.contracts.createIndex({ "contractId": 1, "version": 1 }, { unique: true, sparse: true });
db.validations.createIndex({ "validationId": 1, "version": 1 }, { unique: true, sparse: true });

print('[init-mongo] Database service-portal-manager initialized: workflows, integrations, contracts, validations.');
```

### 2. Excluir `generic-orchestrator/mongodb-workflows/`

Remover a pasta inteira após criação do novo arquivo.

### 3. Atualizar `docker-compose-service-portal.yml` (raiz)

**Serviço `mongodb`** — dois pontos a atualizar:

```yaml
# ANTES
environment:
  MONGO_INITDB_DATABASE: ${MONGODB_DATABASE:-generic-orchestrator}
volumes:
  - mongo_data:/data/db
  - ./generic-orchestrator/mongodb-workflows:/docker-entrypoint-initdb.d:ro

# DEPOIS
environment:
  MONGO_INITDB_DATABASE: ${MONGODB_DATABASE:-service-portal-manager}
volumes:
  - mongo_data:/data/db
  - ./service-portal-manager/mongodb-manager:/docker-entrypoint-initdb.d:ro
```

**Serviço `manager`** — atualizar defaults das env vars:

```yaml
# ANTES
MONGODB_URI:      mongodb://mongodb:27017/${MONGODB_DATABASE:-generic-orchestrator}
MONGODB_DATABASE: ${MONGODB_DATABASE:-generic-orchestrator}

# DEPOIS
MONGODB_URI:      mongodb://mongodb:27017/${MONGODB_DATABASE:-service-portal-manager}
MONGODB_DATABASE: ${MONGODB_DATABASE:-service-portal-manager}
```

### 4. Atualizar `service-portal-manager/docker-compose.yml`

```yaml
# ANTES (linhas 9 e 30-32)
# O init script (../generic-orchestrator/mongodb-workflows) cria a database
# `generic-orchestrator` ...
environment:
  MONGO_INITDB_DATABASE: ${MONGODB_DATABASE:-generic-orchestrator}
volumes:
  - ../generic-orchestrator/mongodb-workflows:/docker-entrypoint-initdb.d:ro

# DEPOIS
# O init script (mongodb-manager/) cria a database
# `service-portal-manager` ...
environment:
  MONGO_INITDB_DATABASE: ${MONGODB_DATABASE:-service-portal-manager}
volumes:
  - ./mongodb-manager:/docker-entrypoint-initdb.d:ro
```

### 5. Atualizar `generic-orchestrator/AGENTS.md`

Remover qualquer menção a `mongodb-workflows/` ou ao script de inicialização do Mongo.
Adicionar nota: "O banco de dados é gerenciado exclusivamente pelo `service-portal-manager`."

### 6. Atualizar `service-portal-manager/AGENTS.md`

Adicionar seção sobre o diretório `mongodb-manager/`:

```markdown
## Inicialização do MongoDB

O arquivo `mongodb-manager/init-mongo.js` cria o database `service-portal-manager`
com as collections `workflows`, `integrations`, `contracts` e `validations`, cada
uma com índice único composto `(id, version)`.

Este script é montado em `/docker-entrypoint-initdb.d/` no container MongoDB e
executado automaticamente na primeira inicialização (volume vazio).
```

### 7. Atualizar READMEs

- `generic-orchestrator/README.md`: remover menção ao script de init Mongo (se houver).
- `service-portal-manager/README.md`: adicionar seção "Inicialização do MongoDB" com instrução de uso.

---

## Arquivos críticos

| Arquivo | Relevância |
|---|---|
| `generic-orchestrator/mongodb-workflows/init-mongo.js` | Origem — será excluído |
| `service-portal-manager/mongodb-manager/init-mongo.js` | Destino — será criado |
| `docker-compose-service-portal.yml` | Volume mount + env vars do MongoDB e Manager |
| `service-portal-manager/docker-compose.yml` | Volume mount per-app compose |
| `service-portal-manager/AGENTS.md` | Documentação do script |
| `generic-orchestrator/AGENTS.md` | Remover referências ao Mongo |

---

## Consideração importante: renomeação do database

O database será renomeado de `generic-orchestrator` para `service-portal-manager`.

**Impacto:** quem tiver volumes Docker já criados com dados em `generic-orchestrator` precisará destruir os volumes antes de subir novamente:

```bash
docker compose down -v          # destrói volumes (apaga dados locais)
docker compose up -d            # re-cria com novo nome de database
```

Em produção ou ambientes com dados persistidos, seria necessário uma migração. Para o contexto atual (desenvolvimento local), `down -v && up` é suficiente.

**Não há impacto no código Kotlin do Manager** — o nome do database é injetado via env var `MONGODB_DATABASE` no `application-docker.yml`:
```yaml
spring:
  data:
    mongodb:
      uri: ${MONGODB_URI:mongodb://localhost:27017/service-portal-manager}
```
Apenas os defaults nos docker-composes precisam mudar.

---

## Verificação

1. **Destruir volumes antigos** (necessário pela renomeação do DB):
   ```bash
   docker compose -f docker-compose-service-portal.yml down -v
   ```

2. **Subir a stack**:
   ```bash
   docker compose -f docker-compose-service-portal.yml up -d
   ```

3. **Verificar que o MongoDB inicializou o database correto**:
   ```bash
   docker exec portal-mongodb mongosh --eval "db.getSiblingDB('service-portal-manager').getCollectionNames()"
   # Esperado: ["contracts", "integrations", "validations", "workflows"]
   ```

4. **Verificar que o Manager sobe healthy**:
   ```bash
   docker ps --filter name=portal-manager --format "{{.Status}}"
   # Esperado: Up X minutes (healthy)
   ```

5. **Verificar health do Manager**:
   ```bash
   curl -s http://localhost:8082/actuator/health | grep '"status":"UP"'
   ```

6. **Confirmar que a pasta antiga não existe mais**:
   ```bash
   ls generic-orchestrator/mongodb-workflows 2>&1
   # Esperado: No such file or directory
   ```

7. **Executar script de testes integrados** (opcional mas recomendado):
   ```bash
   ./teste-integrado-service-portal-v3.sh
   # Esperado: 32/33 (96%) passando
   ```
