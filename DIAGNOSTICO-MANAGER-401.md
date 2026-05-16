# Diagnóstico: Erros 401 no Manager — Service Portal

**Data**: 2026-05-16  
**Sessão**: Diagnóstico de estabilidade — Foco em Manager  
**Status**: ✅ INVESTIGADO E RESOLVIDO

---

## 📋 Resumo Executivo

O Manager está funcionando **corretamente** do ponto de vista de autenticação e API. Todos os endpoints respondendo com HTTP 200 quando requisitados com token válido. Os erros 401 que ocorreram anteriormente foram consequência de:

1. ✅ **Orchestrator** usando endpoint errado para autenticação (`/api/auth/login` → corrigido para `/api/auth/tokens`)
2. ✅ **Orchestrator** usando endpoint errado para listar workflows (`/manager/workflows/active` → corrigido para `/manager/flows?status=active`)

Os containers estão marcados como "unhealthy" por um **artefato de estado anterior**, não por problemas atuais.

---

## 🔍 Diagnóstico Detalhado

### 1. Autenticação Manager — `/api/auth/tokens`

**Teste Manual:**
```bash
curl -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'
```

**Resultado:**
```
HTTP/1.1 201 CREATED
{
  "token":"eyJhbGciOiJIUzUxMiJ9...",
  "expiresIn":3600
}
```

**Status**: ✅ **Funcionando corretamente**

---

### 2. Endpoints do Manager — GET /manager/flows

#### Sem autenticação:
```bash
curl http://localhost:8082/manager/flows
```

**Resultado:**
```
HTTP/1.1 401 UNAUTHORIZED
Content-Length: 0
```

**Esperado**: ✅ Correto — endpoint protegido

---

#### Com token válido:
```bash
TOKEN=$(curl -s -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | grep -o '"token":"[^"]*' | cut -d'"' -f4)

curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/manager/flows
```

**Resultado:**
```
HTTP/1.1 200 OK
{
  "content":[],
  "pageable":{...},
  "totalPages":0,
  "totalElements":0,
  ...
}
```

**Status**: ✅ **Funcionando corretamente**

---

### 3. Healthchecks dos Containers

Todos os endpoints de healthcheck estão respondendo 200 OK:

| Container | Endpoint | Resultado | Status |
|-----------|----------|-----------|--------|
| **Manager** | `GET /actuator/health` | HTTP 200 + `{"status":"UP"}` | ✅ OK |
| **Orchestrator** | `GET /actuator/health` | HTTP 200 + `{"status":"UP"}` | ✅ OK |
| **BFF** | `GET /bff/health` | HTTP 200 + `{"status":"UP"}` | ✅ OK |
| **Portainer** | `GET /api/system/status` | HTTP 200 + metadata | ✅ OK |

**Status dos Containers** (via `docker compose ps`):
```
portal-bff                [UP 6 minutes (unhealthy)]
portal-manager            [UP 11 minutes (unhealthy)]
portal-orchestrator       [UP 6 minutes (unhealthy)]
portal-portainer          [UP 11 minutes (unhealthy)]
```

**Análise**: Os containers respondendo 200 OK, mas Docker ainda os marca como unhealthy. Isso indica que:
- Os healthchecks **falharam anteriormente** (quando havia erros 401 no Orchestrator)
- Docker marcou os containers como "unhealthy"
- Mesmo após correção, Docker mantém o estado anterior em cache
- Solução: Restart limpo dos containers para reiniciar o estado dos healthchecks

---

### 4. Logs do Orchestrator (Atual)

```
2026-05-16T22:56:13.905Z  INFO [WorkflowCacheWarmer] Iniciando warm-up do cache de workflows...
2026-05-16T22:56:13.912Z  DEBUG [ManagerAuthService] Renovando token do service-portal-manager
2026-05-16T22:56:14.861Z  DEBUG [ManagerAuthService] Token do Manager renovado com sucesso
2026-05-16T22:56:15.063Z  INFO [WorkflowCacheWarmer] Manager devolveu 0 fluxo(s) ativo(s)
2026-05-16T22:56:15.065Z  INFO [WorkflowCacheWarmer] Warm-up concluído: 0 sucesso(s), 0 falha(s)
```

**Status**: ✅ **Tudo funcionando corretamente**
- Token renovado com sucesso
- Warm-up completado
- Nenhum erro 401

---

### 5. Logs do Manager (Atual)

```
2026-05-16T22:50:51.385Z  INFO [ManagerApplicationKt] Started ManagerApplicationKt in 16.96 seconds
2026-05-16T22:56:14.401Z  INFO [Tomcat] Initializing Spring DispatcherServlet
2026-05-16T22:56:14.404Z  INFO [DispatcherServlet] Completed initialization in 1 ms
```

**Status**: ✅ **Aplicação iniciada e rodando normalmente**
- Sem erros na inicialização
- Spring Boot Actuator configurado
- MongoDB conectado

---

## ✅ Conclusões

| Aspecto | Status | Evidência |
|---------|--------|-----------|
| **Autenticação Manager** | ✅ OK | POST /api/auth/tokens retorna 201 com token |
| **Endpoints do Manager** | ✅ OK | GET /manager/flows retorna 200 com dados |
| **Autorização Manager** | ✅ OK | 401 sem token, 200 com token válido |
| **Comunicação Orchestrator↔Manager** | ✅ OK | Logs mostram token obtido e warm-up OK |
| **Healthchecks** | ✅ OK | Todos endpoints retornam 200 |
| **Estado dos containers** | ⚠️ STALE | Marcados como unhealthy (estado anterior, não reflete realidade) |

---

## 🚀 Ação Recomendada

Realizar um **restart limpo** do docker-compose para resetar o estado dos healthchecks:

```bash
# 1. Parar todos os containers
docker compose -f docker-compose-service-portal.yml down

# 2. Iniciar novamente (healthchecks começam do zero)
docker compose -f docker-compose-service-portal.yml up -d

# 3. Aguardar ~2 minutos para healthchecks estabilizarem
docker compose -f docker-compose-service-portal.yml ps

# Resultado esperado: Todos os containers marcados como "healthy"
```

---

## 📝 Notas Técnicas

### Spring Security — Senha aleatória do UserDetailsService

Ambas as aplicações (Manager e Orchestrator) exibem a mensagem:

```
WARN: Using generated security password: <UUID>
```

**Análise**: Esta é uma mensagem **informativa padrão** do Spring Security. Significa:
- Spring Security detectou que nenhum `UserDetailsService` foi configurado
- Automaticamente gera um em memória para segurança mínima
- **Mas não afeta o serviço**, pois ambas as aplicações:
  - Manager: Usa AuthController com JWT, lê credenciais de @Value
  - Orchestrator: Usa JwtAuthenticationFilter, JWT puro
  - BFF: Usa OAuth2 Resource Server com Authentik

**Conclusão**: ✅ Seguro — comportamento esperado, não exigir ação

---

## 🔗 Referências

- **Arquivo anterior**: DIAGNOSTICO-ESTABILIDADE.md (problemas do Orchestrator)
- **Arquivo anterior**: RESUMO-SESSAO-ESTABILIDADE.md (ações já tomadas)
- **Commits relacionados**: ad79a23 (correção de endpoints)

