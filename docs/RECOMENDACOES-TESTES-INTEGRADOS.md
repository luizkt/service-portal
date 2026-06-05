# Recomendações para Correção dos Testes Integrados

**Data**: 2026-05-16  
**Status**: 📋 DOCUMENTAÇÃO DE RECOMENDAÇÕES  
**Baseado em**: `teste-integrado-20260516-204125.log`

---

## 📊 Sumário Executivo

O script de testes (`teste-integrado-service-portal.sh`) identificou **5 grupos principais de problemas**:

| Problema | Severidade | Impacto | Status |
|----------|-----------|--------|--------|
| **RabbitMQ healthcheck endpoint incorreto** | 🔴 CRÍTICA | Teste fail falso | ❌ Não corrigido |
| **Falta de autenticação nos testes** | 🔴 CRÍTICA | 401 em todos endpoints | ❌ Não corrigido |
| **Endpoints BFF não mapeados ou desabilitados** | 🟡 ALTA | Server Driven UI fails | ❌ Desconhecido |
| **Content-Type dos workflows** | 🟡 ALTA | Criação de workflows falha | ❌ Não corrigido |
| **CRUD/Execução dependem de criação** | 🟢 MÉDIA | Cascata de falhas | ✅ Por design |

---

## 🔧 Ações Recomendadas

### **Ação 1: Validar Endpoints Reais da BFF**

**Objetivo**: Confirmar quais endpoints estão realmente implementados

**Procedimento**:
```bash
# 1. Listar todos os endpoints mapeados em BFF
curl -s http://localhost:8081/actuator/mappings | \
  jq '.contexts.application.mappings.servletHandlerMappings[] | {handler: .handler, methods: .methods}' | \
  head -50

# 2. Tentar acessar /bff/menu diretamente
curl -v http://localhost:8081/bff/menu

# 3. Procurar por "menu" nos logs da BFF
docker compose logs bff | grep -i "menu"

# 4. Verificar se há endpoints /bff/features
curl -v http://localhost:8081/bff/features
```

**Ações Baseadas no Resultado**:
- ✅ Se endpoints existem: Prosseguir para Ação 2
- ❌ Se endpoints não existem: Implementar endpoints ou desabilitar testes correspondentes

---

### **Ação 2: Determinar Requisito de Autenticação BFF**

**Objetivo**: Identificar se BFF requer token JWT e como obtê-lo

**Procedimento**:
```bash
# 1. Testar endpoint sem autenticação
curl -v -H "Authorization:" http://localhost:8081/bff/flows

# 2. Verificar resposta (401 = requer auth, 200 = publico)
HTTP_CODE=$?

# 3. Se 401, procurar em logs qual tipo de token é esperado
docker compose logs bff | grep -i "token\|jwt\|bearer\|auth"

# 4. Tentar várias estratégias de auth:

# Estratégia A: Bearer Token do Authentik
curl -H "Authorization: Bearer $AUTHENTIK_TOKEN" http://localhost:8081/bff/flows

# Estratégia B: Bearer Token do Manager
curl -H "Authorization: Bearer $MANAGER_TOKEN" http://localhost:8081/bff/flows

# Estratégia C: Session Cookie
curl -b "session=$SESSION_COOKIE" http://localhost:8081/bff/flows
```

**Ações Baseadas no Resultado**:
- ✅ Se BFF não requer auth: Remover lógica de auth do script
- ✅ Se BFF requer auth Authentik: Adicionar passo de login Authentik
- ✅ Se BFF requer auth Manager: Adicionar passo de login Manager
- ❌ Se nenhuma estratégia funciona: Verificar configuração de Spring Security em BFF

---

### **Ação 3: Corrigir Criação de Workflows**

**Objetivo**: Permitir criação bem-sucedida de workflows via Manager ou BFF

**Investigação**:
```bash
# 1. Verificar qual é o endpoint correto
curl -H "Authorization: Bearer $MANAGER_TOKEN" http://localhost:8082/actuator/mappings | \
  jq '.contexts.application.mappings.servletHandlerMappings[] | select(.handler | contains("flow"))' | head -20

# 2. Testar criação com diferentes content-types
curl -X POST http://localhost:8082/manager/flows \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{...}'

curl -X POST http://localhost:8082/manager/flows \
  -H "Content-Type: application/yaml" \
  -H "Authorization: Bearer $TOKEN" \
  -d 'flow: {...}'

# 3. Se ambos falharem, verificar logs
docker compose logs manager | grep -i "flow\|workflow" | tail -20
```

