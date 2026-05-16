# Próximas Etapas - Testes Integrados

**Data**: 2026-05-16  
**Status**: ✅ ANÁLISE COMPLETA  
**Commit**: aadc2b2

---

## 📋 Resumo do Que Foi Feito

### ✅ Análise do Log
- [x] Leitura completa do arquivo `teste-integrado-20260516-204125.log`
- [x] Identificação de 5 grupos de problemas
- [x] Análise de causas raiz para cada grupo

### ✅ Documentação Criada
- [x] **DIAGNOSTICO-TESTES-INTEGRADOS.md** — Análise detalhada dos problemas
- [x] **RECOMENDACOES-TESTES-INTEGRADOS.md** — Plano de ação em 5 fases
- [x] **TESTES-README.md** — Documentação de uso e troubleshooting
- [x] **teste-integrado-service-portal-v2.sh** — Script v2 com autenticação

### ✅ Commit Realizado
- [x] aadc2b2 — "Diagnóstico e manutenção de testes integrados"

---

## 🎯 Próximas Etapas Recomendadas

### **Fase 1: Investigação Preliminar** (Esta Sessão)

#### Ação 1A: Validar Endpoints BFF
```bash
# Executar comandos de validação
curl -s http://localhost:8081/actuator/mappings | \
  jq '.contexts.application.mappings.servletHandlerMappings[] | {handler: .handler}' | \
  grep -i "bff\|menu\|feature" | head -20

# Testar acesso direto
curl -v http://localhost:8081/bff/menu
curl -v http://localhost:8081/bff/features/flow-manager/ui-schema

# Verificar logs
docker compose logs bff | grep -i "menu\|feature" | tail -20
```

**Resultado Esperado**: Identificar se endpoints existem ou não

**Documentar em**: Criar arquivo `FINDINGS-ENDPOINTS-BFF.md`

---

#### Ação 1B: Determinar Autenticação BFF
```bash
# Testar sem autenticação
curl -v http://localhost:8081/bff/flows

# Testar com diferentes tipos de token
MANAGER_TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.token')

curl -H "Authorization: Bearer $MANAGER_TOKEN" http://localhost:8081/bff/flows

# Verificar logs para dicas
docker compose logs bff | grep -i "401\|unauthorized\|token"
```

**Resultado Esperado**: Identificar qual tipo de autenticação é necessário

**Documentar em**: `FINDINGS-ENDPOINTS-BFF.md`

---

#### Ação 1C: Validar Content-Type de Workflows
```bash
# Testar criação com application/json
curl -X POST http://localhost:8082/manager/flows \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -d '{"flowId":"test1","version":"1.0.0"}'

# Testar criação com application/yaml
curl -X POST http://localhost:8082/manager/flows \
  -H "Content-Type: application/yaml" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -d 'flowId: test2
version: 1.0.0'

# Verificar qual endpoint está correto
curl -s http://localhost:8082/actuator/mappings | \
  jq '.contexts.application.mappings.servletHandlerMappings[] | select(.handler | contains("Flow"))' | head -10
```

**Resultado Esperado**: Identificar content-type esperado e endpoint correto

---

### **Fase 2: Implementação Rápida** (Próximas Horas)

#### Ação 2A: Corrigir RabbitMQ Healthcheck
**Arquivo**: `teste-integrado-service-portal.sh`
**Linha**: 184
**Mudança**:
```bash
# ANTES:
curl -sf http://guest:guest@localhost:15672/api/health > /dev/null 2>&1

# DEPOIS:
curl -sf http://guest:guest@localhost:15672/api/aliveness-test/%2F > /dev/null 2>&1
```

**Complexidade**: ⚡ Trivial (1 linha)
**Teste**: 
```bash
curl http://guest:guest@localhost:15672/api/aliveness-test/%2F
# Expected: 200 OK
```

---

#### Ação 2B: Atualizar Endpoints nos Scripts
**Baseado em**: Findings de Ação 1B-1C

**Se BFF requer Manager token**:
- Adicionar lógica de autenticação Manager no script v1
- Incluir `Authorization: Bearer $MANAGER_TOKEN` em requests

**Se BFF requer Authentik token**:
- Deixar como está no script v2
- Testar script v2 com Authentik

**Se BFF é público**:
- Remover lógica de autenticação
- Simplificar script v1

---

### **Fase 3: Testes e Validação** (Próximo Sprint)

#### Ação 3A: Executar Script Melhorado
```bash
chmod +x teste-integrado-service-portal-v2.sh
./teste-integrado-service-portal-v2.sh
```

**Critérios de Sucesso**:
- Taxa de sucesso ≥ 80%
- Nenhum 401 Unauthorized (exceto cenários negativos planejados)
- RabbitMQ health check passa
- Workflows criados e listados com sucesso

---

#### Ação 3B: Compará-lo com Script v1
```bash
# Executar v1 (com correções)
./teste-integrado-service-portal.sh

# Comparar resultados
diff teste-integrado-checklist-*.md
```

**Esperado**: v2 deve ter resultados melhores

---

