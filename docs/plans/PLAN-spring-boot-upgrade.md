# PLAN — Upgrade do Spring Boot (3.4.5 → 4.1.2)

Data base: 2026-11-07. Evidências, URLs e itens não confirmados: [PLAN-spring-boot-upgrade-pesquisa.md](PLAN-spring-boot-upgrade-pesquisa.md).

## 1. Contexto e decisão

Os quatro apps Spring (`generic-orchestrator`, `service-portal-bff`, `service-portal-manager`, `service-portal-admin`) estão no Spring Boot 3.4.5, fixado como restrição de projeto ("não atualizar" no `AGENTS.md` de cada repositório). Essa linha saiu do suporte aberto e os patches pararam:

| Linha | Último patch | Fim do suporte OSS | Fim do suporte comercial |
|---|---|---|---|
| 3.4 | 3.4.13 (2025-12-18) | 2025-12-31 (encerrado) | 2026-12-31 |
| 3.5 | 3.5.16 (2026-06-25) | 2026-06-30 (encerrado) | 2032-06-30 |
| 4.0 | 4.0.9 (2026-10-22) | 2026-12-31 | 2027-12-31 |
| 4.1 | 4.1.2 (2026-10-22) | 2027-07-31 | 2028-07-31 |

Fonte: endoflife.date e Maven Central, consultados em 2026-11-07.

**Decisão proposta:** levantar a restrição e chegar ao Spring Boot **4.1.2** (ou ao 4.1.x mais novo no dia), passando por quatro marcos verificáveis. A linha 4.0 não serve de destino, porque o suporte aberto acaba em 2026-12-31. O Java 21 continua (o Boot 4 aceita Java 17 a 27). O `4.2.0-RC2` existe no Maven Central, mas é pré-release e fica fora.

**Pendente do dono:** aprovar o levantamento da restrição e o alvo 4.1.x. Sem essa aprovação, nenhum marco começa.

## 2. Rota por marcos

A recomendação oficial é subir uma linha por vez. O guia de migração do 4.0 manda ir antes para o último 3.5.x e eliminar o uso de APIs depreciadas. Pular de 3.5.16 direto para 4.1.2 não tem recomendação oficial encontrada, então seguimos todos os saltos. O 4.1 só remove o que o 4.0 depreciou.

| Marco | De → para | Natureza | Risco |
|---|---|---|---|
| M0 | pré-requisitos | `feature/deps-update` mergeada; testes do admin; remover usos de APIs depreciadas | baixo |
| M1 | 3.4.5 → **3.4.13** | só patches | baixo |
| M2 | 3.4.13 → **3.5.16** | última 3.x; prepara o 4.0 | médio |
| M3 | 3.5.16 → **4.0.9** | salto grande: Spring Framework 7, Security 7, Jackson 3, Kotlin 2.2, starters renomeados | alto |
| M4 | 4.0.9 → **4.1.2** | incremental: remove depreciações do 4.0 | baixo a médio |

Cada marco vira uma branch por app (`feature/boot-3-4-13`, `feature/boot-3-5`, `feature/boot-4-0`, `feature/boot-4-1`), sempre a partir da `main` já com o marco anterior mergeado.

## 3. Requisitos de base por marco

| Item | 3.4.13 | 3.5.16 | 4.0.9 | 4.1.2 |
|---|---|---|---|---|
| Java | 17–24 | 17–25 | 17–27 | 17–27 |
| Gradle | 7.6.4+ ou 8.4+ | 7.6.4+ ou 8.4+ | 8.14+ ou 9.x | 8.14+ ou 9.x |
| Spring Framework | 6.2.15+ | 6.2.19 | 7.0.10 | 7.0.x (notas divergem) |
| Spring Security | 6.4.x | 6.5.11 | 7.0.8 | 7.1.2 |
| Servlet / Tomcat | 6.0 / 10.1 | 6.0 / 10.1.55 | 6.1 / 11.0.27 | 6.1 / 11.0.27 |
| Jackson | 2.x | 2.21.4 | 3 (`tools.jackson` 3.1.7) | 3.1.7 |
| Kotlin gerenciado | n/a | 1.9.25 | 2.2.21 | 2.3.21 |
| Testcontainers gerenciado | n/a | 1.21.4 | 2.0.5 | 2.0.5 |
| Spring Kafka / AMQP | n/a | 3.3.16 / 3.2.12 | 4.0.8 / 4.0.6 | 4.1.2 / 4.1.2 |
| Spring Data | n/a | 2025.0.13 | 2025.1.8 | 2026.0.2 |

