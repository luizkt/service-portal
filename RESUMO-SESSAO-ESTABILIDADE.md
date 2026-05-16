# Resumo da Sessão — Diagnóstico de Estabilidade dos Containers

**Data**: 2026-05-16  
**Status**: 🔧 EM PROGRESSO  
**Commit**: ad79a23

---

## 🎯 Objetivo da Sessão

Analisar e resolver problemas de estabilidade dos containers da Service Portal. Containers estavam em estado `unhealthy`: BFF, Manager, Orchestrator, Portainer.

---

## ✅ Progresso

### 1. Análise de Logs (CONCLUÍDO)

Identificados 4 problemas principais:

| Componente | Problema | Root Cause | Status |
|---|---|---|---|
| **Orchestrator** | 401 UNAUTHORIZED ao fazer login no Manager | Endpoint errado: `/api/auth/login` vs `/api/auth/tokens` | ✅ Corrigido |
| **Orchestrator** | 401 UNAUTHORIZED ao buscar workflows ativos | Endpoint errado: `/manager/workflows/active` vs `/manager/flows?status=active` | 🔧 Corrigido código, build em investigação |
| **Orchestrator** | Endpoint YAML com caminho errado | `/manager/workflows/{id}/{v}/yaml` vs `/manager/flows/{id}/versions/{v}/yaml` | ✅ Corrigido |
| **Manager** | Gerando senha aleatória do Spring Security | Comportamento normal — não é problema | ✅ Validado |
| **Portainer** | Healthcheck retornando erro | Endpoint `/api/system/status` pode não exigir autenticação ou estar slow | 🔧 Pending |

---

## 🔧 Mudanças Realizadas

### Arquivo: `generic-orchestrator/src/main/java/com/orchestrator/manager/ManagerAuthService.java`

**Antes:**
```java
.uri("/api/auth/login")
```

**Depois:**
```java
.uri("/api/auth/tokens")
```

**Resultado:** ✅ Autenticação funciona — Token obtido com sucesso

---

### Arquivo: `generic-orchestrator/src/main/java/com/orchestrator/manager/ManagerWorkflowClient.java`

**Antes:**
```java
.uri("/manager/workflows/active")
.uri("/manager/workflows/{flowId}/{versao}/yaml", flowId, versao)
```

**Depois:**
```java
.uri("/manager/flows?status=active")
.uri("/manager/flows/{flowId}/versions/{versao}/yaml", flowId, versao)
```

**Status:** ✅ Código-fonte alterado e commitado, mas Docker build necessita investigação

---

### Testes Atualizados

- `ManagerAuthServiceTest.java:53` — Mudado endpoint de login
- `ManagerWorkflowClientTest.java:67` — Mudado endpoint de workflows ativos
- `ManagerWorkflowClientTest.java:95` — Mudado endpoint de YAML

---

## 🔍 Investigação em Andamento

### Problema: Docker Build Cache

Após múltiplos rebuilds, os logs do Orchestrator ainda mostram URLs antigas:

```
GET http://manager:8082/manager/workflows/active
```

Mas o código-fonte foi alterado para:

```
GET http://manager:8082/manager/flows?status=active
```

**Tentativas realizadas:**
1. ✅ `gradle clean bootJar` — Sucesso
2. ✅ `docker compose build --no-cache` — Sucesso  
3. ✅ `docker image rm service-portal-orchestrator:latest` — Sucesso
4. ❌ Logs ainda mostram URL antiga

**Próxima abordagem:**
- Limpar completamente o Docker builder cache
- Considerar construção manual de Dockerfile sem cache
- Adicionar logs de debug na classe para confirmar execução do código novo

---

## 📋 Próximos Passos (Para Próxima Sessão)

### 1. **Resolver Docker Build Cache Issue**
   ```bash
   docker builder prune -a --force
   docker compose -f docker-compose-service-portal.yml down
   docker compose -f docker-compose-service-portal.yml build --no-cache --pull orchestrator
   docker compose -f docker-compose-service-portal.yml up -d
   ```

### 2. **Se problema persistir:**
   - Adicionar logs explícitos antes de `.uri()`:
     ```java
     log.info("Calling /manager/flows?status=active");
     ```
   - Verificar se classe está sendo carregada corretamente
   - Considerar rebuild manual com `DOCKER_BUILDKIT=0`

### 3. **Testar endpoints manualmente:**
   ```bash
   # Token Manager
   TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*' | cut -d'"' -f4)
   
   # Endpoint ativos
   curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/manager/flows?status=active
   ```

### 4. **Resolver Portainer healthcheck:**
   - Investigar se `/api/system/status` existe
   - Alternativa: usar endpoint `/` (raiz) no healthcheck

### 5. **Testar estabilidade:**
   - Aguardar todos containers em `healthy`
   - Executar script de testes integrados
   - Validar logs sem erros

---

## 📁 Arquivos Gerados

- `DIAGNOSTICO-ESTABILIDADE.md` — Análise detalhada de todos os problemas
- `RESUMO-SESSAO-ESTABILIDADE.md` — Este arquivo

---

## 🚀 Comando Rápido para Próxima Sessão

```bash
docker builder prune -a --force
docker compose -f docker-compose-service-portal.yml down
docker compose -f docker-compose-service-portal.yml build --no-cache --pull
docker compose -f docker-compose-service-portal.yml up -d
docker compose -f docker-compose-service-portal.yml ps
```

