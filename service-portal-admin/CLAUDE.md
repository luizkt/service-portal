# CLAUDE.md — service-portal-admin

- Leia `AGENTS.md` antes de abrir código. Ele é o índice do repositório: o que é, onde mudar e o que não quebrar.
- Ao terminar qualquer feature, correção ou refatoração, use a skill `update-agents-index` antes do commit e inclua o `AGENTS.md` no mesmo commit. Se o índice não precisa mudar, diga isso em uma linha.
- O hook `.githooks/pre-commit` bloqueia o commit se código de produção mudou sem o `AGENTS.md`, ou se `repo-index.py check` acusar erro. Ative uma vez por clone: `git config core.hooksPath .githooks`.
- Mudança que não afeta o índice: `AGENTS_INDEX_OK=1 git commit ...`.
