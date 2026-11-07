#!/usr/bin/env bash
# Sincroniza duas fontes do monorepo com as cópias dos componentes:
#   - scripts/repo-index.py -> .claude/skills/update-agents-index/repo-index.py nas 5 skills
#   - license-header.txt    -> license-header.txt na raiz de generic-orchestrator,
#                              service-portal-bff e service-portal-manager
#                              (service-portal-admin usa ../license-header.txt, sem cópia)
#
# Uso:
#   scripts/sync-skill-script.sh           copia as fontes, roda o check do repo-index em cada componente
#   scripts/sync-skill-script.sh --verify  não altera nada; sai com 1 se alguma cópia difere da fonte
#
# Diretório de componente ausente (ex.: CI do monorepo) vira "pulado". Códigos: 0 ok, 1 drift, 2 uso/erro.
# Depois de sincronizar, cada componente tem uma mudança a commitar (o script lista quais).
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

hsrc="$root/license-header.txt"
hrel="license-header.txt"
header_components=(
  generic-orchestrator
  service-portal-bff
  service-portal-manager
)

mode=sync
case "${1:-}" in
  "") ;;
  --verify) mode=verify ;;
  *) echo "uso: $0 [--verify]" >&2; exit 2 ;;
esac

[ -f "$src" ] || { echo "erro: fonte não encontrada: $src" >&2; exit 2; }
[ -f "$hsrc" ] || { echo "erro: fonte não encontrada: $hsrc" >&2; exit 2; }

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

for c in "${header_components[@]}"; do
  dest="$root/$c/$hrel"
  if [ ! -d "$root/$c" ]; then
    echo "pulado  $c/$hrel (diretório não existe)"
    continue
  fi
  if [ -f "$dest" ] && cmp -s "$hsrc" "$dest"; then
    echo "igual   $c/$hrel"
    continue
  fi
  if [ "$mode" = verify ]; then
    echo "DIFERE  $c/$hrel"
    status=1
    continue
  fi
  cp "$hsrc" "$dest"
  echo "copiado $c/$hrel"
  changed+=("$c/$hrel")
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
  echo "Commite a cópia nestes componentes:"
  printf '  %s\n' "${changed[@]}"
fi
exit "$status"
