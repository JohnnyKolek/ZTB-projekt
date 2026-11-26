#!/usr/bin/env bash
# Generuje zbiory danych do data/<rozmiar> (Record_generation/generate.py, seed 42).
#
# Użycie:
#   ./scripts/generate.sh              wszystkie rozmiary: 100k 500k 1m 5m 10m
#   ./scripts/generate.sh 1m 10m       wybrane rozmiary
#
# Rozmiar = liczba pozycji zamówień (order_items). Istniejący kompletny zbiór
# (z manifest.json) jest pomijany; niekompletny (przerwany) jest kasowany i generowany od nowa.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEED=42
declare -A SIZES=([100k]=100000 [500k]=500000 [1m]=1000000 [5m]=5000000 [10m]=10000000)
ORDER=(100k 500k 1m 5m 10m)

PY=python3; command -v "$PY" >/dev/null 2>&1 && "$PY" -c 'import sys' 2>/dev/null || PY=python

for label in "${@:-${ORDER[@]}}"; do
  n="${SIZES[$label]:-}"
  [[ -n "$n" ]] || { echo "Nieznany rozmiar: $label (dostępne: ${ORDER[*]})" >&2; exit 1; }
  out="$ROOT/data/$label"
  if [[ -f "$out/manifest.json" ]]; then echo ">> $label: już jest, pomijam"; continue; fi
  [[ -d "$out" ]] && { echo ">> $label: niekompletny, kasuję"; rm -rf "$out"; }
  echo ">> $label: generuję $n pozycji zamówień"
  start=$(date +%s)
  "$PY" "$ROOT/Record_generation/generate.py" "$n" "$SEED" "$out"
  echo ">> $label: $(( $(date +%s) - start )) s, $(du -sh "$out" | cut -f1)"
done
