# Plano de Execução: Monitoramento Avançado (SBA + Jaeger)

## Fase 1: Spring Boot Admin (SBA)

### 1.1 Dependências (BFF, Manager, Orchestrator)
Adicionar ao `build.gradle.kts`:
```kotlin
implementation("de.codecentric:spring-boot-admin-starter-client:3.4.1")
```

### 1.2 Configuração (application.yml)
```yaml
spring:
  boot:
    admin:
      client:
        url: http://spring-boot-admin:8080
        instance:
          name: ${spring.application.name}
          service-url: http://${hostname}:${server.port} # Necessário para o SBA alcançar o container
```

---

## Fase 2: Jaeger (Distributed Tracing)

### 2.1 Dependências (BFF, Manager, Orchestrator)
Spring Boot 3.4 usa Micrometer Tracing. Adicionar:
```kotlin
implementation("io.micrometer:micrometer-tracing-bridge-otel")
implementation("io.opentelemetry:opentelemetry-exporter-otlp")
```

### 2.2 Configuração (application.yml)
```yaml
management:
  tracing:
    sampling:
      probability: 1.0 # Captura todas as requisições em DEV
  otlp:
    tracing:
      endpoint: http://jaeger:4318/v1/traces
```

## Fase 3: Validação

1. **SBA**: Acessar `http://localhost:8085` e verificar se as 3 aplicações aparecem como "UP". Alterar um nível de log via UI e validar no log do container.
2. **Jaeger**: Realizar uma execução v2 (paralela) no Orchestrator via Frontend.
3. Acessar `http://localhost:16686` e buscar por traces do `service-portal-bff`.
4. Verificar se o trace mostra o tempo gasto no Orchestrator e as chamadas paralelas disparadas pelas Virtual Threads.