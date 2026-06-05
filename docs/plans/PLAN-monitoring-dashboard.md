# Plano de Execução: Dashboard de Monitoramento (Grafana)

## Fase 1: Configuração do Scrape (Prometheus)
Precisamos garantir que o Prometheus consiga ler os dados de cada container.

**Arquivo: `prometheus/prometheus.yml`**
```yaml
scrape_configs:
  - job_name: 'service-portal'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: 
          - 'portal-bff:8081'
          - 'portal-manager:8082'
          - 'portal-orchestrator:8080'
```

## Fase 2: Estrutura do Dashboard no Grafana

### 2.1 Variável de Filtro
- **Nome**: `service`
- **Query**: `label_values(up, job)` ou manual com as labels dos containers.

### 2.2 Painéis de Recursos (Infra)
- **CPU**: `system_cpu_usage{job="$service"}` (Gauge e Graph)
- **Memória**: `jvm_memory_used_bytes{job="$service", area="heap"}` (Graph)
- **Disco**: `disk_free_bytes{job="$service"} / disk_total_bytes{job="$service"}` (Gauge %)

### 2.3 Painéis de Tráfego (RPM)
- **Requisições por Minuto**: `rate(http_server_requests_seconds_count{job="$service"}[1m]) * 60`

### 2.4 Painéis de Performance (Latência)
- **Média**: `rate(http_server_requests_seconds_sum{job="$service"}[5m]) / rate(http_server_requests_seconds_count{job="$service"}[5m])`
- **P95**: `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job="$service"}[5m])))`
- **P99**: `histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{job="$service"}[5m])))`

### 2.5 Painéis de Saúde (Status)
- **Sucesso (2xx)**: `sum(rate(http_server_requests_seconds_count{job="$service", status=~"2.."}[5m]))`
- **Erros do Cliente (4xx)**: `sum(rate(http_server_requests_seconds_count{job="$service", status=~"4.."}[5m]))`
- **Erros do Servidor (5xx)**: `sum(rate(http_server_requests_seconds_count{job="$service", status=~"5.."}[5m]))`

## Fase 3: Implementação

1. **Habilitar Endpoints**: Adicionar a dependência do `micrometer-registry-prometheus` em todos os serviços Java/Kotlin.
2. **Configuração YAML**: Garantir que `management.endpoints.web.exposure.include` contenha `prometheus`.
3. **Provisioning**: Criar os arquivos em `./grafana/provisioning/dashboards` para que o painel já suba pronto no `docker compose up`.

## Fase 4: Validação
1. Abrir `http://localhost:3000` (Grafana).
2. Selecionar o serviço `portal-orchestrator`.
3. Realizar chamadas via Frontend.
4. Validar se o RPM e os percentis (P95/P99) refletem o delay simulado no WireMock (que configuramos para 500ms nos testes integrados).

---
*Nota: Para o Orquestrador, usaremos métricas específicas para monitorar o pool de **Virtual Threads**.*