O wrapper atual (Gradle 8.14.6) atende todos os marcos. O Java 21 também. O Kotlin 2.0.21 do Manager **não** atende o Boot 4 (mínimo 2.2).

## 4. Compatibilidade das bibliotecas por marco

| Biblioteca | Hoje (`feature/deps-update`) | M1 e M2 (Boot 3.x) | M3 e M4 (Boot 4.x) |
|---|---|---|---|
| springdoc-openapi | 2.8.14 | 2.8.14 no 3.4; 2.10.0 compila contra o 3.5.16 | 3.0.x (4.0), 3.1.x a 3.2.x (4.1). A 3.0.0 é a primeira que exige o Boot 4 |
| Spring Boot Admin (server e client) | 3.4.7 | 3.4.7 no 3.4; 3.5.11 no 3.5 | 4.0.x (não confirmado por POM), 4.1.5 no 4.1 |
| springmockk | 4.0.2 | 4.0.2 | 5.0.x (usa Spring 7, Kotlin 2.2.21, MockK 1.14.6) |
| Testcontainers | 1.21.4 | 1.21.4 | 2.0.5, com módulos novos prefixados `testcontainers-` |
| Kotlin | 2.0.21 | 2.0.21 | 2.2+ obrigatório |
| jjwt | 0.13.0 (a última) | 0.13.0 | 0.13.0 depende de Jackson 2: coexistência com Jackson 3 não confirmada |
| resilience4j | 2.4.0 (a última) | 2.4.0 | 2.4.0, usamos só o core: sem dependência do Boot evidenciada |
| Gradle | 8.14.6 | 8.14.6 | 8.14.6 ou 9.x |

O springdoc acima de 2.8.14 quebra o contexto no Boot 3.4.5 (medido no BFF: `PatternParseException`, 15 testes falham). Por isso o springdoc só sobe junto com o Boot.

## 5. O que quebra em cada marco

### M1 — 3.4.5 → 3.4.13
Só patches. Nenhuma quebra documentada encontrada, mas as notas de cada patch não foram lidas. Confirmar no início do marco.

### M2 — 3.4.13 → 3.5.16
- `heapdump` com `access=NONE` por padrão (alinha com a melhoria de fechar o actuator).
- Propriedades `*.enabled` aceitam só `true` ou `false`.
- Nomes de profile validados (`spring.profiles.validate=false` desliga).
- Redis: com `spring.data.redis.url`, o database vem da URL e `spring.data.redis.database` é ignorado (afeta o orchestrator).
- Só o bean `applicationTaskExecutor`, sem o alias `taskExecutor`.
- `WebClient` e `TestRestTemplate` passam a seguir redirects por padrão (afeta orchestrator e BFF).
- Renomeações de propriedades: `spring.mvc.converters.preferred-json-mapper` e `spring.codec.*` migram para `spring.http.*`.
- Spring Security 6.5, a última 6.x, traz os "opt-ins" que preparam a 7.0.
- Ferramenta oficial: `spring-boot-properties-migrator` (temporário, só durante a migração).

### M3 — 3.5.16 → 4.0.9
- Pré-requisito oficial: estar no último 3.5.x e sem chamadas a APIs depreciadas.
- Modularização: `starter-web` → `starter-webmvc`; `starter-oauth2-resource-server` → `starter-security-oauth2-resource-server`; starters de teste por tecnologia; `@WithMockUser` exige `spring-boot-starter-security-test`.
- Jackson 3 como padrão: `com.fasterxml.jackson` → `tools.jackson` (exceto `jackson-annotations`); `ObjectMapper` customizado vira `JsonMapper`; `@JsonComponent` vira `@JacksonComponent`; propriedades `spring.jackson.*` mudam.
- Testes: `@MockBean` e `@SpyBean` **removidos** (usar `@MockitoBean` e `@MockitoSpyBean`); `@SpringBootTest` deixa de configurar `MockMvc`, `WebClient` e `TestRestTemplate` sozinho (exige as anotações `@AutoConfigure...`).
- Propriedades: `spring.data.mongodb.*` (conexão) → `spring.mongodb.*`; `management.health.mongo` → `mongodb`; `spring.kafka.retry.topic.backoff.random` → `jitter`.
- Actuator: probes de liveness e readiness habilitados por padrão.
- Spring Security 7: Authorization Server incorporado; `spring-security-access` num módulo legado.
- Removidos: Undertow, Spock, scripts de launch embutidos, uber-jar loader clássico.

