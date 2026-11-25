#!/usr/bin/env bash
# Junta as fatias de um gate do bench-pr (instructions ou ab) e decide o
# veredito do check obrigatório.
#
# Uso: bench-aggregate.sh <shards-dir> <out-dir>
#
# Cada subdiretório de <shards-dir> é o artefato de uma fatia, com:
#   shard      "i/n" (de strategy.job-index/job-total, gravado pelo job);
#   exit-code  código de saída do `tool/bench.dart` (0, 1, 2, 69 ou 70);
#   bmf.json e report.md, quando a medição chegou a escrevê-los.
#
# Ambiente:
#   ACCEPT_REGRESSION  "true" se o PR tem o rótulo perf-regression-accepted
#                      (lido do evento pelo workflow, nunca do artefato);
#   NEEDS_RESULT       resultado agregado dos jobs de fatia;
#   GITHUB_STEP_SUMMARY  resumo do job (opcional).
#
# Grava <out-dir>/bmf.json (união dos BMFs) e <out-dir>/report.md. Sai com 0
# se todas as fatias existem, concordam no total, têm BMF e passaram; ou se
# as únicas falhas são regressão (1) ou checksum divergente (2) e o rótulo
# está presente (aviso no resumo). Sai com 1 em qualquer outro caso.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "uso: $0 <shards-dir> <out-dir>" >&2
  exit 64
fi
shards=$1
out=$2
label=perf-regression-accepted
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
accept=${ACCEPT_REGRESSION:-false}
needs=${NEEDS_RESULT:-success}

mkdir -p "$out"
shopt -s nullglob

problems=()
total=""
declare -A codes=()
declare -A dirs=()
for dir in "$shards"/*/; do
  dir=${dir%/}
  name=$(basename "$dir")
  id=$(tr -d '[:space:]' 2>/dev/null < "$dir/shard" || true)
  if ! [[ $id =~ ^([1-9][0-9]{0,2})/([1-9][0-9]{0,2})$ ]]; then
    problems+=("artefato $name sem identificação válida da fatia")
    continue
  fi
  i=${BASH_REMATCH[1]}
  n=${BASH_REMATCH[2]}
  if [ -z "$total" ]; then
    total=$n
  elif [ "$n" != "$total" ]; then
    problems+=("fatias discordam do total ($n e $total)")
  fi
  if [ -n "${codes[$i]+x}" ]; then
    problems+=("fatia $i repetida")
    continue
  fi
  code=$(tr -d '[:space:]' 2>/dev/null < "$dir/exit-code" || true)
  [[ $code =~ ^[0-9]{1,3}$ ]] || code=ausente
  codes[$i]=$code
  dirs[$i]=$dir
done

if [ -z "$total" ]; then
  problems+=("nenhuma fatia produziu artefato")
else
  for ((i = 1; i <= total; i++)); do
    [ -n "${codes[$i]+x}" ] || problems+=("fatia $i/$total sem artefato")
  done
  bmfs=("$shards"/*/bmf.json)
  if [ "${#bmfs[@]}" -ne "$total" ]; then
    problems+=("${#bmfs[@]} BMF(s) para $total fatia(s): parte do catálogo não foi medida")
  fi
fi

# Junta BMFs (ids disjuntos entre fatias) e relatórios, em ordem de fatia.
bmfs=("$shards"/*/bmf.json)
if [ "${#bmfs[@]}" -gt 0 ]; then
  jq -s 'add' "${bmfs[@]}" > "$out/bmf.json"
fi
: > "$out/report.md"
for i in $(printf '%s\n' "${!dirs[@]}" | sort -n); do
  if [ -f "${dirs[$i]}/report.md" ]; then
    cat "${dirs[$i]}/report.md" >> "$out/report.md"
    printf '\n---\n\n' >> "$out/report.md"
  fi
done

flagged=()
for i in $(printf '%s\n' "${!codes[@]}" | sort -n); do
  case ${codes[$i]} in
    0) ;;
    1 | 2) flagged+=("$i") ;;
    *) problems+=("fatia $i/$total saiu com código ${codes[$i]}") ;;
  esac
done
if [ "$needs" != success ] && [ ${#flagged[@]} -eq 0 ] && [ ${#problems[@]} -eq 0 ]; then
  problems+=("jobs de fatia terminaram com '$needs'")
fi

# Benchmarks regredidos e checksums divergentes, extraídos dos relatórios.
regressions() {
  for i in "${flagged[@]}"; do
    [ -f "${dirs[$i]}/report.md" ] || continue
    awk '
      /^## Checksums divergentes/ { c = 1; next }
      /^## / { c = 0 }
      c && /^- `/ { print "- checksum divergente: " substr($0, 3); next }
      /\| regressed \|$/ {
        split($0, cell, "|")
        gsub(/^ +| +$/, "", cell[2])
        print "- regressão: " cell[2]
      }
    ' "${dirs[$i]}/report.md"
  done
}

status=0
if [ ${#problems[@]} -gt 0 ]; then
  {
    echo '## Veredito: reprovado (fatias incompletas ou com falha)'
    echo
    for p in "${problems[@]}"; do echo "- $p"; done
    echo
  } >> "$summary"
  for p in "${problems[@]}"; do echo "::error::$p"; done
  status=1
elif [ ${#flagged[@]} -gt 0 ]; then
  list=$(regressions)
  [ -n "$list" ] || list='- (ver os relatórios das fatias acima)'
  if [ "$accept" = true ]; then
    {
      echo "## Veredito: aprovado com o rótulo \`$label\`"
      echo
      echo 'Regressões e mudanças de checksum aceitas neste PR:'
      echo
      echo "$list"
      echo
    } >> "$summary"
    echo "::warning::Regressão ou checksum divergente aceito pelo rótulo $label (fatias ${flagged[*]})."
  else
    {
      echo '## Veredito: reprovado (regressão ou checksum divergente)'
      echo
      echo "$list"
      echo
      echo "Se a mudança é intencional, quem tem acesso de escrita aplica o rótulo \`$label\` (ver benchmark/README.md)."
      echo
    } >> "$summary"
    echo "::error::Regressão ou checksum divergente nas fatias ${flagged[*]}; se for intencional, aplique o rótulo $label."
    status=1
  fi
else
  echo "Todas as $total fatia(s) passaram."
fi

[ ! -s "$out/report.md" ] || cat "$out/report.md" >> "$summary"
exit "$status"
