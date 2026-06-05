# PLAN: Telas de gerenciamento de contratos, integrações e validações

## Contexto

As collections `contracts`, `integrations` e `validations` foram criadas no Manager na sessão de modularização de workflows, mas ainda não há telas para gerenciá-las. O BFF não tem proxy para esses recursos nem itens de menu correspondentes. Usuários precisam chamar as APIs do Manager diretamente — o que vai contra o padrão Server Driven UI do projeto.

O objetivo é expor os 3 recursos via BFF e criar os componentes React seguindo exatamente o padrão já estabelecido pelo `FlowManager`.

---

## Regras de acesso por recurso

| Recurso | ADMIN (it) | RULES (bizop) | WORKFLOWS (workop) |
|---|---|---|---|
| `integrations` | CRUD completo | sem acesso | somente leitura |
| `contracts` | CRUD completo | somente leitura | CRUD completo |
| `validations` | CRUD completo | CRUD completo | sem acesso |

**Impacto no menu (itens visíveis por grupo):**

| Item de menu | Grupos que o enxergam |
|---|---|
| `integration-manager` | ADMIN, WORKFLOWS |
| `contract-manager` | ADMIN, RULES, WORKFLOWS |
| `validation-manager` | ADMIN, RULES |

---

## Escopo

### BFF (`service-portal-bff`)

| Arquivo | Mudança |
|---|---|
| `controller/BffMenuController.java` | +3 itens em `ALL_ITEMS` + 3 cases em `uiSchema()` |
| `client/ManagerClient.java` | +3 conjuntos de métodos (integrations, contracts, validations) |
| `controller/IntegrationProxyController.java` | **Novo** — proxy `/bff/integrations` → Manager |
| `controller/ContractProxyController.java` | **Novo** — proxy `/bff/contracts` → Manager |
| `controller/ValidationProxyController.java` | **Novo** — proxy `/bff/validations` → Manager |
| Testes | `BffMenuControllerTest.java`, `ManagerClientTest.java`, + 3 novos controller tests |

### Frontend (`service-portal-frontend`)

| Arquivo | Mudança |
|---|---|
| `src/api/bff.ts` | +3 namespaces (integrations, contracts, validations) |
| `src/types/index.ts` | +3 interfaces DTO (IntegrationDefinition, ContractDefinition, ValidationDefinition) |
| `src/components/features/IntegrationManager/IntegrationManager.tsx` | **Novo** |
| `src/components/features/ContractManager/ContractManager.tsx` | **Novo** |
| `src/components/features/ValidationManager/ValidationManager.tsx` | **Novo** |
| `src/components/ComponentRenderer/ComponentRenderer.tsx` | +3 entradas no `componentMap` |
| Testes | `bff.test.ts` atualizado + 3 novos arquivos de teste de componentes |

---

## Implementação passo a passo

### Fase 1 — BFF: ManagerClient

Adicionar ao `ManagerClient.java` 3 conjuntos de métodos espelhando os métodos de flows já existentes:

**Integrations** (endpoints Manager: `/manager/integrations`):
- `listIntegrations(page, size, sort, status)`
- `getIntegration(integrationId, version)`
- `createIntegration(body)` → POST, retorna 201
- `updateIntegration(integrationId, version, body)` → PUT, retorna 201 + Location
- `deleteIntegration(integrationId, version)` → DELETE, retorna 204
- `listIntegrationVersions(integrationId, status)`

**Contracts** (endpoints Manager: `/manager/contracts`):
- Mesmos 6 métodos, substituindo `Integration` por `Contract` e `integrationId` por `contractId`

**Validations** (endpoints Manager: `/manager/validations`):
- Mesmos 6 métodos, substituindo por `Validation` e `validationId`

Padrão de implementação (copiar dos métodos de flows existentes):
```java
public Object listIntegrations(int page, int size, String sort, String status) {
    return managerWebClient.get()
        .uri(uri -> uri.path("/manager/integrations")
            .queryParam("page", page)
            .queryParam("size", size)
            .queryParamIfPresent("sort", Optional.ofNullable(sort))
            .queryParamIfPresent("status", Optional.ofNullable(status))
            .build())
        .header(HttpHeaders.AUTHORIZATION, authHeader())
        .retrieve()
        .bodyToMono(Object.class)
        .block();
}
```

### Fase 2 — BFF: Proxy Controllers

#### `IntegrationProxyController.java`

