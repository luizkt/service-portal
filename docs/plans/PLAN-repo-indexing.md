# PLAN — Indexação de repositório para agentes de IA

## Objetivo

Reduzir os tokens que um agente gasta para entender um repositório e descobrir onde alterar. Hoje o agente lê muitos arquivos até achar o ponto certo. A meta é ler um único índice compacto e abrir só os arquivos indicados por ele.

## Princípios

1. Índice curto, de uma tela (meta: até 1.500 tokens por repositório pequeno, até 3.000 por médio).
2. O índice responde três perguntas: o que é, onde mexer para cada tipo de mudança, o que não quebrar.
3. Caminhos exatos. O agente nunca deve precisar de `find` ou varredura para localizar um arquivo citado.
4. Fatos derivados do código (arquivos, dependências, endpoints, portas) são gerados por script. Texto de intenção (responsabilidade, armadilhas) é escrito à mão.
5. Sem embeddings nem banco vetorial na primeira fase. Markdown versionado no git é suficiente e auditável. RAG só entra se o repositório passar do tamanho em que o índice cabe em uma leitura.

## Artefato por repositório

Arquivo `AGENTS.md` na raiz do componente (convenção já usada por BFF, Manager e Frontend). Estrutura fixa:

| Seção | Conteúdo | Origem |
|---|---|---|
| `index:meta` | nome, tipo, fontes de verdade, data | manual |
| Resumo | 2-3 frases + tamanho (nº de classes/arquivos, testes) | manual + contagem |
| Stack | linguagem, framework, build, porta | gerado do build file |
| Mapa de arquivos | arquivo, papel, "mexer quando" | gerado (lista) + manual (papel) |
| Pontos-chave por tipo de mudança | "Quero X → arquivo/símbolo" | manual |
| Integrações | quem fala com quem e onde está a config | manual |
| Comandos | build, teste, format | manual |
| Armadilhas | erros já cometidos, invariantes | manual |

Referência: `service-portal-admin/AGENTS.md`.

## Método (genérico, aplicável a qualquer repositório)

1. **Inventário.** Listar `git ls-files`, contar linhas por diretório, identificar entry points, configs, build e testes.
2. **Classificar.** Dar um papel de uma linha a cada arquivo relevante. Agrupar arquivos triviais (DTOs, mocks) em uma linha por pacote.
3. **Tabela de intenções.** Listar as 8-15 mudanças mais prováveis e o ponto exato de cada uma.
4. **Integrações.** Registrar contratos externos (endpoints, filas, env vars, compose) com o local da config nos dois lados.
5. **Armadilhas.** Extrair do histórico git (`git log --grep fix`) e de falhas conhecidas.
6. **Validar.** Verificar que todo caminho citado existe e que o índice cabe na meta de tokens.
7. **Manter.** Atualizar o índice no mesmo commit que mudar um arquivo listado.

## Fases

| Fase | Entrega | Status |
|---|---|---|
| F1 | Piloto manual em `service-portal-admin` (`AGENTS.md`) | feito |
| F2 | `scripts/repo-index.py` (Python 3, só stdlib): `inventory` (semente de AGENTS.md novo), `check` (caminhos citados, bloco gerado, arquivos sem citação, orçamento de tokens), `write` (atualiza blocos `gen:` e a data) | feito |
| F3 | Medir ganho: tarefa de exemplo com e sem índice, tokens lidos e arquivos abertos | feito (rodadas 1 a 3; ver Resultados F3) |
| F4 | `AGENTS.md` no formato curto em Orchestrator, BFF, Manager e Frontend (reescritos por subagentes em paralelo, fatos verificados no código) | feito |
| F4b | Skill `update-agents-index` em cada componente (`.claude/skills/update-agents-index/` com `SKILL.md` e cópia de `repo-index.py`): atualiza o `AGENTS.md` a cada feature ou correção, antes do commit | feito |
| F4c | Hook `.githooks/pre-commit` e `CLAUDE.md` em cada componente: bloqueia commit com código de produção sem `AGENTS.md` ou com `check` em erro; `CLAUDE.md` manda ler o índice e usar a skill | feito |
| F5 | Índice raiz em `docs/MAP.md`: uma linha por componente apontando para o `AGENTS.md`, mais a seção de manutenção | feito |
| F6 | Avaliar RAG só se algum componente passar do limite de tokens | opcional |

