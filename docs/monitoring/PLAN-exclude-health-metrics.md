# Plano Técnico: Exclusão de Health Checks da Coleta de Métricas

## Contexto
Os serviços `generic-orchestrator`, `service-portal-bff` e `service-portal-manager` expõem métricas via Spring Boot Actuator. O Prometheus faz scrape a cada 15 segundos e os health checks (Docker/SBA) ocorrem com frequência similar.

Por padrão, o Micrometer registra essas chamadas em `http_server_requests_seconds_count`. Isso infla o RPS e distorce a latência média, porque os health checks são rápidos e constantes e mascaram o comportamento real das APIs de negócio. Os mesmos requests também geram spans no Jaeger.

## Objetivo
Ignorar os endpoints `/actuator/**` nas observações HTTP do servidor, para o dashboard do Grafana refletir só chamadas reais de usuário e integrações.

## Decisão técnica

### Por que não há propriedade
O Spring Boot (verificado nos metadados da 4.1.2) não tem propriedade para ignorar URLs. Em `management.metrics.web.server.request` existem só `autotime.*`, `metric-name` e `ignore-trailing-slash`. Uma chave `ignore-patterns` seria ignorada sem erro nem aviso.

### Solução adotada: `ObservationPredicate`
Cada serviço declara um bean `ObservationPredicate` que retorna `false` para observações de `ServerRequestObservationContext` cujo `requestURI` comece com `/actuator`. Uma observação descartada não gera métrica nem span.

| Serviço | Arquivo |
|---|---|
| generic-orchestrator | `src/main/java/com/orchestrator/config/ActuatorObservationConfig.java` |
| service-portal-bff | `src/main/java/com/serviceportal/bff/config/ActuatorObservationConfig.java` |
| service-portal-manager | `src/main/kotlin/com/serviceportal/manager/config/ActuatorObservationConfig.kt` |

### Alternativas descartadas
- `MeterFilter.deny` por tag `uri`: tira só a métrica e mantém os spans do actuator no Jaeger.
- `management.metrics.enable.http.server.requests=false`: remove também as rotas de negócio.
- `metric_relabel_configs` no Prometheus: não altera as aplicações, e as séries continuam sendo geradas.

## Verificação
1. Subir o compose com as 3 imagens reconstruídas.
2. Chamar `/actuator/health` algumas vezes em cada serviço.
3. Em `/actuator/prometheus`, conferir que não existe série `http_server_requests_seconds_count` com `uri` contendo `actuator`, e que rotas de negócio continuam aparecendo.

Resultado em 2026-11-14: nenhuma série de `actuator` nos 3 serviços. O manager mostrou `/manager/flows` e `/api/auth/tokens`.

## Validação no Grafana
- No painel "Throughput (RPM)", o ruído de fundo constante deve cair para perto de zero sem atividade no frontend.

## Impacto
- **Dashboard**: P95 e P99 ficam mais precisos e provavelmente sobem um pouco, pois os health checks puxavam a média para baixo.
- **Prometheus**: menos séries `http_server_requests_*`.
- **Jaeger**: sem spans de `/actuator`.
- **Fora do escopo**: `service-portal-admin` também é alvo de scrape e não foi alterado.

## Entrega
- generic-orchestrator: PR #22
- service-portal-bff: PR #22
- service-portal-manager: PR #20

---
*Status: Implementado e validado localmente. Aguardando merge dos PRs.*
