# PLAN: Atualizar testes integrados para cobrir fluxos v1 e v2

## Contexto
Com a implementação do endpoint v2 no `generic-orchestrator` utilizando **Java Virtual Threads**, precisamos garantir paridade funcional entre a execução sequencial (v1) e paralela (v2). Além disso, o script de testes deve servir como uma ferramenta de validação de performance básica para desenvolvedores.

## Objetivos
1.  **Paridade**: Validar que o `status`, `result` e `validations` são idênticos em ambos os endpoints.
2.  **Mensuração**: Medir o tempo de execução de cada rota.
3.  **Asserção de Performance**: Garantir que o v2 é significativamente mais rápido para workflows com múltiplas integrações I/O-bound.

## Escopo

| Arquivo | Mudança |
|---|---|
| `teste-integrado-service-portal-v3.sh` | Refatorar `test_execution` para executar v1 e v2 em loop. |
| `wiremock/mappings/*.json` | Adicionar `fixedDelayMilliseconds` em alguns stubs para simular latência de rede. |
| `TESTES-README.md` | Documentar como interpretar os resultados comparativos. |

## Detalhes Técnicos

### 1. Refatoração do Script Shell
A lógica de execução será extraída para uma função genérica que recebe a versão da API.

```bash
# Protótipo da lógica
execute_and_measure() {
    local version=$1 # "v1" ou "v2"
    local endpoint=$2
    
    local start_time=$(date +%s%3N)
    local response=$(orch_curl -X POST "$endpoint" -d "$payload")
    local end_time=$(date +%s%3N)
    
    local duration=$((end_time - start_time))
    # Armazenar resultado para comparação posterior
}
```

### 2. Comparação Semântica com `jq`
Para evitar falhas por causa de campos dinâmicos (como `executionId` ou timestamps), usaremos o `jq` para comparar apenas o essencial:

```bash
compare_results() {
    # Extrai partes estáveis
    res_v1=$(echo "$BODY_V1" | jq -S '{status, result, validations}')
    res_v2=$(echo "$BODY_V2" | jq -S '{status, result, validations}')
    
    if [ "$res_v1" == "$res_v2" ]; then
        success "Paridade v1/v2 confirmada"
    else
        error "Divergência detectada entre v1 e v2!"
    fi
}
```

### 3. Simulação de Latência no WireMock
Para que o teste de performance faça sentido, o WireMock deve demorar. Atualizaremos o mapping `clients-get.json` e `orders-post.json`:

```json
"response": {
    "status": 200,
    "fixedDelayMilliseconds": 500,
    "jsonBody": { ... }
}
```
Num fluxo com 3 integrações de 500ms:
- **v1 (Sequencial)**: ~1500ms + overhead.
- **v2 (Paralelo)**: ~500ms + overhead.

### 4. Atualização do Relatório
O `CHECKLIST_FILE` ganhará uma tabela comparativa:

| Workflow | Latência v1 | Latência v2 | Speedup | Paridade |
|---|---|---|---|---|
| create-order-v1 | 1540ms | 520ms | 2.96x | ✅ |

## Verificação

1.  **Execução Manual**: Rodar o script e observar se o v2 apresenta tempo reduzido.
2.  **Teste de Regressão**: Alterar propositalmente o código do v2 para retornar um campo diferente e garantir que o script detecta a divergência.
3.  **Logs**: Validar que as chamadas no log do `generic-orchestrator` mostram threads diferentes (`VirtualThread[...]`) para o v2.

## Considerações
- O script deve exigir o `jq` instalado para realizar a comparação de paridade.
- Caso o `jq` não esteja presente, o script deve emitir um `warning` e pular apenas a comparação detalhada, mantendo a verificação de status HTTP.