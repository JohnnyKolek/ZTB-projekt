#!/usr/bin/env bash
# Ładowanie zbioru danych do bazy od zera, z pomiarem czasu.
#
# Użycie:
#   ./scripts/load.sh <baza|all> <zbiór> [--keep]
#
#   <baza>   postgres | mariadb | mongodb | neo4j | all (po kolei wszystkie 4)
#   <zbiór>  katalog w data/ z wynikiem generatora, np. 10m (patrz scripts/generate.sh)
#   --keep   nie zapisuj wiersza do results/load-times.csv (np. próbne ładowanie)
#
# Każde wywołanie:
#   1. kasuje dane bazy (db.sh reset; Neo4j: usuwa wolumen),
#   2. zakłada schemat (PostgreSQL/MariaDB: init/ przy starcie, MongoDB: schema.js),
#   3. ładuje dane NATYWNYM narzędziem bazy, uruchamianym w jej kontenerze
#      (pliki z data/ są tam zamontowane, więc na hoście nie trzeba klientów baz):
#        PostgreSQL  COPY ... FROM (serwerowy, CSV z data/<zbiór>/sql)
#        MariaDB     LOAD DATA LOCAL INFILE (CSV z data/<zbiór>/sql)
#        MongoDB     mongoimport (NDJSON z data/<zbiór>/mongo)
#        Neo4j       neo4j-admin database import full (CSV z data/<zbiór>/neo4j), baza zatrzymana
#   4. robi krok po imporcie (db.sh post-import: sekwencje + ANALYZE / ograniczenia Neo4j),
#   5. porównuje liczby rekordów z manifest.json,
#   6. dopisuje czasy do results/load-times.csv.
#
# Mierzone czasy (sekundy, zegar ścienny):
#   import_s       samo ładowanie danych (z utrzymaniem PK/UNIQUE/FK, które schemat ma przed importem)
#   post_import_s  krok po imporcie (Neo4j: budowa ograniczeń unikalności = indeksów na id)
#   total_s        import_s + post_import_s
# Czas startu/resetu serwera nie jest wliczany.
#
# Baza zostaje po wszystkim uruchomiona z załadowanym zbiorem (wariant indeksów: none).

set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash: nie przerabiaj /data-import/... na ścieżki Windows

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DBSH="$ROOT/scripts/db.sh"
INFRA="$ROOT/infra"
RESULTS="$ROOT/results/load-times.csv"
[[ -f "$INFRA/.env" ]] || cp "$INFRA/.env.example" "$INFRA/.env"
set -a; source "$INFRA/.env"; set +a

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 1; }

target="${1:-}"; dataset="${2:-}"; keep=0
[[ "${3:-}" == "--keep" ]] && keep=1
[[ -n "$target" && -n "$dataset" ]] || usage
[[ "$dataset" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Zła nazwa zbioru: $dataset" >&2; exit 1; }
DATA="$ROOT/data/$dataset"
MANIFEST="$DATA/manifest.json"
[[ -f "$MANIFEST" ]] || { echo "Brak $MANIFEST – zbiór niekompletny albo nie istnieje (scripts/generate.sh)." >&2; exit 1; }

TABLES=(categories suppliers warehouses users addresses products product_categories
        inventory orders order_items payments shipments reviews)

now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }
expected() { grep -o "\"$1\":[0-9]*" "$MANIFEST" | tail -n1 | cut -d: -f2; }   # liczba z manifest.json (sekcja counts)
log() { echo ">> [$1] $2"; }

PG=(docker exec -i ztbd-postgres psql -X -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME")
MDB=(docker exec -i ztbd-mariadb mariadb --local-infile=1 -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME")
MONGO=(docker exec ztbd-mongodb mongosh --quiet "$DB_NAME" --eval)
CYPHER=(docker exec -i ztbd-neo4j cypher-shell -u neo4j -p "$DB_PASSWORD" --format plain)

# Healthcheck bywa zielony, zanim skończy się init/ (schemat) – czekamy na ostatnią tabelę.
wait_schema() {
  local i
  for i in $(seq 1 60); do
    case "$1" in
      postgres) "${PG[@]}" -tAc "SELECT 1 FROM reviews LIMIT 0" >/dev/null 2>&1 && return 0 ;;
      mariadb)  "${MDB[@]}" -N -e "SELECT 1 FROM reviews LIMIT 0" >/dev/null 2>&1 && return 0 ;;
      *) return 0 ;;
    esac
    sleep 2
  done
  echo "Schemat $1 nie powstał w 2 min (infra/$1/init/)." >&2; exit 1
}