### M4 — 4.0.9 → 4.1.2
- Remove tudo que o 4.0 depreciou (o compile pode quebrar se sobrar uso).
- `BuildInfo` do Gradle: arquivo padrão agora `META-INF/build-info.properties`.
- Binding: parâmetros `Optional` de construtor viram `Optional.empty()` em vez de `null`.
- `spring.jackson.*` ganha propriedades novas (`read`, `write`, `factory`).

## 6. Impacto por app (mapa do código na `main`)

| App | Pontos sensíveis | Marco em que pesa |
|---|---|---|
| **admin** | sem testes; `SecurityConfig` usa `AntPathRequestMatcher`; `@EnableAdminServer`; SBA server 3.4.7 | M0 (criar testes), M2, M3 |
| **bff** | `@MockBean` em 1 arquivo (`SecurityConfigIT`, 5 usos); `starter-web` e `starter-oauth2-resource-server`; Jackson 2 em 4 arquivos; `WebClient` em 9 arquivos; springdoc em controllers | M0 (trocar `@MockBean`), M3 |
| **manager** (Kotlin) | Kotlin 2.0.21; `@MockkBean` em 4 usos (springmockk 4); `jackson-module-kotlin` com `registerKotlinModule()` em `YamlValidationService` e `VersioningService`; `spring.data.mongodb.*`; 8 arquivos com OpenAPI | M3 (o mais denso: Kotlin, springmockk, Jackson, Mongo) |
| **orchestrator** | `Jackson2JsonRedisSerializer<FlowDefinition>` em `RedisCacheConfig`; 2 `ObjectMapper` em `JacksonConfig`; Kafka e Rabbit em 5 arquivos; Testcontainers 1.21.4; `WebClient` em 6 arquivos; Lombok em 43 arquivos | M2 (Redis), M3 (Jackson, Testcontainers 2) |

O frontend não usa Spring e fica fora deste plano.

## 7. Trabalho de M0 (pré-requisitos)

1. Mergear as branches `feature/deps-update` dos 5 apps (wrapper 8.14.6, Spotless 8, libs atualizadas).
2. **Admin:** escrever testes de segurança com `MockMvc` antes de qualquer salto (`/actuator/health` anônimo, `/` redireciona para login, `POST /instances` sem credencial dá 401 e com `httpBasic` dá 201). Hoje nada protege o upgrade desse app. Coincide com a melhoria de testes do admin.
3. **BFF:** trocar `@MockBean` por `@MockitoBean` no `SecurityConfigIT` ainda no Boot 3.x. Confirmar que a anotação existe na versão do Spring Framework do 3.4.13 (não confirmado na pesquisa).
4. **Manager:** isolar o uso de `@MockkBean` e avaliar se o springmockk 5 funciona no Boot 3.5 (não confirmado).
5. Zerar os avisos de depreciação no build de cada app (compilar com avisos visíveis e registrar a contagem de partida).
6. Fixar a decisão sobre o `jjwt` com Jackson 3 (ver riscos).

## 8. Critérios de entrada e saída de cada marco

Entrada: marco anterior mergeado, `main` verde, contagem de avisos de depreciação registrada.

Saída (todos obrigatórios):
- `./gradlew build jacocoTestCoverageVerification` verde em cada app (gate de 95% mantido, sem baixar limiar e sem apagar teste).
- `docker build` das imagens passa.
- Teste de integração com a stack completa (`teste-integrado-service-portal.sh`, projeto compose `service-portal`) sem falha nova em relação à linha de base do marco anterior.
- `/actuator/health` UP em cada app; SBA com os 3 clientes registrados.
- Nenhum aviso do `spring-boot-properties-migrator` sobrando; depois remover o migrator.
- Contagem de avisos de depreciação do marco menor ou igual à anterior (zero antes de entrar no M3).
- `AGENTS.md` de cada app atualizado (Stack e Armadilhas) e `repo-index.py check` ok.

## 9. Estratégia de execução

