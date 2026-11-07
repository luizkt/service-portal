#!/usr/bin/env bash
# Ativa o hook de pre-commit (.githooks/pre-commit) nos repositórios do Service Portal.
#
# Uso:
#   scripts/install-hooks.sh           ativa (git config core.hooksPath .githooks) em cada repositório
#   scripts/install-hooks.sh --status  só mostra o estado, sem alterar nada; sai com 1 se algum estiver desligado
#
# core.hooksPath é configuração local do clone e não vai no commit. Rode este script uma vez
# em cada clone novo. Repositórios que não estão clonados ao lado são pulados.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# O admin vive dentro do monorepo: o hook dele está em .githooks/ na raiz do monorepo.
repos=(
  "."
  generic-orchestrator
  service-portal-bff
  service-portal-manager
  service-portal-frontend
)

mode=install
case "${1:-}" in
  "") ;;
  --status) mode=status ;;
  *) echo "uso: $0 [--status]" >&2; exit 2 ;;
esac

status=0
for r in "${repos[@]}"; do
  dir="$root/$r"
  label=$([ "$r" = "." ] && echo "service-portal (inclui service-portal-admin)" || echo "$r")

  if [ ! -d "$dir" ]; then
    echo "pulado   $label (não clonado)"
    continue
  fi
  # Cada repositório precisa ter o próprio .git; não configure o monorepo por engano.
  if [ ! -e "$dir/.git" ]; then
    echo "pulado   $label (não é um repositório git)"
    continue
  fi
  if [ ! -f "$dir/.githooks/pre-commit" ]; then
    echo "SEM HOOK $label (falta .githooks/pre-commit; esta branch tem o hook?)"
    status=1
    continue
  fi

  current=$(git -C "$dir" config --local --get core.hooksPath || true)

  if [ "$mode" = status ]; then
    if [ "$current" = ".githooks" ]; then
      echo "ativo    $label"
    else
      echo "DESLIGADO $label (core.hooksPath='${current:-}')"
      status=1
    fi
    continue
  fi

  if [ -n "$current" ] && [ "$current" != ".githooks" ]; then
    echo "AVISO    $label já usa core.hooksPath='$current'; mantido. Ajuste à mão se quiser trocar."
    status=1
    continue
  fi
  chmod +x "$dir/.githooks/pre-commit"
  git -C "$dir" config core.hooksPath .githooks
  if [ "$current" = ".githooks" ]; then
    echo "já ativo $label"
  else
    echo "ativado  $label"
  fi
done

if [ "$mode" = install ] && [ "$status" -eq 0 ]; then
  echo
  echo "Pronto. Mudança que não afeta o índice: AGENTS_INDEX_OK=1 git commit ..."
fi
exit "$status"