## Como medir

Tarefa fixa por repositório, por exemplo "trocar a rota pública X". Registrar:

- arquivos abertos e linhas lidas até chegar à edição correta;
- tokens de entrada da sessão;
- se a edição caiu no arquivo certo na primeira tentativa.

Comparar sem índice contra com índice. Critério de sucesso: pelo menos 50% menos tokens de leitura e acerto na primeira tentativa.

## Resultados F3 (rodada 1, 2026-11-07)

Alvo: `generic-orchestrator` (64 arquivos Java, `AGENTS.md` de ~3.100 tokens). Seis subagentes Sonnet, somente leitura, uma execução por célula. Tarefas de localização: T1 nova regra de validação `UUID`, T2 retry também em 502/503, T3 novo provider de fila `NATS`. "Sem índice" proibia ler `AGENTS.md`.

| Tarefa | Sem índice (tokens / chamadas) | Com índice (tokens / chamadas) |
|---|---|---|
| T1 | 35.713 / 5 | 41.188 / 5 |
| T2 | 37.681 / 4 | 41.735 / 6 |
| T3 | 39.021 / 5 | 44.497 / 6 |
| Total | 112.415 / 14 | 127.420 / 17 |

- Acerto: os dois grupos acharam os pontos do gabarito nas três tarefas. Com índice houve um erro factual no T2: o agente afirmou que `application.yml` não tem bloco `retry-configuration`, mas ele existe nas linhas 102-110.
- Com índice custou +13% de tokens e +3 chamadas. A leitura do `AGENTS.md` (~3 mil tokens) não foi compensada por menos buscas.
- Limitações: uma execução por célula (ruído), repositório pequeno em que `grep` resolve em 4-5 chamadas, tarefas de localização simples, e o total de tokens do subagente inclui custo fixo de prompt que não depende do índice.
- Conclusão provisória: neste tamanho e tipo de tarefa, o índice não reduz tokens. Não validou a hipótese do plano.

Próximos testes: ver a rodada 2 (tarefas de compreensão já feitas).

## Resultados F3, rodada 2 (2026-11-07)

Mesmo alvo e mesmo método da rodada 1 (Sonnet, somente leitura, uma execução por célula). Perguntas de compreensão de fluxo, com gabarito fixado antes: Q1 flow fora do cache com 404 do Manager (resposta correta: HTTP 200 com `status: FAILED`, porque `OrchestrationService` captura a exceção), Q2 falha em passo paralelo do v2 sem `continueOnError`, Q3 resolução de templates `{{...}}` para valores ausentes.

| Pergunta | Sem índice (tokens / chamadas / tempo) | Com índice (tokens / chamadas / tempo) |
|---|---|---|
| Q1 | 38.319 / 10 / 22,8 s | 38.677 / 6 / 14,9 s |
| Q2 | 36.672 / 6 / 14,7 s | 39.337 / 4 / 10,8 s |
| Q3 | 37.435 / 6 / 15,4 s | 36.885 / 6 / 14,5 s |
| Total | 112.426 / 22 / 52,9 s | 114.899 / 16 / 40,2 s |

- Acerto: os seis agentes responderam certo e com evidência de linha. Com índice não houve erro factual nesta rodada.
- Tokens: praticamente iguais (+2%). Chamadas de ferramenta: 27% menos com índice (16 contra 22). Tempo: 24% menor com índice.
- O índice pagou o custo de leitura em chamadas e tempo, mas não em tokens. Maior efeito no Q1, que cruza controller, serviço, cache e cliente do Manager: 10 chamadas sem índice, 6 com.
- Achado extra, sem índice no Q3: `Map.of("error", e.getMessage())` em `OrchestrationService` lança NPE se a mensagem da exceção for nula. Não verificado.