**Atualizações Necessárias** (se OK):
- Atualizar `teste-integrado-service-portal.sh` com endpoint correto
- Adicionar autenticação via token Manager
- Usar content-type correto (application/json vs application/yaml)

---

### **Ação 4: Corrigir RabbitMQ Healthcheck**

**Objetivo**: Usar endpoint correto para validar RabbitMQ

**Alteração no Script**:
```bash
# ANTES (incorreto):
curl -sf http://guest:guest@localhost:15672/api/health > /dev/null 2>&1

# DEPOIS (correto):
curl -sf http://guest:guest@localhost:15672/api/aliveness-test/%2F > /dev/null 2>&1
```

**Impacto**: Mínimo - apenas corrige um teste falso

---

### **Ação 5: Criar Script de Validação Preliminar**

**Objetivo**: Antes de rodar testes, validar estado real do sistema

```bash
#!/bin/bash
# validate-infrastructure.sh

echo "=== DIAGNÓSTICO PRÉ-TESTE ==="

# 1. Status de containers
echo "Container Status:"
docker compose ps

# 2. Health endpoints
echo -e "\n1. Health Checks:"
curl -s http://localhost:8081/bff/health | jq .
curl -s http://localhost:8080/actuator/health | jq .
curl -s http://localhost:8082/actuator/health | jq .

# 3. Endpoints disponíveis
echo -e "\n2. BFF Endpoints Disponíveis:"
curl -s http://localhost:8081/actuator/mappings | jq '.contexts.application.mappings.servletHandlerMappings[] | select(.handler | contains("Bff"))' | head -20

# 4. Autenticação Manager
echo -e "\n3. Autenticação Manager:"
curl -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq .

# 5. Autenticação Authentik
echo -e "\n4. Autenticação Authentik:"
curl -s http://localhost:9000/api/system/status | jq .

echo -e "\n=== FIM DO DIAGNÓSTICO ==="
```

---

## 📝 Plano de Implementação

### **Fase 1: Investigação (Este Sprint)**
- [ ] Executar Ação 1 (validar endpoints BFF)
- [ ] Executar Ação 2 (determinar autenticação BFF)
- [ ] Documentar findings em `FINDINGS-TESTES.md`

### **Fase 2: Correção Rápida (Próximo Sprint)**
- [ ] Ação 4: Corrigir RabbitMQ healthcheck
- [ ] Atualizar `teste-integrado-service-portal.sh` v1
- [ ] Testar script v1 atualizado

### **Fase 3: Refatoração Completa (Futuro)**
- [ ] Migrar para script v2 (`teste-integrado-service-portal-v2.sh`)
- [ ] Implementar autenticação conforme Findings
- [ ] Adicionar retry logic e melhor error handling

---

## 📋 Checklist de Validação

Antes de considerar os testes "corretos", validar:

- [ ] Todos os endpoints esperados estão mapeados em `/actuator/mappings`
- [ ] BFF responde com 200 (se público) ou 401 (se requer auth)
- [ ] Autenticação funciona (Manager ou Authentik)
- [ ] Workflows podem ser criados via POST /manager/flows
- [ ] Workflows aparecem em GET /manager/flows
- [ ] Workflows podem ser executados via Orchestrator
- [ ] Negative scenarios retornam 400/404 (não 401)
- [ ] RabbitMQ health endpoint retorna 200
- [ ] Taxa de sucesso dos testes ≥ 80%

---

## 🚀 Scripts Fornecidos

### Script v1 (Original Melhorado)
- **Arquivo**: `teste-integrado-service-portal.sh`
- **Status**: Funcionando com falhas conhecidas
- **Próximas etapas**: Aplicar Ação 4

### Script v2 (Com Autenticação)
- **Arquivo**: `teste-integrado-service-portal-v2.sh`
- **Status**: ✅ Pronto para uso após Findings
- **Features**:
  - Autenticação Manager e Authentik
  - Melhor error handling com `jq`
  - Logging detalhado (DEBUG)
  - Suporte a fallback de endpoints

---

## 📞 Próximas Etapas

1. **Hoje**: Executar Ações 1-2 para investigar endpoints
2. **Amanhã**: Documenta findings e atualizações necessárias
3. **Próxima semana**: Implementar correções e testar

---
