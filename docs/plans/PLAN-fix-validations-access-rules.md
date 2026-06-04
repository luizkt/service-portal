# PLAN: Corrigir regras de acesso no Manager para `validations`

## Contexto

Durante a sessão de modularização de workflows, a regra de acesso para a collection `validations` foi definida incorretamente no comentário do `ValidationController.kt`. O comentário diz "RULES (bizop): leitura apenas", mas a regra correta é **RULES (bizop): CRUD completo**.

A tabela correta de acesso é:

| Collection | ADMIN (it) | RULES (bizop) | WORKFLOWS (workop) |
|---|---|---|---|
| `integrations` | CRUD | sem acesso | somente leitura |
| `contracts` | CRUD | somente leitura | CRUD |
| `validations` | CRUD | **CRUD completo** ← corrigir | sem acesso |

> **Importante:** O enforcement real via `@PreAuthorize` será feito no BFF no momento em que os endpoints proxy `/bff/validations` forem criados (pendência #4). O que muda agora é apenas a documentação no código — o comentário está desatualizado e será a referência usada na implementação futura.

---

## Escopo

| Arquivo | Mudança |
|---|---|
| `service-portal-manager/src/.../controller/ValidationController.kt` | Corrigir comentário: RULES → CRUD completo |

Nenhuma alteração de lógica, anotações, testes ou outros arquivos. É uma correção de documentação inline.

---

## Implementação

### Arquivo: `ValidationController.kt`

**Localização:** `service-portal-manager/src/main/kotlin/com/serviceportal/manager/controller/ValidationController.kt`

```kotlin
// ANTES (incorreto)
/**
 * Acesso (aplicado pelo BFF via @PreAuthorize ao proxy):
 *   - ADMIN (it)        : CRUD completo
 *   - RULES (bizop)     : leitura apenas     ← ERRADO
 *   - WORKFLOWS (workop): sem acesso
 */

// DEPOIS (correto)
/**
 * Acesso (aplicado pelo BFF via @PreAuthorize ao proxy):
 *   - ADMIN (it)        : CRUD completo
 *   - RULES (bizop)     : CRUD completo      ← CORRIGIDO
 *   - WORKFLOWS (workop): sem acesso
 */
```

---

## Consistência com os outros controllers

Para referência, os outros controllers já têm comentários corretos:

**IntegrationController.kt** (correto, não alterar):
```kotlin
 *   - ADMIN (it)        : CRUD completo
 *   - WORKFLOWS (workop): leitura apenas
 *   - RULES (bizop)     : sem acesso
```

**ContractController.kt** (correto, não alterar):
```kotlin
 *   - ADMIN (it)        : CRUD completo
 *   - WORKFLOWS (workop): CRUD completo
 *   - RULES (bizop)     : leitura apenas
```

---

## Arquivos críticos

| Arquivo | Linha | Mudança |
|---|---|---|
| `service-portal-manager/src/main/kotlin/com/serviceportal/manager/controller/ValidationController.kt` | ~27 | `leitura apenas` → `CRUD completo` |

---

## Verificação

1. **Revisar o diff** — garantir que apenas o comentário mudou (nenhuma lógica alterada):
   ```bash
   git diff service-portal-manager/src/main/kotlin/com/serviceportal/manager/controller/ValidationController.kt
   ```

2. **Build deve continuar passando** sem qualquer alteração de comportamento:
   ```bash
   cd service-portal-manager && ./gradlew test
   # Esperado: 150 testes, 0 falhas (número pode ter crescido desde a última sessão)
   ```

3. **Conferir os 3 controllers lado a lado** para garantir consistência da documentação de acesso:
   ```bash
   grep -A 4 "Acesso" service-portal-manager/src/main/kotlin/com/serviceportal/manager/controller/{Integration,Contract,Validation}Controller.kt
   ```
