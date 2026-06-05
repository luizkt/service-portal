# service-portal

Portal extensível com arquitetura em camadas e **Server Driven UI** — o BFF
controla menu e schemas; o frontend não tem regras de negócio. Workflows são
declarados em YAML, gerenciados pelo Manager e executados pelo Orchestrator
genérico.

```
Usuário
  └─> Frontend (React, :5173 / nginx :80)
        └─> BFF (Java, :8081)
              ├─> Manager (Kotlin, :8082)        — CRUD de fluxos (Mongo)
              └─> Orchestrator (Java, :8080)     — execução de fluxos
                    ├─> Redis           — cache de workflows (TTL 1h)
                    ├─> Manager         — fonte da verdade (HTTP)
                    ├─> RabbitMQ/Kafka  — integrações QUEUE
                    ├─> LocalStack/AWS  — integrações QUEUE (SQS)
                    └─> WireMock        — simulador de APIs HTTP externas

  Authentik (:9000) — IdP OIDC para autenticação do usuário final (SPA → BFF)
```

## Componentes

| Diretório                     | Stack                                          | Porta    |
|-------------------------------|------------------------------------------------|----------|
| [generic-orchestrator/](generic-orchestrator/)       | Java 21 + Spring Boot 3.4.5 + Gradle           | 8080     |
| [service-portal-bff/](service-portal-bff/)           | Java 21 + Spring Boot 3.4.5 + WebClient/WebFlux | 8081     |
| [service-portal-manager/](service-portal-manager/)   | Kotlin 2.0 + Spring Boot 3.4.5 + MongoDB        | 8082     |
| [service-portal-frontend/](service-portal-frontend/) | React 18 + TypeScript + Vite 5                  | 5173 / 80 |

## Infraestrutura local

| Serviço     | Imagem                          | Função                                  |
|-------------|---------------------------------|------------------------------------------|
| postgresql  | `postgres:16-alpine`            | Banco do Authentik                       |
| authentik   | `ghcr.io/goauthentik/server`    | IdP OAuth2/OIDC (server + worker)        |
| mongodb     | `mongo:7`                       | Persistência dos workflows (Manager)     |
| redis       | `redis:7-alpine`                | Cache de workflows do Orchestrator       |
| rabbitmq    | `rabbitmq:3-management-alpine`  | Broker para integrações QUEUE            |
| zookeeper   | `confluentinc/cp-zookeeper:7.5.0` | Coordenação Kafka                      |
| kafka       | `confluentinc/cp-kafka:7.5.0`   | Broker para integrações QUEUE            |
| localstack  | `localstack/localstack:3`       | Emulador AWS SQS para integrações QUEUE  |
| wiremock    | `wiremock/wiremock:3.9.1`       | Simulador de APIs HTTP externas          |
| portainer   | `portainer/portainer-ce:latest` | Gerenciamento e monitoramento de containers |

## Como rodar a stack completa

Pré-requisitos: **Docker 24+**, **Docker Compose v2.20+**. Recomendado 6 GB
RAM livres, 4 CPUs, 10 GB disco.

```bash
# 1. Configurar variáveis
cp env.example .env

# 2. Gerar segredos obrigatórios
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
echo "ORCHESTRATOR_JWT_SECRET=$(openssl rand -base64 60 | tr -d '\n')" >> .env

# 3. Subir tudo
docker compose -f docker-compose-service-portal.yml up -d

# 4. Configurar Authentik (primeiro uso)
#    http://localhost:9000/if/flow/initial-setup/ → criar admin
#    Admin → Applications → Providers → Create → OAuth2/OIDC Provider
#    Admin → Applications → Create → vincular ao Provider (slug: service-portal)
#    Adicionar client público "service-portal-spa" (Authorization Code + PKCE S256)
#
# 5. Ajustar .env e reiniciar BFF se mudou o slug
echo "AUTHENTIK_APP_SLUG=service-portal" >> .env
docker compose -f docker-compose-service-portal.yml restart bff
```

Acessos:

| Serviço    | URL                          | Notas                                  |
|------------|------------------------------|-----------------------------------------|
| Frontend   | http://localhost             | SPA — login redireciona ao Authentik    |
| BFF        | http://localhost:8081/bff/health | Health público                      |
| Manager    | http://localhost:8082/actuator/health | Health público                 |
| Authentik  | http://localhost:9000        | IdP — admin/login                       |
| RabbitMQ   | http://localhost:15672       | Management UI (guest/guest)             |
| WireMock   | http://localhost:18080/__admin | Mappings + admin                       |
| LocalStack | http://localhost:4566        | SQS endpoint                            |
| **Portainer** | **http://localhost:9001** | **Gerenciador de containers** |

## Composes isolados por aplicação

Cada aplicação tem seu próprio `docker-compose.yml` que sobe **apenas a infra
+ apps dependentes** necessários para rodar a aplicação localmente via
`./gradlew bootRun` ou `npm run dev`. Os `application-docker.yml` foram
padronizados para usar env vars com defaults Docker — o mesmo arquivo
funciona no compose isolado, no compose da raiz e em qualquer ambiente
externo que injete as vars corretas.

