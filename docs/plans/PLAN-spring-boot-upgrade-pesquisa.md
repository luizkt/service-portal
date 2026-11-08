# Pesquisa: upgrade do Spring Boot (anexo do PLAN-spring-boot-upgrade.md)

Relatório bruto da pesquisa de 2026-11-07, com as fontes e os itens não confirmados. O plano é [PLAN-spring-boot-upgrade.md](PLAN-spring-boot-upgrade.md).


Uso de requisições web: 39 de 40. Fontes: endoflife.date, docs.spring.io, repo1.maven.org, springdoc.org, java/maven central, services.gradle.org, 3 páginas wiki do GitHub (Boot 4.0 Migration Guide, 4.1 Release Notes, 3.5 Release Notes). "NÃO CONFIRMADO" = não foi possível validar em fonte oficial dentro do orçamento.

## 0. Estado dos apps (build files lidos)
- Os 4 apps: Boot 3.4.5, dependency-management 1.1.7, Spotless 6.25.0. Mgr: Kotlin 2.0.21, springmockk 4.0.2, mockk 1.13.13 (main; branch deps-update 1.14.12). Orch/BFF/Mgr: springdoc 2.8.8, SBA client, jjwt (orch, mgr), okhttp mockwebserver 4.12.0 (orch, bff), Testcontainers `org.testcontainers:{testcontainers,junit-jupiter,rabbitmq,kafka,localstack}` (orch), spring-kafka/amqp/redis (orch), mongodb (mgr), oauth2-resource-server (bff), webflux em orch e bff, Lombok (orch, bff), starters `web`, `oauth2-resource-server`, `aop` não usado.
- Admin: SBA server, `starter-web`, `security`, `actuator`.

## 1. Versões e datas (ENTREGA 1a)
Fonte: https://endoflife.date/spring-boot (página atualizada em 23/10/2026) e https://repo1.maven.org/maven2/org/springframework/boot/spring-boot/maven-metadata.xml (lastUpdated 2026-11-05).

| Linha | Último patch | Data | Fim suporte OSS | Fim suporte comercial ("EOL") |
|---|---|---|---|---|
| 3.4 | 3.4.13 | 2025-12-18 | 2025-12-31 (já encerrado) | 2026-12-31 |
| 3.5 | 3.5.16 | 2026-06-25 | 2026-06-30 (já encerrado) | 2032-06-30 (comercial) |
| 4.0 | 4.0.9 | 2026-10-22 | 2026-12-31 | 2027-12-31 |
| 4.1 | 4.1.2 | 2026-10-22 | 2027-07-31 | 2028-07-31 |

- Maven Central lista 3.4.0-3.4.13, 3.5.0-3.5.16, 4.0.0-4.0.9, 4.1.0-4.1.2 e também 4.2.0-RC2 (pré-release, ignorar).
- Data de lançamento de 4.0.0 e 4.1.0: NÃO CONFIRMADO (wiki 4.1 só traz data de edição 2026-10-09).
- Atenção: endoflife.date diz que 3.5/4.0 suportam Java 17-25, 4.1 Java 17-26; a doc oficial (docs.spring.io/spring-boot/4.0 e /4.1 system-requirements) diz "até Java 27" para 4.0.9 e 4.1.2. Divergência entre fontes; usar a doc oficial. Java 21 é suportado em todas.

## 2. Requisitos de base por salto (ENTREGA 1b)
Fontes: https://docs.spring.io/spring-boot/{3.4,3.5,4.0}/system-requirements.html e /spring-boot/system-requirements.html (4.1.2); BOMs `spring-boot-dependencies-<v>.pom` em repo1.maven.org.

