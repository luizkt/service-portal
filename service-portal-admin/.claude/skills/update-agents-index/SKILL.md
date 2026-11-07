---
name: update-agents-index
description: Atualiza o AGENTS.md (índice do repositório) depois de qualquer mudança de código em service-portal-admin. Use ao terminar uma feature, correção, refatoração ou mudança de config, antes do commit, e sempre que `repo-index.py check` falhar.
---

# update-agents-index (service-portal-admin)

O `AGENTS.md` na raiz deste repositório é o índice que agentes leem antes de abrir código. Se ele fica velho, o agente erra o ponto de mudança. Mantenha-o no mesmo commit do código.

## Quando rodar

- Terminou uma feature, correção ou refatoração: rode os passos abaixo antes do commit.
- Mudança só em teste, comentário ou formatação: basta o passo 4 (`check`).
- O `check` acusou erro ou aviso: rode os passos 2 a 4.

## Passos

1. Veja o que mudou: `git status --short` e `git diff --name-only`.
2. Leia o `AGENTS.md` e atualize só o que a mudança afeta:
   - Arquivo novo, removido ou renomeado: linha no **Mapa** (ou cubra com glob como `pkg/*`).
   - Endpoint, rota, tela ou chamada nova ou alterada: tabela de **Endpoints** ou **Telas**/**Chamadas ao BFF**.
   - Passo do fluxo alterado: seção **Fluxo**.
   - Novo ponto de extensão (novo tipo, enum, provider, regra): linha em **Quero mudar... onde**.
   - Variável de ambiente ou chave de config relevante: seção de **config**.
   - Correção que revelou uma invariante ou pegadinha: item em **Armadilhas**.
   - Informação que ficou falsa: corrija ou apague. Não deixe o antigo ao lado do novo.
3. Confirme cada fato novo no código antes de escrever. Não invente e não copie do commit message.
4. Rode (da raiz do repositório):

   ```bash
   python3 .claude/skills/update-agents-index/repo-index.py write .
   python3 .claude/skills/update-agents-index/repo-index.py check .
   ```

   Corrija todo `ERRO` (caminho citado que não existe, bloco gerado desatualizado). Para aviso de arquivo sem citação, cite a classe ou cubra com glob.

   O `write` atualiza o bloco `gen:size` (contagem de arquivos) e a data `atualizado-em`. Não edite esse bloco à mão.

## Regras de escrita

- Orçamento: até 2.000 tokens estimados (o `check` mostra). Se passar, corte detalhe de baixo valor (listas longas, valores padrão), nunca um fato que muda onde editar.
- Português, prosa simples, uma ideia por frase, sem narrar o histórico ("agora", "foi adicionado"). O índice descreve o estado atual.
- Caminhos em crases devem existir. Não mude seções que a mudança não tocou.
- Não crie outro arquivo de índice. Só o `AGENTS.md`.

## Fim

Inclua o `AGENTS.md` no mesmo commit do código. Se o índice não precisou mudar, diga isso na resposta em uma linha.
