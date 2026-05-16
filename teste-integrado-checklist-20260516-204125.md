# Relatório de Testes Integrados - Service Portal

Data: Sat May 16 08:42:34 PM -03 2026

## Resumo
- Total de testes: 27
- ✓ Passou: 12
- ✗ Falhou: 8
- ⚠ Pulados: 7
- Taxa de sucesso: 44%

## Arquivos de log
- Log detalhado: teste-integrado-20260516-204125.log
- Resultados: teste-integrado-results-20260516-204125.txt

## Checklist de Execução

### Saúde do Sistema
- [x] Health do BFF
- [x] Health do Orquestrador
- [x] Health do Manager
- [x] RabbitMQ acessível
- [x] Redis acessível

### Server Driven UI
- [x] Menu retornado
- [x] Schema da feature retornado

### CRUD de Workflows
- [x] Listar workflows
- [x] Buscar workflow específico
- [x] Obter YAML

### Execução de Workflows
- [x] Workflow HTTP
- [x] Workflow RabbitMQ
- [x] Workflow Kafka

### Cenários Negativos
- [x] Validação de contrato
- [x] Workflow inexistente
- [x] Versão inexistente

