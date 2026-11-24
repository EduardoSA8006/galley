#!/usr/bin/env bash
# Publica o espelho do corpus público na release `corpus-v1` do repositório.
#
# ATENÇÃO: publica conteúdo de terceiros. Rodar SOMENTE com aprovação explícita
# do mantenedor, depois de conferir as licenças em corpus/README.md.
#
# O que faz:
#   1. baixa (ou reaproveita do cache .corpus-cache/) cada livro com
#      "mirrorable": true do corpus/manifest.json, pela URL original;
#   2. confere o sha256 de cada arquivo contra o manifesto (aborta se divergir);
#   3. cria a release `corpus-v1` (se não existir) com o corpus/README.md como
#      notas — atribuições e licenças exigidas (CC-BY-SA, GFDL, W3C, PG);
#   4. envia cada arquivo como `<id>.epub`, mais o README como asset.
#
# Requisitos: bash, curl, jq, sha256sum, gh autenticado com permissão de
# escrita em EduardoSA8006/galley.
#
# Uso: corpus/tool/mirror.sh [--dry-run]
set -euo pipefail

repo="EduardoSA8006/galley"
tag="corpus-v1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/corpus/manifest.json"
readme="$root/corpus/README.md"
cache="$root/.corpus-cache"
staging="$cache/mirror-staging"
user_agent="galley-benchmark-corpus-fetcher/1 (+https://github.com/$repo)"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
fi

for tool in curl jq sha256sum gh; do
  command -v "$tool" >/dev/null || { echo "falta a ferramenta: $tool" >&2; exit 1; }
done

rm -rf "$staging"
mkdir -p "$staging"

# Um livro por linha: id, url, sha256 (só os espelháveis).
jq -r '.books[] | select(.mirrorable) | [.id, .url, .sha256] | @tsv' "$manifest" |
  while IFS=$'\t' read -r id url sha; do
    cached="$cache/$sha.epub"
    if [[ ! -f "$cached" ]]; then
      echo "baixando $id"
      curl -fsSL -A "$user_agent" -o "$cached.part" "$url"
      mv "$cached.part" "$cached"
      sleep 2 # gentileza com os servidores de origem
    fi
    actual="$(sha256sum "$cached" | cut -d' ' -f1)"
    if [[ "$actual" != "$sha" ]]; then
      echo "sha256 divergente em $id: esperado $sha, obtido $actual" >&2
      exit 1
    fi
    cp "$cached" "$staging/$id.epub"
  done

cp "$readme" "$staging/CORPUS-README.md"
count="$(find "$staging" -name '*.epub' | wc -l)"
echo "$count arquivos verificados em $staging"

if $dry_run; then
  echo "--dry-run: nada publicado"
  exit 0
fi

if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$tag" --repo "$repo" \
    --title "Corpus público v1 (espelho)" \
    --notes-file "$readme" \
    --latest=false
fi

gh release upload "$tag" --repo "$repo" --clobber "$staging"/*.epub "$staging/CORPUS-README.md"
echo "release $tag atualizada com $count livros"
