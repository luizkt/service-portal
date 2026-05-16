# Testes Integrados - Service Portal

## 📋 Visão Geral

O Service Portal possui um suite de testes integrados que validam:
- ✅ Health checks de infraestrutura (BFF, Manager, Orchestrator, Redis, RabbitMQ)
- ✅ Server Driven UI (endpoints de menu e schema)
- ✅ CRUD de Workflows (criar, listar, buscar, obter YAML)
- ✅ Execução de Workflows (HTTP, RabbitMQ, Kafka)
- ✅ Cenários negativos (validação, workflows inexistentes)

---

## 🚀 Como Executar

### Pré-requisitos
```bash
# Instalar ferramentas necessárias
docker              # versão 20.10+
curl                # para requisições HTTP
jq                  # (opcional) para parsing JSON
bash                # para executar scripts
```

### Execução Básica
```bash
# Versão 1 (Original - requer correções)
./teste-integrado-service-portal.sh

# Versão 2 (Melhorada com autenticação)
./teste-integrado-service-portal-v2.sh
```

### Saída do Teste
```
[Timestamp] ✓ Teste passou
[Timestamp] ✗ Teste falhou
[Timestamp] ⚠ Teste pulado/warning

[2026-05-16 20:42:34] ║ Total:        20                         ║
[2026-05-16 20:42:34] ║ ✓ Passou:     15                        ║
[2026-05-16 20:42:34] ║ ✗ Falhou:     3                        ║
[2026-05-16 20:42:34] ║ ⚠ Pulados:    2                        ║
[2026-05-16 20:42:34] ║ Taxa:         75%                      ║
```

---

## 📁 Arquivos de Diagnóstico

### Documentos Criados na Sessão (2026-05-16)

1. **DIAGNOSTICO-TESTES-INTEGRADOS.md**
   - Análise detalhada de cada falha
   - Identificação de causas raiz
   - Recomendações de correção

2. **RECOMENDACOES-TESTES-INTEGRADOS.md**
   - Plano de ação com 5 fases
   - Procedimentos de validação
   - Checklist de implementação

3. **teste-integrado-service-portal-v2.sh**
   - Script melhorado com suporte a autenticação
   - Logging detalhado (DEBUG)
   - Error handling robusto

4. **TESTES-README.md** (Este arquivo)
   - Documentação de uso
   - Troubleshooting
   - FAQ

---

## 🔍 Problemas Conhecidos e Soluções

### ❌ Problema: RabbitMQ não responde ao healthcheck

**Sintoma**: `RabbitMQ não respondendo` no teste 1.4

**Causa**: Endpoint `/api/health` não existe em RabbitMQ

**Solução**: Usar endpoint correto
```bash
# Incorreto:
curl http://guest:guest@localhost:15672/api/health

# Correto:
curl http://guest:guest@localhost:15672/api/aliveness-test/%2F
```

**Status**: ⏳ Aguardando correção em `teste-integrado-service-portal.sh`

---

### ❌ Problema: Endpoints BFF retornam erro

**Sintoma**: `Menu não contém 'flow-manager'` em testes 2.1-2.2

**Causa**: 
- Endpoints podem não estar implementados
- Ou requerem autenticação

**Verificação**:
```bash
# Ver todos os endpoints disponíveis
curl http://localhost:8081/actuator/mappings | jq '.contexts.application.mappings.servletHandlerMappings[] | {handler: .handler}' | grep -i "bff\|menu\|feature"

# Testar acesso direto
curl -v http://localhost:8081/bff/menu
```

**Status**: 🔍 Requer investigação (Ver RECOMENDACOES-TESTES-INTEGRADOS.md - Ação 1)

---

### ❌ Problema: 401 Unauthorized em criação de workflows

**Sintoma**: `Workflow HTTP — HTTP 401` em testes de criação

**Causa**: BFF/Manager requer autenticação (Bearer token)

**Solução**: Usar script v2 que implementa autenticação
```bash
./teste-integrado-service-portal-v2.sh
```

**Manual**: Obter token e incluir em requests
```bash
# Obter token Manager
TOKEN=$(curl -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.token')

# Usar em requests
curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/manager/flows
```

**Status**: ✅ Script v2 implementa automaticamente

---

## 📊 Interpretação dos Resultados

### Taxa de Sucesso Esperada

| Taxa | Status | Ação |
|------|--------|------|
| **80-100%** | ✅ OK | Nenhuma - sistema estável |
| **50-79%** | ⚠️ AVISO | Investigar problemas conhecidos |
| **20-49%** | ❌ CRÍTICO | Sistema parcialmente funcional |
| **0-19%** | 🔴 FALHA | Sistema não está pronto |

### Análise por Seção