```java
@RestController
@RequestMapping("/bff/integrations")
public class IntegrationProxyController {

    // GET (list, get, versions): ADMIN + WORKFLOWS
    @GetMapping
    @PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS')")
    public ResponseEntity<Object> list(...) { ... }

    @GetMapping("/{integrationId}/versions/{version}")
    @PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS')")
    public ResponseEntity<Object> get(...) { ... }

    @GetMapping("/{integrationId}/versions")
    @PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS')")
    public ResponseEntity<Object> listVersions(...) { ... }

    // WRITE: somente ADMIN
    @PostMapping
    @PreAuthorize("hasAuthority('ADMIN')")
    public ResponseEntity<Object> create(...) { ... }

    @PutMapping("/{integrationId}/versions/{version}")
    @PreAuthorize("hasAuthority('ADMIN')")
    public ResponseEntity<Object> update(...) { ... }

    @DeleteMapping("/{integrationId}/versions/{version}")
    @PreAuthorize("hasAuthority('ADMIN')")
    public ResponseEntity<Object> delete(...) { ... }
}
```

#### `ContractProxyController.java`

```java
@RestController
@RequestMapping("/bff/contracts")
public class ContractProxyController {

    // GET: todos os grupos
    @GetMapping
    @PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS', 'RULES')")
    // ...

    // WRITE: ADMIN + WORKFLOWS
    @PostMapping
    @PreAuthorize("hasAnyAuthority('ADMIN', 'WORKFLOWS')")
    // ...
}
```

#### `ValidationProxyController.java`

```java
@RestController
@RequestMapping("/bff/validations")
public class ValidationProxyController {

    // GET: ADMIN + RULES
    @GetMapping
    @PreAuthorize("hasAnyAuthority('ADMIN', 'RULES')")
    // ...

    // WRITE: ADMIN + RULES
    @PostMapping
    @PreAuthorize("hasAnyAuthority('ADMIN', 'RULES')")
    // ...
}
```

### Fase 3 — BFF: Menu e UI Schema

#### `BffMenuController.java` — adicionar 3 itens em `ALL_ITEMS`:

```java
private static final List<MenuItemDto> ALL_ITEMS = List.of(
    MenuItemDto.builder()        // existente
        .id("flow-manager")
        .label("Gerenciador de Fluxos")
        .icon("workflow")
        .uiSchemaUrl("/bff/features/flow-manager/ui-schema")
        .requiredGroup("ADMIN").requiredGroup("WORKFLOWS")
        .build(),
    MenuItemDto.builder()        // novo
        .id("integration-manager")
        .label("Integrações")
        .icon("integration")
        .uiSchemaUrl("/bff/features/integration-manager/ui-schema")
        .requiredGroup("ADMIN").requiredGroup("WORKFLOWS")
        .build(),
    MenuItemDto.builder()        // novo
        .id("contract-manager")
        .label("Contratos")
        .icon("contract")
        .uiSchemaUrl("/bff/features/contract-manager/ui-schema")
        .requiredGroup("ADMIN").requiredGroup("WORKFLOWS").requiredGroup("RULES")
        .build(),
    MenuItemDto.builder()        // novo
        .id("validation-manager")
        .label("Validações")
        .icon("validation")
        .uiSchemaUrl("/bff/features/validation-manager/ui-schema")
        .requiredGroup("ADMIN").requiredGroup("RULES")
        .build()
);
```

#### `BffMenuController.java` — adicionar 3 cases em `uiSchema()`:

```java
case "integration-manager" -> UiSchemaDto.builder()
    .type("integration-manager")
    .title("Gerenciamento de Integrações")
    .build();
case "contract-manager" -> UiSchemaDto.builder()
    .type("contract-manager")
    .title("Gerenciamento de Contratos")
    .build();
case "validation-manager" -> UiSchemaDto.builder()
    .type("validation-manager")
    .title("Gerenciamento de Validações")
    .build();
```

### Fase 4 — Frontend: tipos e cliente

#### `src/types/index.ts` — adicionar 3 interfaces:

```typescript
export interface IntegrationDefinition {
  integrationId: string;
  version: number;
  type: string;
  url: string;
  method: string;
  headers: Record<string, string>;
  timeout: number;
  bodyTemplate: string | null;
  responseBody: Record<string, unknown> | null;
  active: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ContractDefinition {
  contractId: string;
  version: number;
  active: boolean;
  fields: ContractField[];
  createdAt: string;
  updatedAt: string;
}

export interface ContractField {
  name: string;
  type: string;
  required: boolean;
  validations: FieldValidation[];
}

export interface FieldValidation {
  type: string;
  value?: string;
  message?: string;
}

export interface ValidationDefinition {
  validationId: string;
  version: number;
  type: string;
  url: string;
  method: string;
  headers: Record<string, string>;
  timeout: number;
  bodyTemplate: string | null;
  responseBody: Record<string, unknown> | null;
  active: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ResourcePage<T> {
  content: T[];
  totalElements: number;
  totalPages: number;
  number: number;
  size: number;
}
```

#### `src/api/bff.ts` — adicionar 3 namespaces seguindo o padrão de `bff.flows`:

```typescript
integrations: {
  list: (page = 0, size = 20) =>
    request<ResourcePage<IntegrationDefinition>>(`/bff/integrations?page=${page}&size=${size}`),
  get: (integrationId: string, version: number) =>
    request<IntegrationDefinition>(`/bff/integrations/${integrationId}/versions/${version}`),
  listVersions: (integrationId: string, status?: string) =>
    request<IntegrationDefinition[]>(`/bff/integrations/${integrationId}/versions${status ? `?status=${status}` : ''}`),
  create: (body: unknown) =>
    request<IntegrationDefinition>('/bff/integrations', { method: 'POST', body: JSON.stringify(body) }),
  update: (integrationId: string, version: number, body: unknown) =>
    request<IntegrationDefinition>(`/bff/integrations/${integrationId}/versions/${version}`, { method: 'PUT', body: JSON.stringify(body) }),
  delete: (integrationId: string, version: number) =>
    request<void>(`/bff/integrations/${integrationId}/versions/${version}`, { method: 'DELETE' }),
},
// Mesma estrutura para contracts e validations
```

### Fase 5 — Frontend: componentes

Os 3 componentes seguem o padrão do `FlowManager`. Cada um implementa:

- **Views:** `list` | `create` | `detail` | `versions`
- **Estado:** `view`, `items`, `selected`, `loading`, `error`
- **Props:** `{ schema: UiSchema }` — contrato idêntico ao FlowManager

**IntegrationManager** e **ValidationManager** são quase idênticos (mesma forma: url, method, headers, timeout, bodyTemplate, responseBody). Diferem apenas no nome do campo ID (`integrationId` vs `validationId`).

**ContractManager** tem formulário diferente — campos estruturados (name, type, required, validations[]) em vez de URL/método.

Para todos os 3:
- Listagem com tabela: ID, versão, ativo, data de criação
- Formulário de criação via JSON (mesmo padrão do FlowManager com YAML — aqui JSON)
- Detalhe mostrando todos os campos
- Histórico de versões (`GET /{id}/versions`)
- Botão de desativar (soft delete)
- Mensagem de 403 quando BFF bloqueia pela autorização

#### `ComponentRenderer.tsx` — adicionar 3 entradas:

```typescript
import { IntegrationManager } from '../features/IntegrationManager/IntegrationManager';
import { ContractManager } from '../features/ContractManager/ContractManager';
import { ValidationManager } from '../features/ValidationManager/ValidationManager';

const componentMap: Record<string, React.ComponentType<{ schema: UiSchema }>> = {
  'flow-manager': FlowManager,
  'integration-manager': IntegrationManager,
  'contract-manager': ContractManager,
  'validation-manager': ValidationManager,
};
```

---

## Arquivos críticos

### BFF

| Arquivo | Função chave |
|---|---|
| `controller/BffMenuController.java` | `ALL_ITEMS` (lista estática) + `uiSchema()` (switch-case) |
| `client/ManagerClient.java` | Métodos `listFlows`, `getFlow` etc. — base para os 18 novos métodos |
| `controller/FlowProxyController.java` | Modelo de proxy a ser replicado 3x |

### Frontend

| Arquivo | Função chave |
|---|---|
| `src/components/features/FlowManager/FlowManager.tsx` | Modelo de componente a ser replicado |
| `src/components/ComponentRenderer/ComponentRenderer.tsx` | `componentMap` — registro de features |
| `src/api/bff.ts` | Namespace `bff.flows` — base para 3 novos namespaces |
| `src/types/index.ts` | `FlowDefinition`, `FlowsPage` — base para novos tipos |

---

## Ordem de implementação recomendada

1. `ManagerClient.java` — métodos de integrations/contracts/validations
2. `IntegrationProxyController.java`, `ContractProxyController.java`, `ValidationProxyController.java`
3. `BffMenuController.java` — itens de menu + UI schemas
4. Testes BFF (controller tests + ManagerClientTest atualizado + BffMenuControllerTest com novos grupos)
5. `src/types/index.ts` — novos DTOs
6. `src/api/bff.ts` — novos namespaces
7. `IntegrationManager.tsx`, `ValidationManager.tsx` (similares — fazer juntos)
8. `ContractManager.tsx` (formulário diferente)
9. `ComponentRenderer.tsx` — registrar os 3
10. Testes frontend

---

## Verificação

1. **Login como `it` (ADMIN)** → sidebar deve exibir 4 itens (flow-manager + os 3 novos)
2. **Login como `bizop` (RULES)** → sidebar deve exibir apenas `contract-manager` e `validation-manager`
3. **Login como `workop` (WORKFLOWS)** → sidebar deve exibir `flow-manager`, `integration-manager` e `contract-manager`
4. **Criar uma integration como ADMIN** → deve retornar 201 e aparecer na lista
5. **Tentar criar integration como `bizop`** → deve retornar 403
6. **Tentar acessar validation-manager como `workop`** → menu não deve exibir o item; chamada direta deve retornar 403
7. **Build e testes:**
   ```bash
   cd service-portal-bff && ./gradlew test
   cd service-portal-frontend && npm test
   ```
