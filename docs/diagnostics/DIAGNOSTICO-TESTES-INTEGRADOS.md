# Diagnóstico dos Testes Integrados - Service Portal

**Data**: 2026-05-16  
**Status**: 🔍 ANALISADO  
**Arquivo Log**: `teste-integrado-20260516-204125.log`

---

## 🎯 Problemas Identificados

### 1. **RabbitMQ - Endpoint Incorreto** ❌

**Teste Atual** (linha 184):
```bash
curl -sf http://guest:guest@localhost:15672/api/health
```

**Problema**: 
- Endpoint `/api/health` não existe em RabbitMQ
- Porta 15672 é management UI (HTTP)
- RabbitMQ não expõe `/api/health` por padrão

**Solução**: Usar endpoint correto de health check:
```bash
curl -sf http://guest:guest@localhost:15672/api/aliveness-test/%2F
```
Ou remover este teste se RabbitMQ for opcional.

---

### 2. **Autenticação BFF** - 401 em Todos os Endpoints ⚠️

**Problemas Observados**:
- `POST /bff/flows` → HTTP 401
- `POST /bff/flows/*/executions` → HTTP 401
- Todos os endpoints da BFF retornam 401

**Possíveis Causas**:
1. BFF espera autenticação/token JWT
2. BFF espera header `Authorization: Bearer <token>`
3. Script não está enviando credenciais

**Investigação Necessária**:
```bash
# 1. Verificar se BFF precisa de autenticação
curl -v http://localhost:8081/bff/menu

# 2. Tentar com Authentik token
TOKEN=$(curl -s -X POST http://localhost:9000/application/o/service-portal/token/... -d '...')
curl -H "Authorization: Bearer $TOKEN" http://localhost:8081/bff/flows
```

---

### 3. **Server Driven UI - Endpoints Não Existem** ❌

**Testes Falhando**:
- `GET /bff/menu` → Menu não contém 'flow-manager'
- `GET /bff/features/flow-manager/ui-schema` → Schema não encontrado

**Possíveis Causas**:
1. Endpoints não estão implementados em BFF
2. Endpoints requerem autenticação
3. Feature ID ou estrutura diferente da esperada

**Verificação Necessária**:
```bash
# Verificar quais endpoints estão realmente disponíveis
curl http://localhost:8081/bff/
curl http://localhost:8081/actuator/mappings  # Spring Boot Actuator
```

---

### 4. **Criação de Workflows - Content-Type Incorreto** ❌

**Teste Atual** (linha 258):
```bash
curl -X POST http://localhost:8081/bff/flows \
    -H "Content-Type: text/plain" \
    -d "$FLOW_HTTP"
```

**Problema**:
- `Content-Type: text/plain` pode não ser aceito
- Endpoints CRUD geralmente esperam `application/json` ou `application/yaml`
- Request sem autenticação retorna 401

**Solução**:
```bash
# Tentar com application/yaml
curl -X POST http://localhost:8081/bff/flows \
    -H "Content-Type: application/yaml" \
    -d "$FLOW_YAML"

# Ou com application/json se esperado
curl -X POST http://localhost:8081/bff/flows \
    -H "Content-Type: application/json" \
    -d "$FLOW_JSON"
```

---

### 5. **CRUD Workflows Dependem de Criação** 🔗

**Cadeia de Dependências**:
```
create_test_workflows() [FAILS 401]
    ↓
test_crud_workflows() [FAILS - workflows não existem]
    ↓
test_execution_http() [FAILS - workflows não existem]
    ↓
test_execution_queue() [FAILS - workflows não existem]
    ↓
test_negative_scenarios() [FAILS - todos retornam 401]
```

**Impacto**: Se workflows não forem criados, toda a cadeia falha.

---

### 6. **Negative Scenarios - 401 ao Invés de 400/404** ❌

**Teste 6.1** (linha 427):
```bash
curl -X POST http://localhost:8081/bff/flows/create-order-v1/.../executions \
    -H "Content-Type: application/json" \
    -d '{}' \
# Esperado: HTTP 400 (Bad Request)
# Recebido: HTTP 401 (Unauthorized)
```

