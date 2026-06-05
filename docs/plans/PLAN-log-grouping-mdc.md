# PLAN: Melhoria de logs: agrupamento por execução de flow (MDC/Tracing)

## Contexto
Com a v2 do `generic-orchestrator` utilizando **Virtual Threads**, várias integrações de um mesmo workflow rodam em paralelo, intercalando logs no console. Sem um identificador de correlação, o debug torna-se impossível.

## Objetivos
1.  **Rastreabilidade**: Garantir que cada linha de log contenha o `executionId`.
2.  **Continuidade**: Propagar o contexto do log da thread principal para as Virtual Threads.
3.  **Observabilidade Externa**: Propagar o ID para sistemas downstream (WireMock/APIs reais).

## Escopo Técnico

### 1. Filtro de Entrada (MDC Filter)
Implementar um `OncePerRequestFilter` que:
- Verifica se o header `X-Execution-Id` existe na request (vindo do BFF).
- Se não existir, gera um `UUID`.
- Coloca no `MDC` (ex: `MDC.put("executionId", id)`).

### 2. Propagação para Virtual Threads (Crucial para v2)
O `MDC` é baseado em `ThreadLocal`. Virtual Threads não herdam `ThreadLocal` por padrão.
- Criar um `TaskDecorator` que captura o contexto MDC da thread original e o injeta na Virtual Thread antes da execução.
- Configurar o `Executor` do `OrchestrationV2Service` para usar este decorator.

### 3. Propagação HTTP (WebClient)
Configurar um `ExchangeFilterFunction` no `WebClient` para injetar automaticamente o `executionId` do MDC em todos os headers de saída.

### 4. Formatação do Log
Atualizar o `logback-spring.xml` ou as propriedades do Spring para incluir o campo:
`%d{yyyy-MM-dd HH:mm:ss} [%X{executionId}] %-5level %logger{36} - %msg%n`

## Plano de Ação

| Passo | Descrição | Classe Sugerida |
|---|---|---|
| 1 | Criar `MdcLogFilter` para interceptar a request. | `com.orchestrator.config.MdcLogFilter` |
| 2 | Implementar `MdcTaskDecorator` para cópia de contexto. | `com.orchestrator.config.MdcTaskDecorator` |
| 3 | Ajustar `OrchestrationV2Service` para decorar as tarefas. | `com.orchestrator.service.OrchestrationV2Service` |
| 4 | Criar `LoggingExchangeFilter` para o WebClient. | `com.orchestrator.config.WebClientConfig` |
| 5 | Atualizar pattern de log em `application.yml`. | `logging.pattern.level` |

## Verificação

1.  **Teste de Concorrência**: Disparar 2 execuções v2 simultâneas e validar no console se as linhas de log de cada integração mantêm o ID correto de sua respectiva execução.
2.  **Downstream**: Validar nos logs do WireMock se o header `X-Execution-Id` está sendo recebido.
3.  **Integridade**: Garantir que o MDC seja limpo (`MDC.clear()`) ao final da request para evitar vazamento de memória/contexto em threads de pool (se houver).

## Considerações de Virtual Threads
Embora as Virtual Threads sejam leves, o uso excessivo de `ThreadLocal` (como o MDC faz) deve ser monitorado. No entanto, para logs de execução de curta duração, o impacto é desprezível frente ao benefício de debug.