```
1. SAÚDE DO SISTEMA
   - Esperado: 5/5 passes
   - Status: 4/5 (RabbitMQ é opcional)
   
2. SERVER DRIVEN UI
   - Esperado: 2/2 passes
   - Status: 0/2 (requer investigação)
   
3. CRIAÇÃO DE WORKFLOWS
   - Esperado: 3/3 passes
   - Status: 0/3 (requer autenticação)
   
4. CRUD DE WORKFLOWS
   - Esperado: 3/3 passes
   - Status: 0/3 (depende de criação)
   
5. EXECUÇÃO DE WORKFLOWS
   - Esperado: 3/3 passes
   - Status: 0/3 (depende de criação)
   
6. CENÁRIOS NEGATIVOS
   - Esperado: 3/3 passes
   - Status: 0/3 (requer autenticação)
```

---

## 🛠️ Troubleshooting

### Teste falha com "docker: command not found"

**Solução**: Instalar Docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### Teste falha com "curl: command not found"

**Solução**: Instalar curl
```bash
# Ubuntu/Debian
sudo apt-get install curl

# macOS
brew install curl

# Alpine
apk add curl
```

### Teste falha com "jq: command not found"

**Solução**: Instalar jq (opcional, alguns testes usam)
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Alpine
apk add jq
```

### Teste fica preso em "Aguardando BFF na porta 8081"

**Solução**: Verificar logs do container
```bash
# Ver últimos 50 linhas de logs
docker compose logs bff | tail -50

# Se problema persistir, reiniciar:
docker compose restart bff
```

### Taxa de sucesso baixa (< 50%)

**Passos de Diagnóstico**:
```bash
# 1. Verificar status dos containers
docker compose ps

# 2. Verificar se não há erros em logs
docker compose logs | grep -i error

# 3. Verificar conectividade entre serviços
docker compose exec bff curl http://manager:8082/actuator/health

# 4. Recriar ambiente limpo
docker compose down -v
docker compose up -d
sleep 60
./teste-integrado-service-portal-v2.sh
```

---

## 📚 Documentação Relacionada

### Diagnósticos da Sessão Atual (2026-05-16)

- **DIAGNOSTICO-ESTABILIDADE.md** — Problemas de autenticação no Orchestrator (Phase 1)
- **DIAGNOSTICO-MANAGER-401.md** — Análise do Manager (Phase 2)
- **DIAGNOSTICO-HEALTHCHECK-CURL.md** — Problema de curl em Dockerfiles (Phase 3-4)
- **DIAGNOSTICO-TESTES-INTEGRADOS.md** — Problemas nos testes (novo)
- **RESUMO-SESSAO-ESTABILIDADE-COMPLETO.md** — Resumo completo da sessão

### Arquivos do Sistema

- **docker-compose-service-portal.yml** — Configuração da infraestrutura
- **env.example** — Variáveis de ambiente de exemplo
- **PLAN.md** — Roadmap do projeto

---

## 🔄 Próximas Etapas

### Imediatas (Esta Semana)
- [ ] Executar checklist de investigação (RECOMENDACOES-TESTES-INTEGRADOS.md - Ação 1-2)
- [ ] Documentar findings em novo arquivo
- [ ] Corrigir RabbitMQ endpoint (Ação 4)

### Curto Prazo (Próxima Semana)
- [ ] Implementar autenticação nos testes
- [ ] Atualizar script v1 com correções
- [ ] Validar taxa de sucesso ≥ 80%

### Médio Prazo (Próximo Sprint)
- [ ] Migrar para script v2 como padrão
- [ ] Adicionar testes ao CI/CD
- [ ] Documentar endpoints BFF no README principal

---

## 💡 Dicas Úteis

### Executar teste específico manualmente
```bash
# Health checks apenas
docker compose logs
curl http://localhost:8081/bff/health
curl http://localhost:8080/actuator/health
curl http://localhost:8082/actuator/health

# Criação de workflow
TOKEN=$(curl -X POST http://localhost:8082/api/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.token')

curl -X POST http://localhost:8082/manager/flows \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d @workflow.json
```

### Gerar relatório customizado
```bash
# Apenas failed tests
grep "✗" teste-integrado-*.log

# Apenas warnings
grep "⚠" teste-integrado-*.log

# Extrato de erro específico
cat teste-integrado-*.log | grep -A 5 "não respondendo"
```

### Limpar dados de teste (reset)
```bash
# Parar todos os containers
docker compose down

# Remover volumes (dados persistentes)
docker compose down -v

# Reiniciar limpo
docker compose up -d
sleep 60
./teste-integrado-service-portal-v2.sh
```

---

## 📞 Suporte

Para problemas ou dúvidas:
1. Consultar documentos de diagnóstico neste diretório
2. Verificar logs em `teste-integrado-*.log`
3. Consultar RECOMENDACOES-TESTES-INTEGRADOS.md para próximas ações

---
