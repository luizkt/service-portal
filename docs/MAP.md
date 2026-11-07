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

## 🤖 Índice de agentes (AGENTS.md)
Cada componente tem um `AGENTS.md` na raiz: um índice de cerca de 1.700 tokens com resumo, endpoints, fluxo, mapa de arquivos, "quero mudar... onde" e armadilhas. Leia-o antes de abrir código.

| Componente | Índice | O que é |
|---|---|---|
| Frontend | [service-portal-frontend/AGENTS.md](../service-portal-frontend/AGENTS.md) | SPA React que renderiza menu e telas descritos pelo BFF. Fala só com o BFF. Porta dev 5173 |
| BFF | [service-portal-bff/AGENTS.md](../service-portal-bff/AGENTS.md) | Único ponto de entrada do frontend: valida o JWT do Authentik e faz proxy para Manager e Orchestrator. Porta 8081 |
| Manager | [service-portal-manager/AGENTS.md](../service-portal-manager/AGENTS.md) | CRUD versionado de workflows, contratos, integrações e validações no MongoDB (Kotlin). Porta 8082 |
| Orchestrator | [generic-orchestrator/AGENTS.md](../generic-orchestrator/AGENTS.md) | Executa fluxos YAML (HTTP e filas), com cache Redis dos workflows do Manager. Porta 8080 |
| Admin | [service-portal-admin/AGENTS.md](../service-portal-admin/AGENTS.md) | Spring Boot Admin: painel de monitoramento dos serviços. Porta 8085 |

Frontend, BFF, Manager e Orchestrator são repositórios git próprios: os links acima funcionam com os clones lado a lado, como neste diretório.

### Manter os índices atualizados
- Método, medições e decisões: [PLAN-repo-indexing.md](plans/PLAN-repo-indexing.md).
- Ferramenta: `scripts/repo-index.py` com os comandos `inventory`, `check` e `write`.
- Em cada componente: skill `update-agents-index` (`.claude/skills/`), `CLAUDE.md` mandando usá-la e hook `.githooks/pre-commit` que bloqueia código de produção sem o `AGENTS.md`. Ative o hook uma vez por clone com `git config core.hooksPath .githooks`.

---
*Última atualização: Novembro 2026*