- Uma atividade por app e por marco, no máximo duas em paralelo (limite da máquina; builds de Gradle e Testcontainers são pesados). Fora o teste de integração, que roda sozinho.
- Ordem dos apps em cada marco: admin (menor, depois dos testes novos), BFF, Manager, orchestrator (o que concentra mais risco em M2 e M3).
- Manter o SBA server e os clients na mesma linha em cada marco. A compatibilidade entre linhas diferentes (client 3.4 contra server 3.5, por exemplo) não foi confirmada.
- Antes de cada marco, um spike curto resolve os itens "não confirmados" que ele toca.
- Depois de cada marco mergeado, marcar a versão: tag `boot-<versão>` na `main` de cada repositório e imagem com a mesma tag.

## 10. Reversão

- Cada marco é um PR por app, isolado: reverter o PR volta ao marco anterior.
- Não há migração de dados neste plano. Os dados do MongoDB e do Postgres ficam nos volumes `service-portal_*`; o driver e o Spring Data novos não devem exigir migração, mas **não confirmado**: validar no teste de integração do M3 com o volume atual e com um volume novo.
- Mantenha a imagem do marco anterior com tag fixa no compose enquanto o marco novo não passar no teste de integração.

## 11. Riscos e itens não confirmados

Ordem aproximada de gravidade para os nossos apps:

1. **Jackson 3 em todos os apps.** Os `ObjectMapper` customizados viram `JsonMapper`. No orchestrator, `RedisCacheConfig` usa `Jackson2JsonRedisSerializer`; o nome do serializer equivalente no Spring Data Redis 4 não foi confirmado.
2. **jjwt-jackson 0.13.0** (orchestrator e manager) depende do Jackson 2, sem versão mais nova. Coexistir com o Jackson 3 não foi confirmado. Se não coexistir, trocar a serialização do jjwt por uma que não dependa do módulo Jackson.
3. **Kotlin 2.0.21 → 2.2+** no Manager, com o plugin `kotlin-spring` e o `jackson-module-kotlin` para Jackson 3 (nome e publicação do artefato 3.x não confirmados). Revalidar Spotless e ktlint, que hoje está fixo em 1.0.1.
4. **Starters renomeados** e `@MockBean` removido (BFF e Manager).
5. **springdoc 2.8 → 3.x** em todos os apps com documentação OpenAPI (17 arquivos entre BFF e orchestrator, 8 no Manager).
6. **Spring Security 7:** a remoção de `AntPathRequestMatcher` e `MvcRequestMatcher` **não foi confirmada** pelas docs lidas; ler o guia de migração do Security 7 antes de tocar no `SecurityConfig` do admin.
7. **Testcontainers 1.x → 2.x** (orchestrator): coordenadas e pacotes mudam, e o guia de migração do Testcontainers 2 deu 404.
8. **Spring Boot Admin 4.x:** a linha 4.0.x para o Boot 4.0 é inferência por numeração, sem POM confirmado.
9. **Mongo e Kafka/AMQP:** propriedades renomeadas (`spring.mongodb.*`, backoff do Kafka) e Spring Data 2025.1 e 2026.0.
10. **Receitas OpenRewrite:** a página de docs deu 404. Pelo conhecimento prévio devem ser `org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_5` e `org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0`, mas confirmar o nome exato antes de usar.

Também não confirmados: datas de lançamento de 4.0.0 e 4.1.0; as últimas ~28 mil letras do guia de migração do 4.0; versões mínimas de Spotless, ktlint e google-java-format com Gradle 9 e Kotlin 2.2+; o Kotlin mínimo do 4.1; e se o salto direto 3.5 → 4.1 é aceitável.

## 12. Atividades derivadas, em ordem

| # | Atividade | Apps | Depende de |
|---|---|---|---|
| A0 | Decisão do dono: levantar a restrição, alvo 4.1.x | todos | — |
| A1 | M0: mergear dependências; testes do admin; `@MockBean` do BFF | admin, bff | A0 |
| A2 | M1: 3.4.13 | 4 apps | A1 |
| A3 | M2: 3.5.16 e ajustes de Redis e redirects | 4 apps | A2 |
| A4 | Spikes do M3: Jackson 3 no orchestrator (Redis), jjwt, Kotlin 2.2, springmockk 5 | orchestrator, manager | A3 |
| A5 | M3: 4.0.9 | 4 apps | A4 |
| A6 | M4: 4.1.2 | 4 apps | A5 |
| A7 | Fechamento: remover o migrator, atualizar `AGENTS.md` e README, tag `boot-4.1.2` | todos | A6 |
