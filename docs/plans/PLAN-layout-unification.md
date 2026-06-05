# PLAN: Unificar layout das telas de gerenciamento (Flow vs Resources)

## Contexto
Atualmente, o `FlowManager` possui uma implementação visual própria, enquanto as novas telas de Integrações, Contratos e Validações utilizam o componente genérico `ResourceManager`. Foram detectadas diferenças em margens, estilos de botões e na estrutura dos cabeçalhos, o que prejudica a experiência de uso "Server Driven UI".

## Objetivos
1.  **Consistência Visual**: Garantir que a transição entre telas de diferentes recursos seja imperceptível para o usuário.
2.  **Reuso de CSS**: Eliminar estilos duplicados e consolidar o design system em classes utilitárias.
3.  **Componentização**: Extrair padrões repetitivos para sub-componentes comuns.

## Pontos de Discrepância Identificados
- **Cabeçalho**: O `FlowManager` pode estar usando estruturas de flexbox diferentes do `ResourceManager`.
- **Badges de Status**: Cores e arredondamentos das tags "Active/Inactive" podem variar.
- **Editor**: O visual do visualizador de YAML (Flows) deve ser idêntico ao de JSON (Resources).
- **Tabelas**: Alinhamento de colunas e estilos de hover nas linhas.

## Plano de Ação

### 1. Auditoria e Padronização de CSS
- Mover estilos comuns de `FlowManager.css` para um arquivo global `src/styles/management-common.css` ou similar.
- Definir variáveis CSS para cores de status (ex: `--color-status-active`, `--color-status-inactive`).

### 2. Refatoração do Cabeçalho (PageHeader)
- Criar um sub-componente genérico `PageHeader` que aceite:
    - Título e subtítulo.
    - Array de botões de ação (ex: "Novo", "Voltar").
    - Renderização de Breadcrumbs.
- Aplicar este componente tanto no `FlowManager` quanto no `ResourceManager`.

### 3. Harmonização de Listagens
- Padronizar o componente de tabela para que as colunas de "ID", "Versão" e "Status" tenham larguras e estilos fixos em todos os módulos.
- Garantir que o comportamento de paginação (footer da tabela) seja idêntico.

### 4. Visualização de Código
- Unificar o container que exibe o YAML/JSON. Ambos devem usar o mesmo tema de syntax highlighting e o mesmo padding interno.

## Escopo de Arquivos

| Arquivo | Mudança |
|---|---|
| `src/components/features/FlowManager/FlowManager.tsx` | Substituir estruturas manuais pelo novo `PageHeader`. |
| `src/components/features/ResourceManager/ResourceManager.tsx` | Ajustar grid e espaçamentos para dar match no FlowManager. |
| `src/styles/` | Criação de estilos compartilhados. |
| `src/components/common/` | Extração de `StatusBadge`, `ActionButtons` e `PageHeader`. |

## Verificação

1.  **Comparação Visual**: Abrir a tela de Fluxos e a de Integrações lado a lado e validar que o topo e a listagem são idênticos em proporção.
2.  **Responsividade**: Garantir que a unificação não quebrou o layout em telas menores.
3.  **Testes de Regressão**: Rodar os testes do Vitest para garantir que os seletores de classe (se usados nos testes) ainda funcionam.

## Considerações
- Priorizar a estética do `FlowManager` (que está mais madura) e trazê-la para o `ResourceManager`.
- Evitar o uso de bibliotecas externas; continuar usando CSS puro conforme as restrições do projeto.