### Conclusão combinada (rodadas 1 e 2)

| Tipo de tarefa | Tokens | Chamadas |
|---|---|---|
| Localizar onde mudar (rodada 1) | +13% | +21% (17 contra 14) |
| Entender fluxo (rodada 2) | +2% | -27% |

- O índice ajuda quando a resposta cruza vários arquivos e não ajuda quando um `grep` basta.
- Nenhuma rodada mostrou economia de tokens. O ganho medido é em chamadas e tempo, e só em compreensão.
- Limitações: uma execução por célula, repositório pequeno, custo fixo de prompt dentro do total de tokens do subagente.

Próximos testes: o item de encurtar o `AGENTS.md` foi feito na rodada 3.

## Resultados F3, rodada 3: índice curto (2026-11-07)

`AGENTS.md` do orquestrador reduzido de ~3.100 para ~1.730 tokens (-44%): saíram a tabela completa de variáveis de ambiente, a lista arquivo a arquivo e as seções de stack e restrições, que foram fundidas. Ficaram endpoints, fluxo, mapa de pacotes, tabela "quero mudar... onde" e armadilhas. `repo-index.py check` passa. Mesmas 6 tarefas e mesmo método (Sonnet, somente leitura, uma execução por célula). A coluna "sem índice" e a "índice longo" são as das rodadas 1 e 2.

| Tarefa | Sem índice | Índice longo (~3.100 tok) | Índice curto (~1.730 tok) |
|---|---|---|---|
| T1 | 35.713 / 5 | 41.188 / 5 | 39.787 / 8 |
| T2 | 37.681 / 4 | 41.735 / 6 | 39.286 / 4 |
| T3 | 39.021 / 5 | 44.497 / 6 | 38.957 / 4 |
| Q1 | 38.319 / 10 | 38.677 / 6 | 41.565 / 5 |
| Q2 | 36.672 / 6 | 39.337 / 4 | 39.697 / 4 |
| Q3 | 37.435 / 6 | 36.885 / 6 | 36.490 / 3 |
| Total | 224.841 / 36 | 242.319 / 33 | 235.782 / 28 |

Células em tokens / chamadas de ferramenta.

| Comparação | Tokens | Chamadas |
|---|---|---|
| Curto contra sem índice | +4,9% | -22% |
| Curto contra longo | -2,7% | -15% |
| Longo contra sem índice | +7,8% | -8% |

Por rodada, curto contra sem índice: localização (T1-T3) +5,0% tokens e +14% chamadas (16 contra 14); compreensão (Q1-Q3) +4,7% tokens, -45% chamadas (12 contra 22) e -40% tempo (32,0 s contra 52,9 s).

- Acerto: as 18 execuções acharam os pontos do gabarito. O erro factual do T2 com índice longo não se repetiu com o curto.
- O índice curto custa menos que o longo e dá menos chamadas, mas ainda não economiza tokens contra não ter índice (+5%).
- O ganho é em compreensão: 45% menos chamadas e 40% menos tempo. Em localização o índice não ajudou.
- T1 com índice curto fez 8 chamadas (as outras células fizeram 4 a 6) porque o agente também varreu outros módulos. É um outlier de uma execução.
- Limitações: uma execução por célula, repositório pequeno, e o total de tokens do subagente inclui custo fixo de prompt que não depende do índice. Diferenças de 5% estão dentro do ruído esperado.

### Decisão provisória

- Manter `AGENTS.md` curto (até ~1.700 tokens) como formato do template: custa menos e rende o mesmo acerto.
- Não vender o método como economia de tokens. Vender como menos chamadas e menos tempo em tarefas de compreensão.
- A F4 (BFF, Manager, Frontend) segue o formato curto. Repetir a medição em um repositório maior antes de generalizar.

## Resultados F4 (2026-11-07)

