# PLAN: Exibir mapa `validations` no resultado de execução (Frontend)

## Contexto

O orquestrador já retorna o campo `validations` na resposta de execução — ele é serializado no `OrchestrationResponse`, passa pelo BFF como `Map<String, Object>` sem alteração, e chega no frontend. No entanto, o frontend ignora completamente esse campo:

1. O tipo TypeScript `OrchestrationResponse` não define `validations`
2. O componente `FlowManager.tsx` renderiza somente `execResult.result`

O objetivo é exibir o mapa `validations` na view de execução, lado a lado com `result`, seguindo o padrão visual já existente (v1 Sequencial / v2 Paralelo).

---

## Diagnóstico

| Camada | Campo `validations` | Status |
|---|---|---|
| Orquestrador (`OrchestrationResponse.java`) | `Map<String, Object> validations` | ✅ Presente |
| BFF (`OrchestratorClient.java`) | Passa como `Map<String, Object>` | ✅ Transparente |
| Frontend tipo (`types/index.ts`) | **Não definido** | ❌ Ausente |
| Frontend render (`FlowManager.tsx`) | **Não renderizado** | ❌ Ignorado |

---

## Escopo

| Arquivo | Mudança |
|---|---|
| `service-portal-frontend/src/types/index.ts` | Adicionar `validations?: Record<string, unknown>` à interface `OrchestrationResponse` |
| `service-portal-frontend/src/components/features/FlowManager/FlowManager.tsx` | Renderizar `execResult.validations` na view de execução |
| `service-portal-frontend/src/components/features/FlowManager/FlowManager.css` | Ajustar grid se necessário |
| Testes | `FlowManager.test.tsx` — adicionar caso com `validations` |

---

## Implementação

### 1. `src/types/index.ts`

```typescript
// ANTES
export interface OrchestrationResponse {
  executionId: string
  flowId: string
  status: string
  result: Record<string, unknown>
  errorMessage?: string
  startedAt: string
  finishedAt: string
}

// DEPOIS — adicionar campo validations
export interface OrchestrationResponse {
  executionId: string
  flowId: string
  status: string
  result: Record<string, unknown>
  validations?: Record<string, unknown>    // ← novo
  errorMessage?: string
  startedAt: string
  finishedAt: string
}
```

### 2. `FlowManager.tsx` — view de execução

A view de execução atual (para v1 e v2) renderiza:
- Status, executionId, errorMessage
- `result` como JSON em `<pre>`

Adicionar bloco condicional após o bloco de `result`:

```tsx
{/* Resultado das integrações */}
<div className="fm-exec-section">
  <h4>Resultado das integrações</h4>
  <pre className="fm-exec-result">
    {JSON.stringify(execResult.result, null, 2)}
  </pre>
</div>

{/* Resultado das validações — exibir apenas quando presente e não vazio */}
{execResult.validations && Object.keys(execResult.validations).length > 0 && (
  <div className="fm-exec-section">
    <h4>Resultado das validações</h4>
    <pre className="fm-exec-result fm-exec-validations">
      {JSON.stringify(execResult.validations, null, 2)}
    </pre>
  </div>
)}
```

O mesmo bloco deve ser aplicado ao resultado do `execResultV2` (v2 paralelo).

### 3. `FlowManager.css` (se necessário)

Adicionar estilo para diferenciar visualmente o bloco de validações do de integrações:

```css
.fm-exec-section {
  margin-top: 12px;
}

.fm-exec-section h4 {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--text-secondary, #666);
  margin-bottom: 4px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.fm-exec-validations {
  border-left: 3px solid #f59e0b; /* âmbar para diferenciar de result */
  padding-left: 8px;
}
```

---

## Arquivos críticos

| Arquivo | Linha relevante |
|---|---|
| `src/types/index.ts` | Interface `OrchestrationResponse` (~linha 34) |
| `src/components/features/FlowManager/FlowManager.tsx` | Seção de renderização de `execResult` (~linha 364) |
| `generic-orchestrator/src/main/java/com/orchestrator/dto/OrchestrationResponse.java` | Campo `validations` já existe — não alterar |

---

## Verificação

1. **Executar um fluxo com validações** (ex: `create-order-v1` com dados de exemplo do init-mongo após pendência #5):
   ```bash
   curl -X POST "http://localhost:8081/bff/flows/create-order-v1/versions/1.0.0/executions" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"clientId":"ABC123","amount":150.00}'
   ```
   → A resposta JSON deve conter o campo `validations` com resultado de `check-credit-limit`

2. **Na UI do FlowManager** (via browser em `http://localhost:5173`):
   - Login como `it` (ADMIN)
   - Abrir `flow-manager` → selecionar `create-order-v1` → aba de execução
   - Executar com `{"clientId":"ABC123","amount":150}`
   - Validar que aparece a seção "Resultado das validações" com o JSON de retorno

3. **Executar testes:**
   ```bash
   cd service-portal-frontend && npm test
   ```
   → Todos os testes devem continuar passando; adicionar caso que verifica renderização de `validations`

4. **Caso sem validações** (workflow que não define a seção `validations`): a seção não deve aparecer (condicional `&& Object.keys(...).length > 0`)
