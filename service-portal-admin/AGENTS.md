# AGENTS.md — service-portal-admin

Guia de contexto para agentes de IA. Leia este arquivo antes de abrir qualquer código. Ele cobre o componente inteiro: não é preciso varrer o repositório.

<!-- index:meta
repo: service-portal-admin
tipo: spring-boot-admin-server
fonte-de-verdade: build.gradle.kts, src/main/resources/application.yml, src/main/java
atualizado-em: 2026-11-07
-->

## Resumo

Servidor Spring Boot Admin (SBA) do Service Portal. Painel de monitoramento onde BFF, Manager e Orchestrator se registram como clientes. Não tem lógica de negócio, banco de dados nem endpoints próprios além do que o SBA fornece. Tem testes de segurança (`@SpringBootTest` + MockMvc) que fixam rotas públicas, CSRF e registro de clientes.

<!-- gen:size -->Tamanho: 3 arquivos .java em `src/main`, 2 em `src/test`.<!-- /gen:size -->

## Stack

| Item | Valor |
|---|---|
| Linguagem | Java 21 |
| Framework | Spring Boot 3.5.16 + `spring-boot-admin-starter-server` 3.5.11 |
| Build | Gradle Kotlin DSL; jar final `service-portal-admin.jar` |
| Testes | JUnit 5, `spring-boot-starter-test`, `spring-security-test` (MockMvc); `./gradlew test` |
| Formatação | Spotless (google-java-format AOSP + header de `../license-header.txt`) |
| Porta | `SERVER_PORT` (padrão 8085 local, 8080 no container; host 8085 via `SBA_PORT`) |

## Mapa de arquivos (todos os pontos de mudança)

| Arquivo | Papel | Mexer quando |
|---|---|---|
| `src/main/java/com/serviceportal/admin/SpringBootAdminApplication.java` | Entry point, `@EnableAdminServer` | Quase nunca |
| `src/main/java/com/serviceportal/admin/config/SecurityConfig.java` | `SecurityFilterChain`: form login, basic auth, CSRF, rotas públicas | Mudar auth, rotas públicas ou CSRF |
| `src/main/java/com/serviceportal/admin/config/SecurityDefaultsGuard.java` | Detecta `admin`/`admin`: WARN; falha em `prod` ou `sba.security.strict=true` | Mudar a política de defaults |
| `src/test/java/com/serviceportal/admin/` | `AdminSecurityTest` (rotas, CSRF, registro) e `SecurityDefaultsGuardTest` | Toda mudança de segurança |
| `src/main/resources/application.yml` | Porta, usuário/senha, título da UI, exposição do actuator | Mudar config, título, endpoints expostos |
| `build.gradle.kts` | Dependências, versão do SBA (`sbaVersion`), Spotless | Atualizar versões ou libs |
| `Dockerfile` | Build multi-stage (gradle 8.10 → temurin 21 jre), `HEALTHCHECK` via curl em `/actuator/health`, usuário não-root `app` | Mudar imagem ou runtime |

## Pontos-chave por tipo de mudança

| Quero... | Onde |
|---|---|
| Trocar credenciais | env `SBA_USERNAME` / `SBA_PASSWORD` (`application.yml`, compose; a imagem não tem default) |
| Exigir credenciais não-default | env `SECURITY_STRICT=true` ou profile `prod`: o startup falha se continuar `admin`/`admin` |
| Liberar uma rota sem login | `SecurityConfig.securityFilterChain` → bloco `authorizeHttpRequests` |
| Aceitar registro de clientes sem CSRF | `SecurityConfig` → `csrf.ignoringRequestMatchers` (hoje só `POST /instances` e `DELETE /instances/*`, por método) |
| Mudar título da UI | `application.yml` → `spring.boot.admin.ui.title` |
| Expor mais endpoints do actuator | `application.yml` → `management.endpoints.web.exposure.include` (hoje `health,info`) |
| Autenticar via Authentik/OIDC | `SecurityConfig` + nova dependência `oauth2-client` em `build.gradle.kts` |
| Atualizar o SBA | `build.gradle.kts` → `extra["sbaVersion"]` |

