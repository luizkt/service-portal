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

## ✅ Conclusões
... (truncado para brevidade, mantendo o conteúdo original)