| Compose                                    | Sobe                                              | Como usar                                           |
|---------------------------------------------|---------------------------------------------------|------------------------------------------------------|
| [generic-orchestrator/docker-compose.yml](generic-orchestrator/docker-compose.yml)   | redis, rabbitmq, kafka, mongodb, localstack, wiremock, manager | `docker compose up -d && ./gradlew bootRun`         |
| [service-portal-manager/docker-compose.yml](service-portal-manager/docker-compose.yml) | mongodb                                            | `docker compose up -d && ./gradlew bootRun`         |
| [service-portal-bff/docker-compose.yml](service-portal-bff/docker-compose.yml)         | Authentik + Manager + Orchestrator + toda a infra | `docker compose up -d && ./gradlew bootRun`         |
| [service-portal-frontend/docker-compose.yml](service-portal-frontend/docker-compose.yml) | BFF + cadeia completa                              | `docker compose up -d && npm install && npm run dev` |

## Portainer — Monitoramento de Containers

O **Portainer CE** é incluído para gerenciar e monitorar os containers Docker:

**Acesso:** http://localhost:9001

**Funcionalidades:**
- 🐳 Ver status e logs de todos os containers
- 📊 Monitorar uso de recursos (CPU, memória)
- 🔧 Gerenciar networks, volumes, imagens
- ⚙️ Reiniciar/pausar/remover containers via UI
- 📈 Histórico e estatísticas

**Primeiro acesso:**
1. Abra http://localhost:9001
2. Crie usuário admin (será solicitado na primeira execução)
3. Conecte ao Docker local (aparece automaticamente)
4. Explore containers em "Containers" → lista todos os 15 serviços

**Dica:** Use para monitorar a saúde dos containers durante testes de carga ou troubleshooting.

---

## Decisões arquiteturais

- **Server Driven UI**: BFF expõe `/bff/menu` e `/bff/features/{id}/ui-schema`; o frontend é genérico.
- **Frontend só fala com o BFF**. Nunca diretamente com Orchestrator/Manager.
- **Auth do usuário**: PKCE S256 SPA → Authentik → Bearer no BFF (OAuth2 Resource Server, JWKS).
- **Auth server-to-server**: BFF → Manager/Orchestrator com cache de JWT HS512 e renovação automática.
- **Sub-recursos REST em inglês**: `/flows/{flowId}/versions/{version}` + `/executions`; filtros via query (`?status=active`).
- **Workflows persistem domínio via integrações HTTP downstream** — o Orchestrator não tem mais dependência direta com banco de dados.
- **Cache de workflows** no Orchestrator (Redis, TTL 1h, warm-up no startup).
- **Multi-instância de Kafka/RabbitMQ** via `orch-integrations` no `application.yml`, match por `id`.
- **Monitoramento com Portainer** — gerenciamento centralizado de containers via UI web.

## Endpoints — visão geral

**BFF** (todos sob `/bff/...`):

| Endpoint                                              | Método  | Descrição                                |
|-------------------------------------------------------|---------|-------------------------------------------|
| `/bff/health`                                         | GET     | Health público                            |
| `/bff/auth/config`                                    | GET     | Config OAuth2/PKCE para o SPA (público)   |
| `/bff/menu`                                           | GET     | Itens da sidebar (Server Driven UI)       |
| `/bff/features/{featureId}/ui-schema`                 | GET     | Schema JSON da feature                    |
| `/bff/flows?page=&size=&sort=&status=`                | GET     | Lista paginada de fluxos                  |
| `/bff/flows/{flowId}/versions/{version}`              | GET/PUT/DELETE | CRUD de fluxos (proxy ao Manager)  |
| `/bff/flows/{flowId}/versions/{version}/yaml`         | GET     | YAML cru (`application/x-yaml`)           |
| `/bff/flows`                                          | POST    | Cria fluxo (body = YAML)                  |
| `/bff/flows/{flowId}/versions/{version}/executions`   | POST    | Executa fluxo                             |

**Manager**: ver [service-portal-manager/](service-portal-manager/).
**Orchestrator**: ver [generic-orchestrator/](generic-orchestrator/).

## Estrutura do repositório

```
service-portal/
├── docker-compose-service-portal.yml   ← stack completa
├── env.example                          ← copie para .env
├── generic-orchestrator/                ← executor de workflows
│   ├── docker-compose.yml              ← compose isolado
│   └── docs/example-flow.yml           ← workflow de exemplo
├── service-portal-bff/                  ← BFF
│   └── docker-compose.yml              ← compose isolado
├── service-portal-manager/              ← CRUD de workflows
│   ├── docker-compose.yml              ← compose isolado
│   └── mongodb-manager/init-mongo.js   ← init script Mongo (DB service-portal-manager + dados de exemplo)
├── service-portal-frontend/             ← SPA React
│   └── docker-compose.yml              ← compose isolado
└── wiremock/                            ← mappings das APIs simuladas
    ├── mappings/                        ← stubs
    └── __files/                         ← respostas (vazio por padrão)
```

## Testes & cobertura

Todos os módulos têm gate de cobertura ≥ **95%** (JaCoCo nos Java, V8 no
frontend). Para rodar:

```bash
# Cada serviço Java
cd generic-orchestrator && ./gradlew test jacocoTestCoverageVerification
cd service-portal-bff     && ./gradlew test jacocoTestCoverageVerification
cd service-portal-manager && ./gradlew test jacocoTestCoverageVerification

# Frontend
cd service-portal-frontend && npm run coverage
```

Cobertura atual:

| Componente          | Cobertura            |
|---------------------|----------------------|
| generic-orchestrator | ~99% INSTRUCTION     |
| service-portal-bff   | 100% INSTRUCTION     |
| service-portal-manager | 96% INSTRUCTION    |
| service-portal-frontend | 100% lines/branches/functions/statements |

## Documentação adicional

- [PLAN.md](PLAN.md) — Roadmap mestre, decisões e progresso.
- [docs/MAP.md](docs/MAP.md) — Índice para arquitetura, guias e diagnósticos.