## Comportamento de segurança (atual)

- Rotas públicas: `/assets/**`, `/actuator/health`, `/actuator/info`, `/login`. Todo o resto exige autenticação.
- Todas as rotas respeitam `adminServer.getContextPath()` (prefixo `ctx`).
- Clientes registram em `POST /instances` com basic auth. CSRF fica desligado só para `POST /instances` e `DELETE /instances/*`; qualquer outro POST/DELETE (inclusive `/logout` e `/actuator/**`) exige token CSRF. O SBA responde 200 (não 201) ao registro.
- `health` mostra detalhes só `when-authorized` (anônimo vê apenas o status).
- `SecurityDefaultsGuard`: com `SBA_USERNAME`/`SBA_PASSWORD` em `admin`/`admin` loga WARN com o nome da variável (nunca o valor); com profile `prod` ou `SECURITY_STRICT=true` o startup falha (`IllegalStateException`). Dev, testes e compose seguem funcionando com o default.
- Após login, redireciona para o parâmetro `redirectTo` ou `ctx + "/"`.

## Integrações com o resto do monorepo

| Componente | Relação | Onde está a config do lado dele |
|---|---|---|
| BFF, Manager, Orchestrator | Clientes SBA, registram aqui | `spring.boot.admin.client.url` em cada `application*.yml` (`SPRING_BOOT_ADMIN_URL`, padrão `http://spring-boot-admin:8080` no docker) |
| `docker-compose-service-portal.yml` | Serviço `spring-boot-admin`, container `portal-sba` | seção `spring-boot-admin` (~linha 640) |
| Prometheus / Grafana | O admin expõe `/actuator/prometheus` (público, regra em `config/SecurityConfig`); job `service-portal-admin` em `../prometheus/prometheus.yml` | `prometheus/`, `grafana/` |

## Comandos

```bash
./gradlew bootRun          # sobe em :8085
./gradlew test             # testes de segurança
./gradlew spotlessApply    # formata (obrigatório antes de commit)
./gradlew bootJar -x test  # gera build/libs/service-portal-admin.jar
```

## Armadilhas

- Segredos nunca em `ENV` do Dockerfile: sem `SBA_PASSWORD` a imagem sobe com o default `admin` (WARN); em produção defina `SBA_PASSWORD` e `SECURITY_STRICT=true`.
- Matchers com método (`AntPathRequestMatcher(path, "POST")`) são parte do contrato de registro: mudar o matcher na atualização do Spring Boot exige rodar `AdminSecurityTest`.
- Usuário único compartilhado: a mesma credencial serve à UI e ao registro dos clientes (BFF, Manager, Orchestrator).
- Alterar `SecurityConfig` sem o `ctx` quebra a UI quando há `spring.boot.admin.context-path`.
- O SBA server roda em modo servlet. Remover `spring-boot-starter-web` causa `ClassNotFoundException` (commit `dcfc3fc`).
- Trocar a senha só no admin faz os clientes falharem no registro: atualize `SBA_USERNAME`/`SBA_PASSWORD` em todos os componentes.
- Todo arquivo `.java` precisa do header de licença, senão o Spotless falha.
- A imagem roda como `app` (não root). Arquivos copiados para o runtime precisam de `--chown=app:app`; novos diretórios graváveis também.
- O `HEALTHCHECK` do Dockerfile usa `curl` em `/actuator/health` com `${SERVER_PORT:-8080}` (forma shell, para expandir a variável). Se tirar `health` do `exposure.include` ou a rota da lista pública, a imagem fica `unhealthy`.
- `.dockerignore` exclui diretórios de build, caches e config de agentes e os `*.md`; `src/`, `gradle/`, `gradlew` e `*.kts` precisam continuar no contexto.
- Ordem das camadas do build: arquivos de build (`gradlew`, `gradle/`, `*.kts`) → `gradle dependencies` → `COPY src` → `bootJar`. Mexer em código não refaz o download de dependências.
