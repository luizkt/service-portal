# AGENTS.md — service-portal-admin

Guia de contexto para agentes de IA. Leia este arquivo antes de abrir qualquer código. Ele cobre o componente inteiro: não é preciso varrer o repositório.

<!-- index:meta
repo: service-portal-admin
tipo: spring-boot-admin-server
fonte-de-verdade: build.gradle.kts, src/main/resources/application.yml, src/main/java
atualizado-em: 2026-11-07
-->

## Resumo

Servidor Spring Boot Admin (SBA) do Service Portal. Painel de monitoramento onde BFF, Manager e Orchestrator se registram como clientes. Não tem lógica de negócio, banco de dados nem endpoints próprios além do que o SBA fornece.

<!-- gen:size -->Tamanho: 2 arquivos .java em `src/main`, 0 em `src/test`.<!-- /gen:size -->

## Stack

| Item | Valor |
|---|---|
| Linguagem | Java 21 |
| Framework | Spring Boot 3.4.5 + `spring-boot-admin-starter-server` 3.4.0 |
| Build | Gradle Kotlin DSL; jar final `service-portal-admin.jar` |
| Formatação | Spotless (google-java-format AOSP + header de `../license-header.txt`) |
| Porta | `SERVER_PORT` (padrão 8085 local, 8080 no container; host 8085 via `SBA_PORT`) |

## Mapa de arquivos (todos os pontos de mudança)

| Arquivo | Papel | Mexer quando |
|---|---|---|
| `src/main/java/com/serviceportal/admin/SpringBootAdminApplication.java` | Entry point, `@EnableAdminServer` | Quase nunca |
| `src/main/java/com/serviceportal/admin/config/SecurityConfig.java` | `SecurityFilterChain`: form login, basic auth, CSRF, rotas públicas | Mudar auth, rotas públicas ou CSRF |
| `src/main/resources/application.yml` | Porta, usuário/senha, título da UI, exposição do actuator | Mudar config, título, endpoints expostos |
| `build.gradle.kts` | Dependências, versão do SBA (`sbaVersion`), Spotless | Atualizar versões ou libs |
| `Dockerfile` | Build multi-stage (gradle 8.10 → temurin 21 jre), healthcheck via curl | Mudar imagem ou runtime |

## Pontos-chave por tipo de mudança

| Quero... | Onde |
|---|---|
| Trocar credenciais | env `SBA_USERNAME` / `SBA_PASSWORD` (`application.yml`, `Dockerfile`, compose) |
| Liberar uma rota sem login | `SecurityConfig.securityFilterChain` → bloco `authorizeHttpRequests` |
| Aceitar registro de clientes sem CSRF | `SecurityConfig` → `csrf.ignoringRequestMatchers` (hoje: `/instances`, `/instances/**`, `/actuator/**`) |
| Mudar título da UI | `application.yml` → `spring.boot.admin.ui.title` |
| Expor mais endpoints do actuator | `application.yml` → `management.endpoints.web.exposure.include` (hoje `health,info`) |
| Autenticar via Authentik/OIDC | `SecurityConfig` + nova dependência `oauth2-client` em `build.gradle.kts` |
| Atualizar o SBA | `build.gradle.kts` → `extra["sbaVersion"]` |

## Comportamento de segurança (atual)

- Rotas públicas: `/assets/**`, `/actuator/health`, `/actuator/info`, `/login`. Todo o resto exige autenticação.
- Todas as rotas respeitam `adminServer.getContextPath()` (prefixo `ctx`).
- Clientes registram em `POST /instances` com basic auth. CSRF fica desligado só para `/instances*` e `/actuator/**`.
- Após login, redireciona para o parâmetro `redirectTo` ou `ctx + "/"`.

## Integrações com o resto do monorepo

| Componente | Relação | Onde está a config do lado dele |
|---|---|---|
| BFF, Manager, Orchestrator | Clientes SBA, registram aqui | `spring.boot.admin.client.url` em cada `application*.yml` (`SPRING_BOOT_ADMIN_URL`, padrão `http://spring-boot-admin:8080` no docker) |
| `docker-compose-service-portal.yml` | Serviço `spring-boot-admin`, container `portal-sba` | seção `spring-boot-admin` (~linha 640) |
| Prometheus / Grafana | Sem relação direta com o SBA | `prometheus/`, `grafana/` |

## Comandos

```bash
./gradlew bootRun          # sobe em :8085
./gradlew spotlessApply    # formata (obrigatório antes de commit)
./gradlew bootJar -x test  # gera build/libs/service-portal-admin.jar
```

## Armadilhas

- Alterar `SecurityConfig` sem o `ctx` quebra a UI quando há `spring.boot.admin.context-path`.
- O SBA server roda em modo servlet. Remover `spring-boot-starter-web` causa `ClassNotFoundException` (commit `dcfc3fc`).
- Trocar a senha só no admin faz os clientes falharem no registro: atualize `SBA_USERNAME`/`SBA_PASSWORD` em todos os componentes.
- Todo arquivo `.java` precisa do header de licença, senão o Spotless falha.