# --- import ------------------------------------------------------------

import_postgres() {
  local t cols sql=""
  for t in "${TABLES[@]}"; do
    cols="$(head -n1 "$DATA/sql/$t.csv" | tr -d '\r')"
    sql+="COPY $t ($cols) FROM '/data-import/$dataset/sql/$t.csv' WITH (FORMAT csv, HEADER true, NULL '__ZTBD_NULL__', ENCODING 'UTF8');"$'\n'
  done
  "${PG[@]}" <<< "$sql"
}

import_mariadb() {
  local t cols vars sets sql=""
  for t in "${TABLES[@]}"; do
    cols="$(head -n1 "$DATA/sql/$t.csv" | tr -d '\r')"
    vars="$(sed 's/\([^,]*\)/@\1/g' <<< "$cols")"
    sets="$(tr ',' '\n' <<< "$cols" | sed "s/.*/& = NULLIF(@&, '__ZTBD_NULL__')/" | paste -sd, -)"
    sql+="LOAD DATA LOCAL INFILE '/data-import/$dataset/sql/$t.csv' INTO TABLE $t CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\"'
LINES TERMINATED BY '\n' IGNORE 1 LINES ($vars) SET $sets;
SHOW WARNINGS;"$'\n'
  done
  "${MDB[@]}" <<< "$sql"
}