| Item | 3.4.13 | 3.5.16 | 4.0.9 | 4.1.2 |
|---|---|---|---|---|
| Java | 17-24 | 17-25 | 17-27 | 17-27 |
| Gradle | 7.6.4+ ou 8.4+ | 7.6.4+ ou 8.4+ | 8.14+ ou 9.x | 8.14+ ou 9.x |
| Spring Framework | 6.2.15+ | 6.2.19 | 7.0.10 | 7.0.10+ (notas 4.1.0 dizem 7.0.8 - inconsistente na wiki) |
| Spring Security | 6.4.x (não verificado) | 6.5.11 | 7.0.8 | 7.1.2 |
| Servlet/Tomcat | Servlet 6.0, Tomcat 10.1 | Servlet 6.0, Tomcat 10.1.55 | Servlet 6.1, Tomcat 11.0.27 | Servlet 6.1, Tomcat 11.0.27 |
| Jackson | 2.x | 2.21.4 | Jackson 3 (`tools.jackson` 3.1.7) + jackson 2.21.7 BOM | Jackson 3.1.7 + 2.21.7 |
| Micrometer / Tracing | 1.14.x (não verificado) | 1.15.12 / 1.5.12 | 1.16.8 / 1.6.8 | 1.17.2 / 1.7.2 |
| OpenTelemetry | - | 1.49.0 | 1.55.0 | 1.62.0 |
| Kotlin gerenciado | - | 1.9.25 | 2.2.21 | 2.3.21 |
| Kotlin mínimo | - | sem mudança | 2.2 (migration guide) | 2.2 presumido; NÃO CONFIRMADO |
| Testcontainers gerenciado | - | 1.21.4 | 2.0.5 | 2.0.5 |
| Mockito | - | 5.17.0 | 5.20.0 | 5.23.0 |
| Spring Kafka / AMQP | - | 3.3.16 / 3.2.12 | 4.0.8 / 4.0.6 | 4.1.2 / 4.1.2 |
| Spring Data BOM | - | 2025.0.13 | 2025.1.8 | 2026.0.2 |
| MongoDB driver | - | 5.5.2 | 5.6.5 | 5.8.1 |
| JUnit Jupiter | - | 5.12.2 | 6.0.3 | 6.0.3 |
| Lombok | - | 1.18.46 | 1.18.48 | 1.18.48 |

Notas: jackson-module-kotlin gerenciado = 2.21.7 no 4.1.2 (docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html); no Boot 4 o `jackson-annotations` continua em `com.fasterxml.jackson.core` (2.21). Springdoc, jjwt, awssdk, okhttp/mockwebserver e resilience4j NÃO são gerenciados pelo BOM (ausentes no POM 4.1.2) - mantemos versões explícitas.

## 3. Mudanças que quebram por salto (ENTREGA 1c)

### 3.4.5 -> 3.4.13
Patches apenas. Nenhuma quebra documentada pesquisada (release notes de patch não lidas: NÃO CONFIRMADO). Gradle 8.14.x do wrapper atende.

### 3.4.13 -> 3.5.16 (fonte: wiki Spring-Boot-3.5-Release-Notes; "Minimum requirements: no changes")
- `spring-boot-parent` não é mais publicado (irrelevante para Gradle com plugin).
- Endpoint `heapdump` com `access=NONE` por padrão.
- Propriedades `*.enabled` só aceitam `true`/`false`.
- Nomes de profile validados (letras, dígitos, `-`, `_`; 3.5.1 permite `.`, `+`, `@`); `spring.profiles.validate=false` desliga.
- Redis: com `spring.data.redis.url`, o database vem da URL e `spring.data.redis.database` é ignorado (afeta orchestrator).
- Só o bean `applicationTaskExecutor` (sem alias `taskExecutor`).
- `@ConditionalOnMissingBean` passa a considerar tipos genéricos de retorno.
- WebClient e TestRestTemplate agora seguem redirects por padrão.
- Renomeações: `spring.mvc.converters.preferred-json-mapper` -> `spring.http.converters.preferred-json-mapper`; `spring.codec.*` -> `spring.http.codecs.*`; `micrometer.observations.annotations.enabled` removida -> `management.observations.annotations.enabled`; Pushgateway `base-url` -> `address` (e exige `prometheus-metrics-exporter-pushgateway`); SignalFX depreciado.
- Deps: Security 6.5, Micrometer 1.15, Testcontainers 1.21, Mockito 5.17, Kafka 3.9, OTel 1.49 (lista de wiki, parte final da página não lida).
- Spring Security 6.5 é a última 6.x e traz os "opt-ins" para 7.0 (docs.spring.io/spring-security/reference/migration/index.html).

