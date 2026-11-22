#!/usr/bin/env bash
# Test dymny infrastruktury: po kolei uruchamia każdą bazę, sprawdza połączenie,
# wypisuje wersję i weryfikuje, że baza wczytała NASZĄ konfigurację
# (cache 3 GB, fsync przy commicie, brak query cache itd.).
#
# Użycie:  ./scripts/smoke-test.sh            wszystkie bazy
#          ./scripts/smoke-test.sh mariadb    jedna baza
#
# Po teście wszystkie bazy są zatrzymane (dane zostają w wolumenach).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="$ROOT/scripts/db.sh"
set -a; source "$ROOT/infra/.env" 2>/dev/null || source "$ROOT/infra/.env.example"; set +a

DBS=("${@:-postgres mariadb mongodb neo4j}")
read -r -a DBS <<< "${DBS[*]}"

declare -A RESULT
fail=0

check() {   # check <opis> <oczekiwane> <faktyczne>
  if [[ "$3" == "$2" ]]; then
    printf "   OK    %-32s %s\n" "$1" "$3"
  else
    printf "   BŁĄD  %-32s jest '%s', oczekiwano '%s'\n" "$1" "$3" "$2"
    return 1
  fi
}

check_re() {   # check_re <opis> <regex> <faktyczne>
  if [[ "$3" =~ $2 ]]; then
    printf "   OK    %-32s %s\n" "$1" "$3"
  else
    printf "   BŁĄD  %-32s jest '%s'\n" "$1" "$3"
    return 1
  fi
}

test_postgres() {
  local q="docker exec ztbd-postgres psql -U $DB_USER -d $DB_NAME -tA -c"
  echo "   wersja: $($q 'SHOW server_version;')"
  check "shared_buffers"      "3GB" "$($q 'SHOW shared_buffers;')"      || return 1
  check "synchronous_commit"  "on"  "$($q 'SHOW synchronous_commit;')"  || return 1
  check "fsync"               "on"  "$($q 'SHOW fsync;')"               || return 1
}

test_mariadb() {
  local q="docker exec ztbd-mariadb mariadb -u $DB_USER -p$DB_PASSWORD -N -B -e"
  echo "   wersja: $($q 'SELECT VERSION();')"
  check "innodb_buffer_pool_size [GB]"   "3" "$($q 'SELECT @@innodb_buffer_pool_size DIV 1073741824;')" || return 1
  check "innodb_flush_log_at_trx_commit" "1" "$($q 'SELECT @@innodb_flush_log_at_trx_commit;')"         || return 1
  check "query_cache_type"               "OFF" "$($q 'SELECT @@query_cache_type;')"                     || return 1
}

test_mongodb() {
  local q="docker exec ztbd-mongodb mongosh --quiet --eval"
  echo "   wersja: $($q 'db.version()')"
  check "WiredTiger cache [GB]" "3" \
    "$($q "Math.round(db.serverStatus().wiredTiger.cache['maximum bytes configured'] / 1024 ** 3)")" || return 1
  check "replica set (PRIMARY)" "PRIMARY" \
    "$($q 'rs.status().members[0].stateStr')" || return 1
  check "transakcje (startSession)" "ok" \
    "$($q 'const s = db.getMongo().startSession(); s.startTransaction(); s.abortTransaction(); print("ok")')" || return 1
}

test_neo4j() {
  local q="docker exec ztbd-neo4j cypher-shell -u neo4j -p $DB_PASSWORD --format plain"
  echo "   wersja: $(docker exec ztbd-neo4j neo4j --version 2>/dev/null | tail -n1) (Community)"
  # Neo4j może zwrócić wartość jako "3g", "3.000GiB" albo w bajtach – sprawdzamy wzorcem.
  check_re "page cache (3 GB)" '^(3[gG]|3(\.0+)?GiB|3221225472)$' \
    "$($q "SHOW SETTINGS YIELD name, value WHERE name = 'server.memory.pagecache.size' RETURN value" | tail -n1 | tr -d '"')" || return 1
  check_re "heap max (1.5 GB)" '^(1536[mM]|1\.50*GiB|1610612736)$' \
    "$($q "SHOW SETTINGS YIELD name, value WHERE name = 'server.memory.heap.max_size' RETURN value" | tail -n1 | tr -d '"')" || return 1
}

for db in "${DBS[@]}"; do
  echo
  echo "=== $db ==="
  if ! "$DB" up "$db"; then
    echo "   BŁĄD  baza nie wstała – zobacz: ./scripts/db.sh logs $db"
    RESULT[$db]="NIE WSTAŁA"; fail=1; continue
  fi
  if "test_$db"; then RESULT[$db]="OK"; else RESULT[$db]="ZŁA KONFIGURACJA"; fail=1; fi
  echo "   limit RAM kontenera: $(docker inspect -f '{{.HostConfig.Memory}}' "ztbd-$db" | awk '{printf "%.0f GB", $1/1024^3}')"
done

"$DB" down >/dev/null 2>&1

echo
echo "=== Podsumowanie ==="
for db in "${DBS[@]}"; do printf "   %-10s %s\n" "$db" "${RESULT[$db]}"; done
exit $fail
