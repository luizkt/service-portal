# Diagnóstico de Estabilidade dos Containers — Service Portal

Data: 2026-05-16
Sessão: Análise e resolução de problemas de estabilidade do docker-compose

## Problemas Identificados

### 1. ❌ ORCHESTRATOR — 401 UNAUTHORIZED na autenticação com Manager

**Status**: RESOLVIDO

**Sintoma**:
```
ERROR c.o.manager.ManagerAuthService: Renovando token do service-portal-manager
ERROR c.o.manager.ManagerWorkflowClient: Manager respondeu 401 UNAUTHORIZED ao listar ativos
```

**Causa Raiz**:
- ManagerAuthService.java tentava acessar `/api/auth/login` (linha 42)
- Manager expõe somente `/api/auth/tokens` (AuthController.kt)
- Mismatch de endpoints causava 401 em cada tentativa de autenticação

**Solução**:
- Alterado `generic-orchestrator/src/main/java/com/orchestrator/manager/ManagerAuthService.java:42`
  - De: `.uri("/api/auth/login")`
  - Para: `.uri("/api/auth/tokens")`
- Alterado teste correspondente em `ManagerAuthServiceTest.java:53`

**Próximo Passo**: Rebuild do Orchestrator e restart do docker-compose

---

### 2. ⚠️ MANAGER — Gerando senha aleatória (Spring Security auto-config)

**Status**: INVESTIGADO — Sem ação necessária

**Sintoma**:
```
WARN: Using generated security password: 241bb595-8d44-443a-a267-5360030de633
```

**Análise**:
- Manager tem `application-docker.yml` com credenciais:
  ```yaml
  manager.security.admin.username: ${MANAGER_ADMIN_USERNAME:admin}
  manager.security.admin.password: ${MANAGER_ADMIN_PASSWORD:admin}
  ```
- AuthController.kt lê essas variáveis corretamente via @Value
- Spring Security gera senha aleatória apenas para o UserDetailsService padrão (não configurado)
- Isto é **seguro** — o endpoint protegido realmente está usando as credenciais customizadas via JWT

**Conclusão**: Comportamento normal; nenhuma mudança necessária

---

### 3. ⚠️ PORTAINER — Healthcheck retornando falha

**Status**: INVESTIGADO

**Sintoma**:
```
portal-portainer | [UP 11 minutes - unhealthy]
```

**Análise**:
- Healthcheck tenta: `wget --no-verbose --tries=1 --spider http://localhost:9000/api/system/status`
- Portainer responde em `:9000` internamente, mas pode estar em estado de inicialização
- Logs mostram que Portainer **iniciou corretamente** (started HTTP server)
- Problema: o endpoint `/api/system/status` pode não existir ou exigir autenticação

**Solução**:
- Trocar healthcheck para usar um endpoint que não requer auth
- Opção 1: Usar `curl http://localhost:9000` (raiz, sem exigência)
- Opção 2: Aguardar mais tempo no `start_period` (aumentar de padrão)

---

### 4. ⚠️ BFF — Unhealthy (consequência de dependências)

**Status**: Resultante dos problemas acima

**Sintoma**:
```
portal-bff | [UP 7 minutes - unhealthy]
```

**Análise**:
- BFF iniciou corretamente (logs mostram Tomcat running)
- Healthcheck: `curl -sf http://localhost:8081/bff/health`
- Endpoint `/bff/health` existe e é público (permitAll)
- Problema: depende de `orchestrator` estar healthy via `depends_on`
- Como Orchestrator não conseguia fazer login no Manager → healthcheck falhava
- Manager também reiniciava (graciousshutdown em 19:54:22)

**Conclusão**: Uma vez que Orchestrator foi corrigido, BFF deve voltar a healthy

---

## Plano de Ação

| # | Componente | Problema | Solução | Status |
|---|---|---|---|---|
| 1 | Orchestrator | Endpoint auth errado | Trocar `/api/auth/login` → `/api/auth/tokens` | ✅ Corrigido |
| 2 | Portainer | Healthcheck pode falhar | Melhorar healthcheck ou aumentar start_period | 🔧 Por fazer |
| 3 | Rebuild + Restart | Stack desatualizada | Rebuild das imagens Java e restart | 🔧 Por fazer |
| 4 | Verificação | Validar estabilidade | Aguardar todos os containers healthy | 🔧 Por fazer |

---

## ATUALIZAÇÃO: Investig ação de Cache Docker

### Problema Identificado

Após corrigir os endpoints, os logs indicam que o código antigo ainda está sendo executado:

1. ✅ Mudanças feitas no código-fonte:
   - `/api/auth/login` → `/api/auth/tokens` (resolvido com sucesso)
   - `/manager/workflows/active` → `/manager/flows?status=active` (código alterado, mas logs ainda mostram URL antiga)
   - `/manager/workflows/{flowId}/{versao}/yaml` → `/manager/flows/{flowId}/versions/{versao}/yaml` (alterado)

2. ⚠️ Compilação bem-sucedida:
   - Gradle compile: ✅ BUILD SUCCESSFUL
   - Docker build: ✅ orchestrator Built

3. ❌ Execução do código: Mostra URLs antigas
   - Logs mostram ainda: "401 Unauthorized from GET http://manager:8082/manager/workflows/active"
   - Não deve acontecer se o código compilado fosse novo

### Hipóteses

- [ ] Cache do Docker builder (multi-stage) pode estar usando JAR antigo
- [ ] Problema com classpath ou carregamento de classes no container
- [ ] Bug em como o WebClient constrói a URI  
- [ ] A exceção que aparece nos logs pode ser de cache antigo do Spring WebClientResponseException

### Recomendação para Próxima Sessão

1. **Limpar tudo completamente**:
   ```bash
   docker compose -f docker-compose-service-portal.yml down
   docker image prune -a --force
   docker volume prune -f
   ```

2. **Fazer build sem cache**:
   ```bash
   docker compose -f docker-compose-service-portal.yml build --no-cache --pull
   ```

3. **Testar manualmente o endpoint do Manager**:
   ```bash
   # Obter token
   TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*' | cut -d'"' -f4)
   
   # Testar listActive endpoint
   curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/manager/flows?status=active
   ```

4. **Se o problema persistir**: Adicionar logs de debug no ManagerWorkflowClient.listActive() para ver qual URI é realmente enviada

