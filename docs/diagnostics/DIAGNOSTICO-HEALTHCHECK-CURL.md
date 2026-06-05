# Diagnóstico: Causa Raiz dos Healthchecks Falhando — Falta de curl

**Data**: 2026-05-16  
**Status**: 🔧 INVESTIGADO E CORRIGIDO  
**Causa Raiz Identificada**: Imagens Alpine não incluem `curl`

---

## 🎯 Problema Identificado

Todos os containers (Manager, Orchestrator, BFF) estavam marcados como **"unhealthy"** apesar de:
- ✅ Aplicações rodando normalmente
- ✅ Endpoints respondendo HTTP 200 (testados de fora do container)
- ✅ Spring Boot Actuator funcionando

### Por que continuavam unhealthy?

O `docker-compose-service-portal.yml` define healthchecks que executam:

```bash
# Manager:
curl -sf http://localhost:${MANAGER_INTERNAL_PORT:-8082}/actuator/health || exit 1

# Orchestrator:
curl -sf http://localhost:${ORCHESTRATOR_INTERNAL_PORT:-8080}/actuator/health || exit 1

# BFF:
curl -sf http://localhost:${BFF_INTERNAL_PORT:-8081}/bff/health || exit 1
```

**Problema**: Os Dockerfiles usam `eclipse-temurin:21-jre-alpine`, uma imagem **extremamente minimalista** que não inclui `curl`.

---

## 🔍 Investigação e Confirmação

### Teste dentro do container (falha esperada):

```bash
$ docker exec portal-manager curl -sf http://localhost:8082/actuator/health
OCI runtime exec failed: exec failed: unable to start container process: 
exec: "curl": executable file not found in $PATH: unknown
```

**Exit code 127** → Comando não encontrado
... (truncado para brevidade, mantendo o conteúdo original)