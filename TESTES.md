# Guia de Execução de Testes — Service Portal

Este documento descreve como executar os testes integrados do Service Portal após as atualizações recentes.

## Testes Unitários

Cada componente possui gate de cobertura ≥ 95%. Para rodar:

### generic-orchestrator
```bash
cd generic-orchestrator
./gradlew test jacocoTestCoverageVerification
```
**Cobertura atual:** ~99% INSTRUCTION

### service-portal-bff
```bash
cd service-portal-bff
./gradlew test jacocoTestCoverageVerification
```
**Cobertura atual:** 100% INSTRUCTION

### service-portal-manager
```bash
cd service-portal-manager
./gradlew test jacocoTestCoverageVerification
```
**Cobertura atual:** 96% INSTRUCTION

### service-portal-frontend
```bash
cd service-portal-frontend
npm run coverage
```
**Cobertura atual:** 100% lines/branches/functions/statements

---

## Testes Integrados (End-to-End)

### Modo automático

Um script `teste-integrado-service-portal.sh` automatiza a maioria dos testes:

```bash
# Torna executável (primeira vez)
chmod +x teste-integrado-service-portal.sh

# Executa testes
./teste-integrado-service-portal.sh
```

**O que o script faz:**
1. Verifica pré-requisitos (Docker, curl, arquivos de config)
2. Para containers anteriores e inicia nova stack via docker-compose
3. Aguarda serviços ficarem prontos (BFF, Orquestrador, Manager)
4. Testa saúde do sistema (health checks)
5. Testa Server Driven UI (menu e schemas)
6. Cria workflows de teste em formato inglês
7. Testa CRUD de workflows via Manager
8. Testa execução de workflows (HTTP, RabbitMQ, Kafka)
9. Testa cenários negativos (validações de contrato)
10. Gera relatório em Markdown

**Saída:**
- Log detalhado: `teste-integrado-<timestamp>.log`
- Checklist: `teste-integrado-checklist-<timestamp>.md`

### Modo manual

Para testes mais detalhados ou Debug, veja [teste-integrado.md](teste-integrado.md) com instruções step-by-step.

**Passos principais:**

1. **Subir a stack**
   ```bash
   cp env.example .env
   echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
   echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
   echo "ORCHESTRATOR_JWT_SECRET=$(openssl rand -base64 60 | tr -d '\n')" >> .env
   
   docker compose -f docker-compose-service-portal.yml up -d
   ```

2. **Aguardar serviços**
   ```bash
   # Verificar saúde
   curl -s http://localhost:8081/bff/health | jq .
   curl -s http://localhost:8080/actuator/health | jq .
   curl -s http://localhost:8082/actuator/health | jq .
   ```

3. **Criar workflow de teste** (em formato inglês)
   ```bash
   cat > wf-test.yml <<'EOF'
   flow:
     flowId: test-http
     version: "1.0.0"
     description: "Test workflow"
     active: true
     contract:
       fields:
         - name: clientId
           type: STRING
           required: true
     integrations:
       - id: fetch-client
         order: 1
         type: HTTP
         continueOnError: false
         http:
           url: "http://api.exemplo.com/clients/CLI001A"
           method: GET
           timeout: 5000
   EOF
   
   curl -X POST http://localhost:8081/bff/flows \
     -H "Content-Type: text/plain" \
     --data-binary @wf-test.yml
   ```

4. **Listar workflows**
   ```bash
   curl http://localhost:8081/bff/flows | jq .
   ```

5. **Executar workflow**
   ```bash
   curl -X POST http://localhost:8081/bff/flows/test-http/versions/1.0.0/executions \
     -H "Content-Type: application/json" \
     -d '{"clientId":"CLI001A"}' | jq .
   ```

---

## Pontos-Chave das Atualizações Recentes

### Formato YAML — Inglês

Todos os workflows agora usam **inglês**:
- `flow:` (era `fluxo:`)
- `flowId`, `version`, `description`, `active` (era `id`, `versao`, `descricao`, `ativo`)
- `contract` → `fields` (era `contrato` → `campos`)
- `integrations` (era `integracoes`)
- `continueOnError` (era `continuarEmErro`)
- `responseMapping`, `messageTemplate` (era `mapeamentoResposta`, `mensagemTemplate`)

### Endpoints REST

