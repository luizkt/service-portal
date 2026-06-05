# Mapa de Documentação do Projeto

Este documento serve como índice para toda a documentação técnica do Service Portal.

## 🚀 Roadmap e Status
- [PLAN.md](../PLAN.md): Roadmap mestre, decisões arquiteturais e controle de tarefas concluídas.

## 📋 Planos de Execução (`docs/plans/`)
- Monitoramento: SBA + Jaeger
- Monitoramento: Dashboards Grafana
- Observabilidade: Agrupamento de Logs (MDC)
- UX/UI: Unificação de Layout
- Infra: Dados de Exemplo MongoDB

## 📊 Monitoramento (`docs/monitoring/`)
- Prometheus Config: Regras de coleta.
- Grafana Provisioning: Configuração de data sources.
- Dashboards JSON: Definições visuais dos painéis.

## � Diagnósticos e Incidentes (`docs/diagnostics/`)
- Padrão de Nomenclatura
- Template de Diagnóstico
- Healthcheck Curl
- Manager 401 Unauthorized
- Resumo Sessão Estabilidade

## 🏗️ Arquitetura e Testes
- Arquitetura Geral
- Cenários de Teste Integrado

## 🤖 Agentes (AGENTS.md)
Cada componente possui um arquivo `AGENTS.md` na sua respectiva pasta com instruções específicas para o desenvolvimento:
- BFF
- Manager
- Orchestrator
- Frontend

---
*Última atualização: Junho 2026*