### **Fase 4: Integração com CI/CD** (Futuro)

#### Adicionar testes ao pipeline
**Arquivo**: `.github/workflows/tests.yml` (ou equivalente)

```yaml
- name: Run Integration Tests
  run: ./teste-integrado-service-portal-v2.sh
  
- name: Upload Test Results
  if: always()
  uses: actions/upload-artifact@v2
  with:
    name: test-results
    path: teste-integrado-*.log
```

---

## 📊 Checklist de Execução

### Hoje (2026-05-16)
- [ ] **Ação 1A**: Validar endpoints BFF
- [ ] **Ação 1B**: Determinar autenticação BFF
- [ ] **Ação 1C**: Validar content-type workflows
- [ ] Criar arquivo `FINDINGS-ENDPOINTS-BFF.md` com resultados
- [ ] Commit com findings

### Próximas Horas
- [ ] **Ação 2A**: Corrigir RabbitMQ endpoint (30 min)
- [ ] **Ação 2B**: Atualizar scripts baseado em findings (1-2 horas)
- [ ] Testar scripts manualmente (30 min)
- [ ] Commit com melhorias

### Próxima Semana
- [ ] **Ação 3A**: Executar script melhorado
- [ ] **Ação 3B**: Comparar com script v1
- [ ] Validar taxa de sucesso ≥ 80%
- [ ] Documentar lições aprendidas

### Futuro (Próximo Sprint)
- [ ] **Ação 4A**: Adicionar ao CI/CD
- [ ] **Ação 4B**: Monitorar testes em pipeline
- [ ] Melhorias contínuas baseado em dados do pipeline

---

## 📁 Estrutura de Arquivos

### Criados Nesta Sessão
```
✅ DIAGNOSTICO-TESTES-INTEGRADOS.md
✅ RECOMENDACOES-TESTES-INTEGRADOS.md
✅ TESTES-README.md
✅ teste-integrado-service-portal-v2.sh
✅ PROXIMAS-ETAPAS-TESTES.md (este arquivo)
```

### A Criar (Baseado em Findings)
```
⏳ FINDINGS-ENDPOINTS-BFF.md (Ação 1)
```

### A Atualizar
```
⏳ teste-integrado-service-portal.sh (Ação 2A)
⏳ PLAN.md (registrar progresso)
```

---

## 🔗 Referências Rápidas

### Documentos de Diagnóstico
- [DIAGNOSTICO-TESTES-INTEGRADOS.md](DIAGNOSTICO-TESTES-INTEGRADOS.md) — Análise de problemas
- [RECOMENDACOES-TESTES-INTEGRADOS.md](RECOMENDACOES-TESTES-INTEGRADOS.md) — Plano de ação
- [TESTES-README.md](TESTES-README.md) — Como usar

### Scripts de Teste
- `teste-integrado-service-portal.sh` — Versão original (melhorado)
- `teste-integrado-service-portal-v2.sh` — Versão com autenticação

### Logs Atuais
- `teste-integrado-20260516-204125.log` — Log do último teste
- `teste-integrado-checklist-20260516-204125.md` — Checklist do último teste

---

## 💡 Dicas para Execução

### Para Executar Ação 1 Rapidamente
```bash
# Salvar este script como "validate-endpoints.sh"
#!/bin/bash
echo "=== VALIDAÇÃO DE ENDPOINTS ==="

echo -e "\n1. Endpoints BFF Disponíveis:"
curl -s http://localhost:8081/actuator/mappings | jq '.contexts.application.mappings.servletHandlerMappings[] | select(.handler | contains("Bff"))' | head -20

echo -e "\n2. Teste /bff/menu:"
curl -v http://localhost:8081/bff/menu 2>&1 | grep "< HTTP"

echo -e "\n3. Teste /bff/features:"
curl -v http://localhost:8081/bff/features 2>&1 | grep "< HTTP"

echo -e "\n4. Teste com Token Manager:"
TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.token')
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8081/bff/flows 2>&1 | grep "< HTTP"

echo -e "\n=== FIM DA VALIDAÇÃO ==="
```

### Para Manter Registro de Progresso
```bash
# Adicionar ao PLAN.md ou criar novo arquivo de status
# Atualizar após cada ação completada
```

---

## ❓ FAQ

**P: Posso executar as ações em ordem diferente?**  
R: Ações 1B e 1C dependerão de resultados de 1A. Comece por 1A.

**P: E se um endpoint não existir?**  
R: Isso é aceitável - será documentado e removido dos testes.

**P: Quanto tempo vai levar?**  
R: Fase 1 (investigação): ~1 hora. Fase 2 (implementação): ~1-2 horas.

**P: Como saber se os testes estão "corretos"?**  
R: Taxa de sucesso ≥ 80% é o indicador principal.

---

## 📞 Próximo Passos

1. ✅ Ler este documento
2. ⏭️ Executar Ação 1A (validar endpoints)
3. ⏭️ Documentar findings em `FINDINGS-ENDPOINTS-BFF.md`
4. ⏭️ Retornar com resultados

---