import_mongodb() {
  local f c
  for f in "$DATA"/mongo/*.ndjson; do
    [[ -s "$f" ]] || continue
    c="$(basename "$f" .ndjson)"
    docker exec ztbd-mongodb mongoimport --quiet --db "$DB_NAME" --collection "$c" \
      --file "/data-import/$dataset/mongo/$c.ndjson" --stopOnError
  done
}

import_neo4j() {
  local f name args=(neo4j-admin database import full neo4j --overwrite-destination
                     --id-type=integer --legacy-style-quoting=false)
  for f in "$DATA"/neo4j/node-*.csv; do
    name="$(basename "$f" .csv)"; args+=("--nodes=${name#node-}=/import/$dataset/neo4j/$name.csv")
  done
  for f in "$DATA"/neo4j/rel-*.csv; do
    name="$(basename "$f" .csv)"; args+=("--relationships=${name#rel-}=/import/$dataset/neo4j/$name.csv")
  done
  # Jednorazowy kontener na tym samym wolumenie co serwer (serwer zatrzymany).
  (cd "$INFRA" && docker compose --profile neo4j run --rm --no-deps neo4j "${args[@]}")
}

# --- liczby rekordów ----------------------------------------------------

counts_postgres() {
  local t; for t in "${TABLES[@]}"; do
    echo "$t $("${PG[@]}" -tAc "SELECT count(*) FROM $t")"; done
}
counts_mariadb() {
  local t; for t in "${TABLES[@]}"; do
    echo "$t $("${MDB[@]}" -N -e "SELECT count(*) FROM $t")"; done
}
counts_mongodb() {
  "${MONGO[@]}" '
    for (const c of db.getCollectionNames().sort()) print(c + " " + db[c].countDocuments());
    const r = db.orders.aggregate([{ $group: { _id: null, n: { $sum: { $size: "$items" } } } }]).toArray();
    print("order_items " + (r.length ? r[0].n : 0));'
}
counts_neo4j() {
  local t label
  declare -A labels=([categories]=Category [suppliers]=Supplier [warehouses]=Warehouse [users]=User
    [addresses]=Address [products]=Product [orders]=Order [payments]=Payment [shipments]=Shipment [reviews]=Review)
  declare -A rels=([product_categories]=IN_CATEGORY [inventory]=STOCKS [order_items]=CONTAINS)
  for t in "${!labels[@]}"; do
    echo "$t $("${CYPHER[@]}" "MATCH (n:${labels[$t]}) RETURN count(n)" | tail -n1)"; done
  for t in "${!rels[@]}"; do
    echo "$t $("${CYPHER[@]}" "MATCH ()-[r:${rels[$t]}]->() RETURN count(r)" | tail -n1)"; done
}

verify() {   # verify <baza> – 0 gdy wszystkie liczby zgodne z manifestem
  local db="$1" ok=0 t got want
  declare -A have=()
  while read -r t got; do [[ -n "$t" ]] && have[$t]="${got//$'\r'/}"; done < <("counts_$db")
  for t in "${TABLES[@]}"; do
    want="$(expected "$t")"; got="${have[$t]:-brak}"
    if [[ "$got" != "$want" ]]; then echo "   BŁĄD  $t: jest $got, oczekiwano $want" >&2; ok=1; fi
  done
  return $ok
}

disk_mb() {   # rozmiar katalogu danych serwera po załadowaniu (z WAL/logami)
  local c dir
  case "$1" in
    postgres) c=ztbd-postgres; dir=/var/lib/postgresql ;;
    mariadb)  c=ztbd-mariadb;  dir=/var/lib/mysql ;;
    mongodb)  c=ztbd-mongodb;  dir=/data/db ;;
    neo4j)    c=ztbd-neo4j;    dir=/data/databases/neo4j ;;
  esac
  docker exec "$c" du -sm "$dir" | cut -f1
}

# --- jedna baza ---------------------------------------------------------

load_one() {
  local db="$1" t0 import_s post_s total_s counts_ok
  log "$db" "zbiór $dataset ($(expected order_items) pozycji zamówień)"

  if [[ "$db" == neo4j ]]; then
    "$DBSH" down
    (cd "$INFRA" && docker compose --profile neo4j rm -sfv neo4j >/dev/null)
    docker volume rm -f ztbd_neo4j_data ztbd_neo4j_logs >/dev/null
    log "$db" "neo4j-admin import"
    t0=$(now); import_neo4j; import_s=$(since "$t0")
    "$DBSH" up neo4j
  else
    "$DBSH" reset "$db"
    wait_schema "$db"
    [[ "$db" == mongodb ]] && "$DBSH" schema mongodb
    log "$db" "import"
    t0=$(now); "import_$db"; import_s=$(since "$t0")
  fi
  log "$db" "import: ${import_s} s"

  t0=$(now); "$DBSH" post-import "$db"; post_s=$(since "$t0")
  total_s=$(awk -v a="$import_s" -v b="$post_s" 'BEGIN { printf "%.1f", a + b }')
  log "$db" "po imporcie: ${post_s} s, razem ${total_s} s"

  if verify "$db"; then counts_ok=true; log "$db" "liczby rekordów zgodne z manifest.json"
  else counts_ok=false; log "$db" "UWAGA: liczby rekordów NIEZGODNE z manifest.json"; fi

  local disk; disk=$(disk_mb "$db")
  log "$db" "rozmiar danych na dysku: ${disk} MB"

  if (( ! keep )); then
    [[ -f "$RESULTS" ]] || echo "timestamp,db,dataset,order_items,import_s,post_import_s,total_s,disk_mb,counts_ok,cpus,memory,machine" > "$RESULTS"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$db,$dataset,$(expected order_items),$import_s,$post_s,$total_s,$disk,$counts_ok,$DB_CPUS,$DB_MEMORY,${MACHINE:-nieznany}" >> "$RESULTS"
    log "$db" "zapisano do results/load-times.csv"
  fi
  [[ "$counts_ok" == true ]]
}

case "$target" in
  all) for db in postgres mariadb mongodb neo4j; do load_one "$db"; done ;;
  postgres|mariadb|mongodb|neo4j) load_one "$target" ;;
  *) usage ;;
esac