Três subagentes Sonnet, um por repositório, em paralelo, com o `AGENTS.md` do orquestrador como exemplo de formato. Cada um verificou os fatos no código e rodou `repo-index.py check`.

| Componente | Tokens (estimado) | `check` |
|---|---|---|
| `generic-orchestrator` | ~1.770 | ok |
| `service-portal-admin` | ~1.070 | ok |
| `service-portal-bff` | ~1.740 | ok |
| `service-portal-manager` | ~1.880 | ok |
| `service-portal-frontend` | ~1.860 | ok (aviso esperado: sem bloco `gen:size`) |

Os `AGENTS.md` antigos estavam defasados. Correções principais:

- BFF: lista de endpoints incompleta; renovação de token só quando faltam menos de 60 s (o antigo citava 401).
- Manager: o escopo antigo falava só de flows, mas ele também é dono de `contracts`, `integrations` e `validations`. `PUT` de workflow cria nova versão SemVer e responde 201, não atualiza no lugar.
- Frontend: o login real é `LoginPage` → `loginWithCredentials` → `POST /bff/auth/login`, não PKCE; faltavam Integration, Contract e Validation managers, retry de refresh em 401 e `canWrite` por grupo.
- Orquestrador: o Manager é quem chama `DELETE /api/admin/cache/workflows/...` (`OrchestratorCacheClient` do Manager).

Esforço dos agentes, como dado de custo de criação: BFF 66,5 mil tokens / 12 chamadas / 49 s; Manager 70,8 mil / 13 / 55 s; Frontend 87,0 mil / 16 / 93 s.

Limitações de `scripts/repo-index.py` apontadas pelo agente do Frontend:

- `inventory` e o drift só veem `src/main` e Java/Kotlin; não cobrem TypeScript.
- `check` resolve caminhos a partir da raiz do repositório, então `src/...` precisa estar completo.
- Nomes em crases com `.css` ou `.template` são tratados como caminho; o agente usou globs como `src/*.css`.

Os `AGENTS.md` de BFF, Manager e Frontend estão modificados e não commitados nos três repositórios aninhados.

## Fora de escopo

- Banco vetorial, embeddings e serviço de busca.
- Geração automática de texto de intenção por LLM.
- Mudanças de código de produção.

## Pontos em aberto

- O hook só vale em clones com `core.hooksPath` apontando para `.githooks`, e isso é configuração local. `scripts/install-hooks.sh` ativa nos 5 repositórios de uma vez (`--status` só mostra o estado e sai com 1 se algum estiver desligado). Rode uma vez por clone novo.
- CI: nenhum dos 5 repositórios tem pipeline (só remotos do GitHub). Quando houver, ligar `scripts/sync-skill-script.sh --verify` e `repo-index.py check` como passos, porque o CI não depende da configuração local de quem commita.
- O `repo-index.py` está copiado em 5 skills e em `scripts/`. A fonte é `scripts/repo-index.py`. Depois de mudar o script, rode `scripts/sync-skill-script.sh` (copia e roda o `check` nos 5) e commite a cópia em cada componente que mudar. `scripts/sync-skill-script.sh --verify` só compara e sai com 1 se alguma cópia difere: serve para CI.
- Suporte a TypeScript (feito): `repo-index.py` reconhece o layout `src/` (sem `src/main`), separa testes (`__tests__`, `*.test.*`, `*.spec.*`) e `src/test/`, gera `gen:size` com arquivos, testes e casos, resolve caminhos relativos a `src/` e extensões `.ts` e `.tsx`, e faz drift e `inventory` em TypeScript. O `AGENTS.md` do Frontend passou a usar o bloco `gen:size`.
- Um único `AGENTS.md` por componente, ou separar `INDEX.md` gerado de `AGENTS.md` manual? O piloto usa um arquivo só.
- Onde o `check` roda: hook de pre-commit ou CI. `generic-orchestrator` é um repositório git próprio, então o script precisa ser copiado ou versionado em um lugar comum.
- A estimativa de tokens usa caracteres/4. Calibrar contra a contagem real na F3.
