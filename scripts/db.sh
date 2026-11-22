#!/usr/bin/env bash
# Zarządzanie bazami do benchmarku ZTBD.
# Zawsze działa tylko JEDNA baza – "up" najpierw zatrzymuje pozostałe.
#
# Użycie:
#   ./scripts/db.sh up      <baza>   uruchom bazę (i poczekaj, aż będzie gotowa)
#   ./scripts/db.sh down    [baza]   zatrzymaj bazę (bez nazwy: wszystkie); dane zostają
#   ./scripts/db.sh reset   <baza>   usuń dane bazy i uruchom ją od zera
#   ./scripts/db.sh status           pokaż, co działa
#   ./scripts/db.sh logs    <baza>   logi bazy
#   ./scripts/db.sh shell   <baza>   konsola bazy (psql / mariadb / mongosh / cypher-shell)
#   ./scripts/db.sh version <baza>   dokładna wersja serwera (do sprawozdania)
#
# Schemat (infra/<baza>/..., opis: docs/schemat-danych.md):
#   ./scripts/db.sh schema      <baza>        MongoDB: kolekcje + walidatory (PRZED importem)
#                                             Neo4j: ograniczenia unikalności (PO imporcie)
#                                             PostgreSQL/MariaDB: robi to init/ przy 1. starcie
#   ./scripts/db.sh post-import <baza>        po imporcie: sekwencje + ANALYZE (SQL), ograniczenia (Neo4j)
#   ./scripts/db.sh indexes     <baza> on|off indeksy do drugiej serii pomiarów
#
# Bazy: postgres | mariadb | mongodb | neo4j

set -euo pipefail

DBS=(postgres mariadb mongodb neo4j)
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../infra" && pwd)"
cd "$INFRA_DIR"

if [[ ! -f .env ]]; then
  echo "Brak infra/.env – kopiuję z .env.example"
  cp .env.example .env
fi
set -a; source .env; set +a

compose_all() {
  local args=() d
  for d in "${DBS[@]}"; do args+=(--profile "$d"); done
  docker compose "${args[@]}" "$@"
}

require_db() {
  local db="${1:-}"
  for d in "${DBS[@]}"; do [[ "$d" == "$db" ]] && return 0; done
  echo "Nieznana baza: '${db}'. Dostępne: ${DBS[*]}" >&2
  exit 1
}

cmd="${1:-}"; db="${2:-}"

# run_file <baza> <plik> – wykonuje plik skryptu w działającej bazie
run_file() {
  local file="$2"
  [[ -f "$file" ]] || { echo "Brak pliku: infra/$file" >&2; exit 1; }
  echo ">> $1: $file"
  case "$1" in
    postgres) docker exec -i ztbd-postgres psql -X -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$file" ;;
    mariadb)  docker exec -i ztbd-mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$file" ;;
    # --eval zamiast ścieżki: Git Bash na Windowsie nie przerobi niczego na ścieżkę Windows
    mongodb)  docker exec ztbd-mongodb mongosh --quiet "$DB_NAME" --eval "$(cat "$file")" ;;
    neo4j)    docker exec -i ztbd-neo4j cypher-shell -u neo4j -p "$DB_PASSWORD" --format plain < "$file" ;;
  esac
}

case "$cmd" in
  up)
    require_db "$db"
    echo ">> Zatrzymuję pozostałe bazy"
    compose_all stop
    echo ">> Uruchamiam $db (czekam na healthcheck)"
    docker compose --profile "$db" up -d --wait "$db"
    echo ">> $db gotowa"
    ;;

  down)
    if [[ -z "$db" ]]; then
      compose_all stop
    else
      require_db "$db"
      docker compose --profile "$db" stop "$db"
    fi
    ;;

  reset)
    require_db "$db"
    echo ">> Usuwam kontener i dane: $db"
    docker compose --profile "$db" rm -sfv "$db"
    docker volume rm -f "ztbd_${db}_data" >/dev/null
    [[ "$db" == "neo4j" ]] && docker volume rm -f ztbd_neo4j_logs >/dev/null
    "$0" up "$db"
    ;;

  status)
    compose_all ps
    ;;

  logs)
    require_db "$db"
    docker compose --profile "$db" logs -f --tail 100 "$db"
    ;;

  shell)
    require_db "$db"
    case "$db" in
      postgres) docker exec -it ztbd-postgres psql -U "$DB_USER" -d "$DB_NAME" ;;
      mariadb)  docker exec -it ztbd-mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" ;;
      mongodb)  docker exec -it ztbd-mongodb mongosh "$DB_NAME" ;;
      neo4j)    docker exec -it ztbd-neo4j cypher-shell -u neo4j -p "$DB_PASSWORD" ;;
    esac
    ;;

  version)
    require_db "$db"
    case "$db" in
      postgres) docker exec ztbd-postgres psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT version();" ;;
      mariadb)  docker exec ztbd-mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" -N -e "SELECT VERSION();" ;;
      mongodb)  docker exec ztbd-mongodb mongosh --quiet --eval "db.version()" ;;
      neo4j)    docker exec ztbd-neo4j cypher-shell -u neo4j -p "$DB_PASSWORD" --format plain \
                  "CALL dbms.components() YIELD name, versions, edition RETURN name, versions[0], edition" ;;
    esac
    ;;

  schema)
    require_db "$db"
    case "$db" in
      postgres|mariadb)
        echo "Schemat $db tworzy się sam przy pierwszym starcie pustej bazy (infra/$db/init/)."
        echo "Po zmianie DDL: ./scripts/db.sh reset $db" ;;
      mongodb) run_file mongodb mongodb/schema/schema.js ;;
      neo4j)   run_file neo4j neo4j/schema/constraints.cypher ;;
    esac
    ;;

  post-import)
    require_db "$db"
    case "$db" in
      postgres|mariadb) run_file "$db" "$db/post-import.sql" ;;
      mongodb)          echo "MongoDB: nic do zrobienia (walidatory i indeksy unikalne zakłada 'schema')." ;;
      neo4j)            run_file neo4j neo4j/schema/constraints.cypher ;;
    esac
    ;;

  indexes)
    require_db "$db"
    mode="${3:-}"
    [[ "$mode" == on || "$mode" == off ]] || { echo "Użycie: $0 indexes <baza> on|off" >&2; exit 1; }
    case "$db" in
      postgres|mariadb) f="$db/indexes/$([[ $mode == on ]] && echo create || echo drop).sql" ;;
      mongodb)          f="mongodb/schema/indexes-$([[ $mode == on ]] && echo create || echo drop).js" ;;
      neo4j)            f="neo4j/schema/indexes-$([[ $mode == on ]] && echo create || echo drop).cypher" ;;
    esac
    run_file "$db" "$f"
    ;;

  *)
    sed -n '2,22p' "$0"
    exit 1
    ;;
esac
