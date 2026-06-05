# PLAN: Reavaliar fluxo de edição (botão Editar) para recursos modulares

## Contexto
Com a modularização de recursos (Integrações, Contratos e Validações), as telas de gerenciamento utilizam o componente genérico `ResourceManager`. No entanto, o fluxo de edição (botão "Editar") ainda não foi totalmente implementado ou exposto nestas telas, dificultando o ciclo de vida dos recursos (bump de versão).

## Objetivos
1.  **Exposição do Botão**: Disponibilizar o botão "Editar" na visualização de detalhes do recurso.
2.  **Segurança**: Habilitar o botão apenas para usuários com permissão de escrita (`canWrite`) baseada nos grupos Authentik.
3.  **Fluxo de Versão**: Garantir que o salvamento da edição resulte em uma nova versão sequencial (1 → 2 → 3) via `PUT` no Manager.

## Detalhes Técnicos

### 1. Frontend: ResourceManager.tsx
O componente `ResourceManager` deve ser atualizado para gerenciar um novo estado de visualização: `edit`.

**Mudanças:**
- Adicionar botão "Editar" no cabeçalho da view `detail`.
- Implementar a lógica de transição para a view `edit`, carregando o JSON do recurso atual no editor.
- Reutilizar o componente de editor JSON (similar ao usado na criação) para a edição.
- O botão de salvar deve disparar o método `bff.[resource].update(id, version, body)`.

### 2. Lógica de Permissões (canWrite)
A permissão de escrita deve ser passada para o `ResourceManager` com base no tipo de recurso e grupo do usuário:
- **Integrations**: `ADMIN` (it).
- **Contracts**: `ADMIN` (it) ou `WORKFLOWS` (workop).
- **Validations**: `ADMIN` (it) ou `RULES` (bizop).

### 3. Integração com Manager (Versioning)
O Manager já possui o `SequentialVersioningService`. Quando o BFF chama o `PUT /manager/[resource]/{id}/versions/{v}`, o Manager:
1. Valida o conteúdo.
2. Desativa a versão `{v}`.
3. Cria a versão `{v+1}` com o novo conteúdo.
4. O Frontend deve redirecionar o usuário para a lista de ativos ou para o detalhe da nova versão gerada.

## Plano de Ação

| Passo | Componente | Descrição |
|---|---|---|
| 1 | Frontend | Atualizar `ResourceManager.tsx` para incluir o botão "Editar" condicional ao `canWrite`. |
| 2 | Frontend | Implementar a view de edição com o editor JSON pré-populado. |
| 3 | Frontend | Conectar o "Salvar" ao endpoint de update no `api/bff.ts`. |
| 4 | BFF | Validar se as anotações `@PreAuthorize` nos proxy controllers de Recursos permitem o `PUT` para os grupos corretos. |
| 5 | Manager | Validar se o `update` de Recursos modulares está retornando o header `Location` com a nova versão correta. |

## Verificação
1. **Escrita**: Logar como `it`, acessar uma Integração e verificar se o botão "Editar" aparece e funciona.
2. **Restrição**: Logar como `workop`, acessar uma Validação e garantir que o botão "Editar" **não** esteja visível (apenas leitura).
3. **Persistência**: Após editar uma Integração versão 1, verificar se a lista agora exibe a versão 2 como ativa e a versão 1 como inativa.
4. **Integridade**: Garantir que o ID do recurso não possa ser alterado durante a edição (campo readonly no formulário).

## Considerações de Layout
- O botão "Editar" deve ser visualmente consistente com o botão "Novo".
- Usar um modal de confirmação ou um aviso claro de que a edição criará uma nova versão e desativará a atual.