### 3.5.16 -> 4.0.9 (fonte: wiki Spring-Boot-4.0-Migration-Guide; 127 mil caracteres, os últimos 28 mil NÃO foram lidos)
- Pré-requisito oficial: ir antes para o último 3.5.x e eliminar chamadas a APIs depreciadas.
- Base: Java 17+, Kotlin 2.2+ (nossa 2.0.21 não serve), Jakarta EE 11 / Servlet 6.1, Spring Framework 7, Spring Security 7.0, Gradle 8.14+/9.x (docs.spring.io).
- Modularização: módulos `spring-boot-<tech>`, starters de teste `spring-boot-starter-<tech>-test`. Renomes: `starter-web` -> `starter-webmvc`; `starter-aop` -> `starter-aspectj`; `starter-oauth2-*` -> `starter-security-oauth2-*` (nosso `starter-oauth2-resource-server` no BFF vira `spring-boot-starter-security-oauth2-resource-server`); `@WithMockUser`/`@WithUserDetails` exigem `spring-boot-starter-security-test`; Flyway/Liquibase exigem seus starters. Caminho em etapas: `spring-boot-starter-classic` e `spring-boot-starter-test-classic`.
- Jackson 3 padrão: `com.fasterxml.jackson` -> `tools.jackson` (exceto `jackson-annotations`). Renomes: `@JsonComponent` -> `@JacksonComponent`, `@JsonMixin` -> `@JacksonMixin`, `Jackson2ObjectMapperBuilderCustomizer` -> `JsonMapperBuilderCustomizer`, `JsonObjectSerializer` -> `ObjectValueSerializer`, `JsonValueDeserializer` -> `ObjectValueDeserializer`. Propriedades `spring.jackson.read/write.*` -> `spring.jackson.json.read/write.*` (no 4.1 há também `spring.jackson.read.*`/`write.*` novas). É preciso definir bean `JsonMapper` (um bean `ObjectMapper` não substitui). Compatibilidade: `spring.jackson.use-jackson2-defaults=true` e módulo depreciado `spring-boot-jackson2` (`spring.jackson2.*`).
- Testes: `@MockBean`/`@SpyBean` REMOVIDOS -> `@MockitoBean`/`@MockitoSpyBean` (não funcionam em classes `@Configuration`); `MockitoTestExecutionListener` removido. `@SpringBootTest` não configura mais MockMvc/WebClient/TestRestTemplate: usar `@AutoConfigureMockMvc`, `@AutoConfigureTestRestTemplate` (+ `spring-boot-resttestclient`), `RestTestClient`.
- Removidos: Undertow, Spring Retry deixa de ser gerenciado, Spock, scripts de launch embutidos, uber-jar loader clássico.
- Propriedades: `spring.data.mongodb.*` (conexão) -> `spring.mongodb.*` (afeta manager); `management.health.mongo` -> `mongodb`; `spring.kafka.retry.topic.backoff.random` -> `jitter`; `StreamBuilderFactoryBeanCustomizer` substituído; `RabbitRetryTemplateCustomizer` substituído por `RabbitTemplateRetrySettingsCustomizer`/`RabbitListenerRetrySettingsCustomizer`; `spring.session.*` -> `spring.session.data.*`.
- Actuator: probes liveness/readiness habilitados por padrão (`management.endpoint.health.probes.enabled`); parâmetros de endpoint usam `org.jspecify` `@Nullable`. Detalhes de Micrometer/OTel (starters novos como `micrometer-tracing-opentelemetry`): NÃO CONFIRMADO (parte truncada).
- Spring Security 7: Spring Authorization Server incorporado; `spring-security-access` (AccessDecisionManager/Voter) em módulo legado (docs.spring.io/spring-security/reference/7.0/migration/servlet/authorization.html). Remoção de `AntPathRequestMatcher`/`MvcRequestMatcher` em favor de `PathPatternRequestMatcher`: NÃO CONFIRMADO nas docs lidas (as páginas de migração servlet/oauth2 não foram abertas por limite de requisições). Jackson no Security: `SecurityJacksonModules` substitui `SecurityJackson2Modules`.
- Ferramentas: `spring-boot-properties-migrator` (runtime, temporário) - confirmado no guia. Receitas OpenRewrite: NÃO CONFIRMADO (a URL de docs tentada deu 404). Do conhecimento prévio: `org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_5` e `org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0` - não validados.
- Guia: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide

