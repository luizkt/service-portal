# Resumo da Sessão — Diagnóstico de Estabilidade dos Containers

**Data**: 2026-05-16  
**Status**: 🔧 EM PROGRESSO  
**Commit**: ad79a23

---

## 🎯 Objetivo da Sessão

Analisar e resolver problemas de estabilidade dos containers da Service Portal. Containers estavam em estado `unhealthy`: BFF, Manager, Orchestrator, Portainer.

---

## ✅ Progresso

### 1. Análise de Logs (CONCLUÍDO)

Identificados 4 problemas principais:

| Componente | Problema | Root Cause | Status |
|---|---|---|---|
| **Orchestrator** | 401 UNAUTHORIZED ao fazer login no Manager | Endpoint errado: `/api/auth/login` → `/api/auth/tokens` | ✅ Corrigido |
| **Orchestrator** | 401 UNAUTHORIZED ao buscar workflows ativos | Endpoint errado: `/manager/workflows/active` → `/manager/flows?status=active` | 🔧 Corrigido |
| **Orchestrator** | Endpoint YAML com caminho errado | `/manager/workflows/{id}/{v}/yaml` → `/manager/flows/{id}/versions/{v}/yaml` | ✅ Corrigido |

---

## 🔍 Investigação em Andamento

### Problema: Docker Build Cache
... (truncado conforme original)