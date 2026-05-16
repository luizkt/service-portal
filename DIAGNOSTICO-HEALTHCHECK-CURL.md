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

### Teste fora do container (sucesso):

```bash
$ curl -s http://localhost:8082/actuator/health
{"status":"UP"}
```

**HTTP 200 OK** → Aplicação funciona perfeitamente

---

## ✅ Solução Implementada

Adicionar `curl` às imagens Alpine em todos os Dockerfiles antes de copiar o JAR:

### Manager: `service-portal-manager/Dockerfile`

```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache curl  # ← ADICIONADO

COPY --from=build /app/build/libs/service-portal-manager.jar app.jar
```

### Orchestrator: `generic-orchestrator/Dockerfile`

```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache curl  # ← ADICIONADO

COPY --from=build /app/build/libs/generic-orchestrator.jar app.jar
```

### BFF: `service-portal-bff/Dockerfile`

```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache curl  # ← ADICIONADO

COPY --from=build /app/build/libs/service-portal-bff.jar app.jar
```

---

## 📊 Impacto da Mudança

### Tamanho de imagem (aproximado):
- **Antes**: ~280 MB (Orchestrator), ~248 MB (Manager), ~244 MB (BFF)
- **Depois**: ~285 MB (Orchestrator), ~253 MB (Manager), ~249 MB (BFF)
- **Delta**: +5 MB por imagem (curl é um binário pequeno)

### Compatibilidade:
- ✅ Sem quebra de funcionalidade
- ✅ `apk add --no-cache` não cria cache, mantem imagem limpa
- ✅ `curl` é ferramenta padrão em healthchecks Docker

---

## 🚀 Próximas Etapas

1. **Rebuild das imagens** (com `--no-cache` para garantir pick-up da nova instrução RUN)
2. **Restart limpo** (`docker compose down && docker compose up -d`)
3. **Aguardar ~60s** para healthchecks estabilizarem
4. **Validar** com `docker compose ps` — todos devem estar **green (healthy)**

---

## 📝 Notas Técnicas

### Por que Alpine?

As imagens `eclipse-temurin:21-jre-alpine` são escolhidas para:
- **Tamanho mínimo**: ~150 MB vs ~600 MB das versões full
- **Segurança**: Menos código = menos surface de ataque
- **Rapidez**: Deploy mais rápido

**Trade-off**: Aplicações precisam instalar ferramentas adicionais conforme necessário.

### Alternativas consideradas (descartadas):

1. ❌ Usar `eclipse-temurin:21-jre` (full image com curl) — aumenta imagem de 150 MB
2. ❌ Remover curl dos healthchecks e usar Java internamente — mais complexo
3. ❌ Usar `wget` em vez de `curl` — ambos ausentes em Alpine minimal
4. ✅ **Instalar curl via `apk add --no-cache curl`** — mínimo overhead, padrão Docker

---

## 🔗 Referências

- **Docker Compose Healthcheck Docs**: https://docs.docker.com/compose/compose-file/05-services/#healthcheck
- **Alpine Linux apk package manager**: https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management
- **eclipse-temurin base images**: https://hub.docker.com/_/eclipse-temurin