### 4.0.9 -> 4.1.2 (fonte: wiki Spring-Boot-4.1-Release-Notes)
- Remove tudo que estava depreciado em 4.0 (compile pode quebrar se sobrar uso).
- Layertools removido; Derby depreciado; Dynatrace v1 depreciado; LiveReload do devtools depreciado.
- Maven AOT: `-DskipTests` não pula mais AOT de testes (Gradle: n/a).
- Gradle `BuildInfo`: arquivo padrão agora `META-INF/build-info.properties` (afeta Actuator /info se customizado; usar `filename`).
- Binding: parâmetros `Optional` de construtor viram `Optional.empty()` e não `null`; YAML mantém objetos vazios.
- Reactor HTTP: `proxyWithSystemProperties()` por padrão; Tomcat limpa tmp dir ao fechar contexto; JPA bootstrap `deferred` exige `AsyncTaskExecutor`.
- Deps: Spring Framework 7.0.x, Security 7.1.0, Micrometer 1.17, Mockito 5.23, Kotlin 2.3.21, Spring Kafka/AMQP 4.1.0, Spring Data 2026.0.0, Hibernate 7.4, Jackson props novas `spring.jackson.read/write/factory.*`.
- Guia: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes

### Recomendação oficial sobre pular minors (ENTREGA 1e)
- Confirmado: "Upgrade to the latest 3.5.x first" antes do 4.0 (Migration Guide 4.0); Spring Security: usar último patch do Boot 4.0 e depois Security 7; 6.5 antes do 7 (docs.spring.io/spring-security/reference/migration/index.html).
- Salto 3.4 -> 3.5 direto ao último patch: comum; política formal de "não pular minor" além do citado: NÃO CONFIRMADO.
- 4.0 -> 4.1: o 4.1 apenas remove depreciações do 4.0, sem guia separado de migração; pular o 4.0 (3.5.16 -> 4.1.2 direto) não tem recomendação oficial encontrada: NÃO CONFIRMADO (mas o guia 4.0 continua sendo o principal e 4.1 é incremental).

## 4. Matriz de compatibilidade (ENTREGA 2)

