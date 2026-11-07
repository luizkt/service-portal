#!/usr/bin/env bash
# Sincroniza scripts/repo-index.py (fonte) com a cópia dentro da skill de cada componente.
#
# Uso:
#   scripts/sync-skill-script.sh           copia a fonte para as 5 skills e roda o check em cada uma
#   scripts/sync-skill-script.sh --verify  não altera nada; sai com 1 se alguma cópia difere da fonte
#
# Depois de sincronizar, cada componente tem uma mudança a commitar em
# .claude/skills/update-agents-index/repo-index.py (o script lista quais).
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/scripts/repo-index.py"
rel=".claude/skills/update-agents-index/repo-index.py"
components=(
  service-portal-admin
  generic-orchestrator
  service-portal-bff
  service-portal-manager
  service-portal-frontend
)

mode=sync
case "${1:-}" in
  "") ;;
  --verify) mode=verify ;;
  *) echo "uso: $0 [--verify]" >&2; exit 2 ;;
esac

[ -f "$src" ] || { echo "erro: fonte não encontrada: $src" >&2; exit 2; }

status=0
changed=()
for c in "${components[@]}"; do
  dest="$root/$c/$rel"
  if [ ! -d "$root/$c" ]; then
    echo "pulado  $c (diretório não existe)"
    continue
  fi
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "igual   $c"
    continue
  fi
  if [ "$mode" = verify ]; then
    echo "DIFERE  $c"
    status=1
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "copiado $c"
  changed+=("$c")
done

if [ "$mode" = verify ]; then
  [ "$status" -eq 0 ] && echo "ok: todas as cópias iguais à fonte" || echo "rode scripts/sync-skill-script.sh" >&2
  exit "$status"
fi

echo
for c in "${components[@]}"; do
  [ -d "$root/$c" ] || continue
  (cd "$root/$c" && python3 "$rel" check .) || status=1
done

if [ "${#changed[@]}" -gt 0 ]; then
  echo
  echo "Commite a cópia nestes componentes (${rel}):"
  printf '  %s\n' "${changed[@]}"
fi
exit "$status"