Padrão **sub-recursos** com versionamento explícito:
- `POST /bff/flows` — criar workflow
- `GET /bff/flows?page=0&size=20` — listar (paginado)
- `GET /bff/flows/{flowId}/versions/{version}` — detalhe
- `GET /bff/flows/{flowId}/versions/{version}/yaml` — YAML cru
- `PUT /bff/flows/{flowId}/versions/{version}` — atualizar
- `DELETE /bff/flows/{flowId}/versions/{version}` — desativar (soft-delete)
- `POST /bff/flows/{flowId}/versions/{version}/executions` — **executar workflow**

### Arquitetura (CRUD vs Execução)

- **CRUD**: delegado ao `service-portal-manager` (Kotlin, :8082)
- **Execução**: orquestrador (`generic-orchestrator`, :8080)
- **Cache**: workflows em Redis (TTL 1h) no orquestrador
- **Persistência**: collection `workflows` no MongoDB via Manager

### Integrações Removidas

- ❌ `IntegrationType.DATABASE` — removido do orquestrador
- ✅ `IntegrationType.HTTP` — com Retry + Circuit Breaker
- ✅ `IntegrationType.QUEUE` — RabbitMQ, Kafka, SQS

---

## Monitoramento com Portainer

Acesse **http://localhost:9001** para monitorar os containers em tempo real:

1. **Containers**: status de cada serviço (healthy/running/exited)
2. **Logs**: visualizar logs em tempo real de cada container
3. **Stats**: CPU, memória, I/O por container
4. **Networks**: visualizar conectividade entre serviços
5. **Volumes**: gerenciar dados persistentes

**Dica:** Abra Portainer durante a execução do script de testes para acompanhar recursos.

---

## Troubleshooting

### Docker compose não inicia
```bash
# Limpar state antigo
docker compose -f docker-compose-service-portal.yml down -v

# Verificar se há processos pendurados
docker ps -a | grep -i service-portal

# Reconstruir imagens
docker compose -f docker-compose-service-portal.yml build --no-cache

# Ver logs do Portainer (se houver erro de socket)
docker logs portal-portainer
```

### Serviços não ficam healthy
```bash
# Verificar logs
docker compose -f docker-compose-service-portal.yml logs <service>

# Verificar conectividade interna
docker exec <container> ping <outro-container>

# Porta em uso
netstat -an | grep LISTEN | grep 8081
```

### Workflow não encontrado (404)
```bash
# Verificar se foi criado no Manager
curl http://localhost:8082/manager/flows | jq .

# Verificar no MongoDB
docker exec <mongo> mongosh generic-orchestrator --eval "db.workflows.find()"
```

### Execução falha silenciosamente
```bash
# Verificar logs do orquestrador
docker compose -f docker-compose-service-portal.yml logs orchestrator -f

# Verificar cache Redis
docker exec <redis> redis-cli keys "*"
```

---

## Próximas Etapas

1. **Configurar Authentik** (primeira vez) — http://localhost:9000/if/flow/initial-setup/
   - Criar admin
   - Criar OAuth2/OIDC Provider
   - Criar Application com slug `service-portal`
   - Adicionar client público `service-portal-spa`

2. **Testes com Authentik** — validar login PKCE no frontend

3. **Documentação AGENTS.md** — (pendente) criar por aplicação

---

## Ferramentas de Suporte

### Portainer — Gerenciamento de Containers
- **URL:** http://localhost:9001
- **Uso:** monitorar status, logs e recursos dos containers
- **Primeiro acesso:** crie usuário admin
- **Benefícios:** visualizar saúde da stack em tempo real durante testes

### Comandos Úteis
```bash
# Ver containers rodando
docker ps

# Ver logs de um serviço específico
docker logs portal-bff -f

# Executar comando dentro de um container
docker exec -it portal-mongodb mongosh generic-orchestrator

# Ver estatísticas de recursos
docker stats --no-stream

# Pausar/resumir container
docker pause portal-orchestrator
docker unpause portal-orchestrator

# Reiniciar serviço
docker compose -f docker-compose-service-portal.yml restart orchestrator
```

---

## Referências

- [teste-integrado.md](teste-integrado.md) — cenários detalhados
- [PLAN.md](PLAN.md) — progresso e decisões arquiteturais
- [README.md](README.md) — visão geral do projeto
- [arquitetura-portal-service.md](arquitetura-portal-service.md) — diagrama de arquitetura
- http://localhost:9001 — **Portainer (gerenciamento visual)**