| Biblioteca | Boot 3.4/3.5 | Boot 4.0 | Boot 4.1 | Evidência |
|---|---|---|---|---|
| springdoc-openapi | 2.8.x (2.8.8 hoje; 2.8.17 última 2.8.x; 2.9.x/2.10.0 também 2.x). 2.10.0 compila contra Boot 3.5.16 | 3.0.x (3.0.0 compila contra Boot 4.0.0, swagger-ui 5.30.1) | 3.1.x-3.2.x (3.2.0 é a última, 2026-10-24) | springdoc.org/faq (matriz 4.1->3.1-3.2, 4.0->3.0); POMs `springdoc-openapi-2.10.0.pom`, `-3.0.0.pom`; maven-metadata |
| Spring Boot Admin (server e client) | 3.4.x (3.4.7 última) para Boot 3.4; 3.5.x (3.5.11 última) para Boot 3.5 | 4.0.x (4.0.4 última) - suposição por numeração, NÃO CONFIRMADO por POM | 4.1.x (4.1.5, 2026-11-06); POM `spring-boot-admin-server-4.1.5` usa `spring-boot-starter-webmvc/webclient/webflux` 4.1.2 (módulos Boot 4) | maven-metadata e POM; parent SBA 3.5.11 sem info de Boot |
| springmockk | 4.0.2 (Boot 3.x, atual) | 5.0.x (5.0.0, 5.0.1 de 2025-11-30) | idem 5.0.1 (sem versão mais nova) | POM 5.0.1: Spring 7.0.1, Kotlin 2.2.21, MockK 1.14.6. Exigência de Boot 4 vs 3.5 para o 5.x: NÃO CONFIRMADO (README não lido) |
| MockK | 1.13.13/1.14.x | 1.14.x (springmockk 5.0.1 usa 1.14.6) | 1.14.x | POM springmockk 5.0.1 |
| Testcontainers | 1.20.x/1.21.4 (3.5 gerencia 1.21.4) | 2.0.5 (gerenciado) | 2.0.5 (gerenciado) | BOM 3.5.16/4.0.9/4.1.2. Módulos 2.x têm prefixo `testcontainers-` (ex.: `org.testcontainers:testcontainers-kafka` 2.0.0-2.0.5 existe em Maven Central); 1.x era `org.testcontainers:kafka`. Nomes exatos de `junit-jupiter`, `rabbitmq`, `localstack` no 2.x e remoção de APIs: NÃO CONFIRMADO (página de migração deu 404) |
| Kotlin | 2.0.21 funciona (Boot 3.x gerencia 1.9.25, plugin Gradle sobrescreve) | mínimo 2.2 (guia 4.0); gerenciado 2.2.21 | gerenciado 2.3.21 | wiki migration guide e BOMs |
| Gradle | 8.4+ | 8.14+ ou 9.x | 8.14+ ou 9.x | system-requirements; Gradle atual 9.9.0 (services.gradle.org/versions/current). Wrapper 8.14.x atende 4.x |
| jackson-module-kotlin | 2.18-2.21 (Jackson 2; gerenciado) | no Boot 4 o módulo Jackson 3 é `tools.jackson.module:jackson-module-kotlin` (3.x); o 2.21.7 no BOM é para o modo de compatibilidade Jackson 2. Nome exato do artefato 3.x e publicação: NÃO CONFIRMADO | idem | BOM 4.1.2 (2.21.7, jackson-bom 3.1.7) |
| jackson-dataformat-yaml / jsr310 | 2.x gerenciado | Jackson 3: JSR-310 e outros módulos ficam embutidos/auto-registrados (módulos auto-registrados, guia 4.0); coordenadas em `tools.jackson.dataformat:jackson-dataformat-yaml`: NÃO CONFIRMADO | idem | guia 4.0 |
| jjwt | 0.12.x/0.13.0 (última, 2025-08-20) | 0.13.0 usa `jjwt-jackson` baseado em Jackson 2; suporte a Jackson 3: NÃO CONFIRMADO (sem versão posterior a 0.13.0). Boot 4 mantém `com.fasterxml.jackson` 2.21.7 apenas via módulo de compatibilidade | idem | maven-metadata jjwt-jackson. Alternativa: `jjwt-gson` ou impl. própria |
| resilience4j | 2.3.0/2.4.0 (2.4.0 última, 2026-03-14) | 2.4.0 sem evidência de dependência de Boot (usamos só core retry/circuitbreaker, não o starter spring-boot3) - deve funcionar; NÃO CONFIRMADO | idem | maven-metadata |
| Spotless plugin | 6.25.0 (atual) | NÃO CONFIRMADO versões mínimas para Gradle 9 | idem | não pesquisado |
| ktlint / google-java-format | NÃO CONFIRMADO | NÃO CONFIRMADO | | não pesquisado |
| Micrometer/OTel | 1.15/1.49 gerenciados | 1.16/1.55 | 1.17/1.62 | BOMs |
| spring-kafka | 3.3.16 | 4.0.8 | 4.1.2 | BOMs |
| spring-amqp | 3.2.12 | 4.0.6 | 4.1.2 | BOMs |
| spring-data-mongodb/redis | Data 2025.0.13 | 2025.1.8 | 2026.0.2 | BOMs |
| spring-security (oauth2 RS) | 6.5.11 | 7.0.8 | 7.1.2 | BOMs |
| WebClient/WebFlux | 3.x ok | `starter-webflux` continua; WebClient auto-config em `spring-boot-starter-webclient` (visto no POM SBA 4.1.5) | idem | POM SBA |
| Lombok | 1.18.46 | 1.18.48 | 1.18.48 | BOMs |
| AWS SDK v2 sqs | não gerenciado; qualquer 2.x | idem (sem dependência de Jackson do Boot: NÃO CONFIRMADO) | idem | BOM 4.1.2 (ausente) |
| okhttp mockwebserver 4.12.0 | funciona | não gerenciado; independe do Boot; 4.12 usa Kotlin 1.9 stdlib: sem conflito esperado, NÃO CONFIRMADO | idem | BOM (ausente) |