**Causa**: Autenticação requerida antes da validação.

---

## 📋 Checklist de Verificação

### Para Entender o Estado Real do Sistema

```bash
# 1. Verificar status dos containers
docker compose ps

# 2. Verificar logs do BFF
docker compose logs bff | tail -50

# 3. Testar health dos serviços
curl -v http://localhost:8081/bff/health
curl -v http://localhost:8080/actuator/health
curl -v http://localhost:8082/actuator/health

# 4. Verificar endpoints disponíveis em BFF
curl -v http://localhost:8081/bff/
curl -v http://localhost:8081/actuator/mappings | jq '.contexts.application.mappings.servletHandlerMappings[] | select(.handler | contains("Bff")) | .handler' 2>/dev/null | head -20

# 5. Verificar se Authentik está funcionando
curl -v http://localhost:9000/api/system/status

# 6. Tentar obter token do Authentik
curl -X POST http://localhost:9000/application/o/service-portal/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=...&client_secret=..."

# 7. Testar endpoints de workflow
curl -v -H "Content-Type: application/yaml" http://localhost:8081/bff/flows

# 8. Verificar RabbitMQ management API
curl -v http://guest:guest@localhost:15672/api/aliveness-test/%2F
```

---

## 🛠️ Soluções Propostas

### Fase 1: Corrigir Testes Básicos
1. ✅ Remover teste RabbitMQ `/api/health` (usar `/api/aliveness-test/%2F`)
2. ✅ Verificar se BFF realmente expõe `/bff/menu` e `/bff/features/...`
3. ✅ Verificar se BFF está configurado com autenticação obrigatória

### Fase 2: Adicionar Autenticação
1. Se BFF requer autenticação:
   - Adicionar passo de login no script antes dos testes
   - Extrair token JWT
   - Incluir `Authorization: Bearer $TOKEN` em todos os requests

2. Se autenticação é via Authentik:
   - Fazer login no Authentik
   - Obter token
   - Usar token nos requests subsequentes

### Fase 3: Verificar Endpoints
1. Confirmar quais endpoints realmente existem em BFF
2. Testar com `curl` manualmente para validar request/response
3. Atualizar script para usar endpoints corretos e content-types apropriados

### Fase 4: Melhorar o Script
1. Adicionar validação de prerequisites para endpoints (testar antes de rodar)
2. Adicionar logging detalhado (incluir request/response bodies)
3. Melhorar tratamento de erros (mostrar response da API, não só HTTP code)
4. Adicionar retry logic para endpoints flaky

---

## 📊 Sumário de Mudanças Necessárias

| Componente | Problema | Solução | Prioridade |
|-----------|----------|---------|-----------|
| **test_health()** | RabbitMQ endpoint incorreto | Usar `/api/aliveness-test/%2F` | 🔴 ALTA |
| **test_server_driven_ui()** | Endpoints podem não existir | Validar com Actuator mappings | 🔴 ALTA |
| **create_test_workflows()** | 401 em todos os POSTs | Adicionar autenticação | 🔴 ALTA |
| **test_crud_workflows()** | Falha por workflows não criados | Depende de Phase 1 | 🟡 MÉDIA |
| **test_execution_*()** | Falha por workflows não criados | Depende de Phase 1 | 🟡 MÉDIA |
| **test_negative_scenarios()** | 401 ao invés de 400/404 | Adicionar autenticação | 🔴 ALTA |
| **Content-Type** | `text/plain` para workflows | Usar `application/yaml` | 🟡 MÉDIA |
| **Error handling** | Pouco detalhe em erros | Adicionar `jq` parsing e logging | 🟢 BAIXA |

---

## 🔗 Próximas Etapas

1. **Executar checklist de verificação** acima
2. **Identificar requirement de autenticação** em BFF
3. **Atualizar script** conforme findings
4. **Testar e validar** cada mudança
5. **Documentar endpoints** finais no README

---