Primeira versão que EXIGE Boot 4: springdoc 3.0.0 (parent POM Boot 4.0.0); SBA 4.0.0 (inferido, sem POM); springmockk 5.0.0 (inferido, Spring 7); Testcontainers 2.0.x é só ligado ao Boot 4 via gerenciamento (a lib roda em qualquer Boot, mas os módulos novos têm outros nomes).
Última versão que serve Boot 3.x: springdoc 2.10.0 (compila contra Boot 3.5.16); SBA 3.5.11; springmockk 4.0.2.

## 5. Suporte/EOL e versão alvo (ENTREGA 3)
Fonte: https://endoflife.date/spring-boot (23/10/2026).
- 3.4: OSS já acabou (2025-12-31); comercial acaba 2026-12-31 (daqui ~2 meses). Estamos fora de suporte aberto e sem patches.
- 3.5: OSS acabou em 2026-06-30; só comercial (até 2032-06-30). Rota intermediária, não destino.
- 4.0: OSS acaba 2026-12-31 (daqui ~8 semanas). Não vale como destino final.
- 4.1: OSS até 2027-07-31 (~9 meses), comercial até 2028-07-31. 4.1.2 é a estável mais recente (4.2.0-RC2 apenas pré-release).

Recomendação: alvo final Spring Boot 4.1.2 (ou 4.1.x mais novo no dia), passando por 3.4.13 -> 3.5.16 -> 4.0.9 -> 4.1.2 como marcos de verificação (o guia oficial exige o último 3.5 antes do 4.0, e 4.0 perde suporte OSS em 31/12/2026). Mudanças 4.0 -> 4.1 são pequenas, então 4.0.9 pode ser um ponto de parada de uma etapa só, e subir para 4.1 logo em seguida. Observação: mesmo 4.1 terá suporte OSS por ~9 meses; planejar 4.2 em 2027.

## 6. Riscos para os nossos apps (resumo)
1. Jackson 3 (todos): `com.fasterxml.jackson.datatype:jackson-datatype-jsr310` e `dataformat-yaml` direto no build; `ObjectMapper` customizado precisa virar `JsonMapper`; renomes `@JsonComponent`.
2. jjwt-jackson 0.13.0 (orch, mgr) depende do Jackson 2: coexistência com Jackson 3 não confirmada.
3. Kotlin 2.0.21 -> mínimo 2.2 (mgr) + jackson-module-kotlin para Jackson 3 + plugins kotlin-spring; Spotless/ktlint a revalidar.
4. Starters renomeados (`web`->`webmvc`, `oauth2-resource-server`->`security-oauth2-resource-server`, testes por tecnologia).
5. `@MockBean`/`@SpyBean` removidos e springmockk 4.0.2 -> 5.x (mgr, também orch/bff se usarem MockBean) e `@AutoConfigureMockMvc`.
6. springdoc 2.8.x -> 3.x (todos os apps com UI).
7. Spring Security 7 (orch, bff, mgr, admin): matchers (AntPathRequestMatcher: NÃO CONFIRMADO), oauth2 resource server, JWT/Jackson.
8. Testcontainers 1.x -> 2.x (orch): nomes de módulos (`testcontainers-kafka`...), pacotes, `@ServiceConnection`.
9. Spring Boot Admin server/client 3.5.x -> 4.x e SBA server com Security 7/Tomcat 11.
10. Mongo (`spring.data.mongodb.*` -> `spring.mongodb.*`), Redis (URL/database), Kafka/AMQP retry customizers, Lombok com Jackson 3, Actuator probes ligados por padrão e métricas Micrometer 1.16/1.17.

## 7. NÃO CONFIRMADO (lista)
Datas de 4.0.0/4.1.0; release notes de patches 3.4.x; trecho final (~28 mil chars) da migration guide 4.0; AntPathRequestMatcher no Security 7; nomes exatos das receitas OpenRewrite; migration guide Testcontainers 2 (404) e nomes de todos os módulos 2.x; SBA 4.0.x exigência exata; springmockk 5 vs Boot 3.5; jjwt com Jackson 3; Spotless/ktlint/google-java-format para Gradle 9 e Kotlin 2.2+; jackson-module-kotlin 3.x coordenadas; Kotlin mínimo do 4.1.
