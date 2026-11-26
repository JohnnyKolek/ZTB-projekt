# ZTBD – porównanie PostgreSQL, MariaDB, MongoDB i Neo4j

**Temat:** Porównanie wydajności i skalowalności operacji CRUD w systemach PostgreSQL, MariaDB, MongoDB i Neo4j na podstawie systemu obsługi zamówień e-commerce.

**Hipoteza (H2):** Różnice wydajności pomiędzy silnikami bazodanowymi rosną wraz ze wzrostem liczby rekordów.

Żeby to sprawdzić, te same operacje CRUD wykonujemy na 5 zbiorach o rosnącym rozmiarze (100k, 500k, 1m, 5m i 10m pozycji zamówień), w 4 bazach i w 3 wariantach indeksów.

## Stan prac

| Etap | Zakres | Stan |
|---|---|---|
| 1 | Infrastruktura: Docker Compose, konfiguracje baz z równymi limitami, `scripts/db.sh`, test dymny | gotowe |
| 2 | Schemat danych w 4 bazach, mapowanie modeli, warianty indeksów `none` / `fk` / `full` | gotowe |
| 3 | Generator zbiorów (`scripts/generate.sh`), ładowanie z pomiarem czasu (`scripts/load.sh`) | gotowe (powtórzenia 3× przeniesione do etapu 5) |
| 4 | Scenariusze CRUD i runner w Spring Boocie (`benchmark/`) | w toku: [propozycja scenariuszy](docs/scenariusze.md) do uzgodnienia |
| 5 | Pomiary: wszystkie scenariusze × bazy × rozmiary × warianty indeksów, ładowanie 3× (mediana) | do zrobienia |
| 6 | Wizualizacja wyników (`dashboard/`), sprawozdanie i prezentacja | do zrobienia |

## Bazy

| Baza | Wersja obrazu | Model danych w projekcie |
|---|---|---|
| PostgreSQL | 18 | relacyjny, `attributes` jako JSONB |
| MariaDB | 12.3 LTS | relacyjny, `attributes` jako JSON |
| MongoDB | 8.0 (jednowęzłowy replica set `rs0`) | dokumentowy, pozycje zamówień zagnieżdżone w `orders.items` |
| Neo4j | 2026.10 Community | grafowy, pozycje zamówień jako relacje `CONTAINS` |

Każdy kontener ma te same limity: **4 CPU, 6 GB RAM bez swapu**, a cache danych każdej bazy to 3 GB. Wersje i limity są w `infra/.env.example` (`*_VERSION`, `DB_CPUS`, `DB_MEMORY`). Dokładne wersje do sprawozdania: `./scripts/db.sh version <baza>`.

## Struktura repozytorium

```
infra/              docker-compose, konfiguracje baz, schemat (init/, schema/), warianty indeksów (indexes/)
scripts/            db.sh – uruchamianie/reset baz, schemat, indeksy
                    generate.sh – generowanie zbiorów do data/
                    load.sh – ładowanie zbioru z pomiarem czasu
                    smoke-test.sh – test dymny konfiguracji baz
Record_generation/  generator danych (Python 3.10+, biblioteka standardowa) i Import.ps1
data/               wygenerowane zbiory (CSV/JSON) – poza gitem, montowane do każdej bazy
benchmark/          aplikacja testowa / runner scenariuszy (Spring Boot) – etap 4
dashboard/          wizualizacja wyników (React) – etap 6
results/            wyniki pomiarów (CSV), na razie load-times.csv
docs/               dokumentacja, sprawozdanie, diagramy, prezentacja
```

## Dokumentacja

- [docs/schemat-danych.md](docs/schemat-danych.md) – schemat w 4 bazach, mapowanie tabel na kolekcje i graf, warianty indeksów, kolejność przygotowania bazy
- [docs/ladowanie-danych.md](docs/ladowanie-danych.md) – generowanie zbiorów, ładowanie, znaczenie kolumn w `results/load-times.csv`
- [docs/scenariusze.md](docs/scenariusze.md) – **propozycja** 24 scenariuszy CRUD (po 6 na operację) do wyboru i poprawek przed etapem 4
- [Record_generation/README.md](Record_generation/README.md) – opis generatora i formatów plików

## Wymagania

- Docker z Compose v2 (`docker compose version`)
- min. 16 GB RAM, dysk SSD z kilkudziesięcioma GB wolnego miejsca (sam zbiór 10m to ok. 4,3 GB)
- Python 3.10+ (generator)
- Windows: Docker Desktop z WSL2 + Git Bash lub WSL do uruchamiania skryptów z `scripts/`. Klienci baz na hoście nie są potrzebni, wszystko działa w kontenerach.

> **Windows / Docker Desktop:** maszyna WSL2 dostaje domyślnie tylko 50% RAM (8 GB przy 16 GB). Limit bazy (6 GB) się mieści, ale warto to sprawdzić w `docker info` (Total Memory). Większy limit ustawia się w `%UserProfile%\.wslconfig` (`[wsl2]` → `memory=12GB`).

## Szybki start

```bash
cp infra/.env.example infra/.env     # opcjonalnie – skrypty zrobią to same; ustawcie tu MACHINE (np. pc1)
chmod +x scripts/*.sh

./scripts/generate.sh 100k           # mały zbiór do data/100k
./scripts/load.sh postgres 100k      # reset bazy + import + pomiar czasu
./scripts/db.sh shell postgres       # konsola psql z załadowanymi danymi
./scripts/db.sh down                 # zatrzymuje wszystko
```

### Zarządzanie bazami (`scripts/db.sh`)

Zawsze działa tylko **jedna** baza: `up` najpierw zatrzymuje pozostałe. Bazy: `postgres | mariadb | mongodb | neo4j`.

```bash
./scripts/db.sh up      <baza>         # uruchom i poczekaj, aż będzie gotowa
./scripts/db.sh down    [baza]         # zatrzymaj (bez nazwy: wszystkie); dane zostają
./scripts/db.sh reset   <baza>         # czysta baza (usuwa dane!)
./scripts/db.sh status | logs <baza> | shell <baza> | version <baza>

./scripts/db.sh schema      <baza>     # MongoDB: kolekcje + walidatory (przed importem)
                                       # Neo4j: ograniczenia unikalności (po imporcie)
                                       # PostgreSQL/MariaDB: robi to init/ przy 1. starcie
./scripts/db.sh post-import <baza>     # sekwencje + ANALYZE (SQL), ograniczenia (Neo4j)
./scripts/db.sh indexes     <baza> none|fk|full
```

Warianty indeksów (szczegóły w [schemat-danych.md](docs/schemat-danych.md#warianty-indeksów-none-fk-full)):

- **none** – tylko PK, UNIQUE i klucze obce ze schematu (stan po `load.sh`),
- **fk** – dodatkowo indeksy na kolumnach FK,
- **full** – dodatkowo indeksy pod scenariusze (`orders(status, created_at)`, `orders(created_at)`, `products(price)`, `attributes.color`).

`indexes` najpierw usuwa wszystkie indeksy `ix_*`, więc warianty można przełączać w dowolnej kolejności.

Bez skryptu: `cd infra && docker compose --profile postgres up -d --wait`.

### Generowanie danych (`scripts/generate.sh`)

```bash
./scripts/generate.sh                # wszystkie rozmiary: 100k 500k 1m 5m 10m
./scripts/generate.sh 1m 10m         # wybrane rozmiary
```

Rozmiar to liczba pozycji zamówień (`order_items`), seed jest stały (42), więc każdy w zespole dostaje identyczne zbiory. Zbiory trafiają do `data/<rozmiar>`. Kompletny zbiór (z `manifest.json`) jest pomijany, przerwany jest kasowany i generowany od nowa. Zbiór 10m generuje się ok. 6,5 min.

### Ładowanie danych (`scripts/load.sh`)

```bash
./scripts/load.sh <postgres|mariadb|mongodb|neo4j|all> <rozmiar> [--keep]
./scripts/load.sh all 1m             # po kolei wszystkie 4 bazy
```

Każde wywołanie kasuje dane bazy, zakłada schemat, ładuje zbiór natywnym narzędziem bazy uruchamianym w jej kontenerze (`COPY`, `LOAD DATA LOCAL INFILE`, `mongoimport`, `neo4j-admin database import`), robi krok po imporcie, porównuje liczby rekordów z `manifest.json` i dopisuje wiersz do **`results/load-times.csv`** (`--keep` pomija zapis). Baza zostaje uruchomiona z danymi w wariancie indeksów `none`.

W CSV kolumna `machine` pochodzi z **`MACHINE` w `infra/.env`** – każdy wpisuje własną etykietę (`pc1`, `pc2`, …), nie nazwę komputera. Znaczenie pozostałych kolumn: [ladowanie-danych.md](docs/ladowanie-danych.md#co-mierzy-resultsload-timescsv).

Katalog `data/` jest zamontowany tylko do odczytu w każdym kontenerze: `/data-import` w PostgreSQL, MariaDB i MongoDB, `/import` w Neo4j.

## Dane połączeniowe (domyślne z `.env.example`)

| Baza | Adres | Login / hasło | Uwagi |
|---|---|---|---|
| PostgreSQL 18 | `jdbc:postgresql://localhost:5432/ecommerce` | bench / bench_pass | |
| MariaDB 12.3 LTS | `jdbc:mariadb://localhost:3306/ecommerce` | bench / bench_pass | root: root_pass |
| MongoDB 8.0 | `mongodb://localhost:27017/ecommerce?directConnection=true&w=1&journal=true` | bez autoryzacji | replica set `rs0` |
| Neo4j 2026.10 | `bolt://localhost:7687`, przeglądarka: http://localhost:7474 | neo4j / bench_pass | Community Edition |

## Zasady uczciwego porównania

Te ustawienia są już w konfiguracji – opisujcie je w sprawozdaniu w rozdziale o metodologii.

1. **Jedna baza naraz.** Testujemy po kolei, nic innego nie działa w tle.
2. **Identyczne zasoby:** każdy kontener ma 4 CPU i 6 GB RAM (bez swapu), a cache danych każdej bazy to 3 GB (`shared_buffers`, `innodb_buffer_pool_size`, WiredTiger `cacheSizeGB`, Neo4j page cache).
3. **Identyczna trwałość zapisu:** commit czeka na fsync dziennika we wszystkich bazach (`synchronous_commit=on`, `innodb_flush_log_at_trx_commit=1`, `journal=true` w Mongo, domyślne zachowanie Neo4j). Bez tego MongoDB „wygrywa” zapisy, bo nie czeka na dysk.
4. **Wyłączony query cache w MariaDB** – inaczej powtórzony SELECT zwraca wynik z pamięci podręcznej bez wykonania.
5. **Stały stan przed próbą:** po scenariuszach CREATE/UPDATE/DELETE baza wraca do stanu wyjściowego. Propozycja w [scenariusze.md](docs/scenariusze.md#wspólne-zasady-pomiaru): niemierzony `setup`/`teardown` zamiast przeładowywania bazy (do ustalenia w runnerze).
6. **Rozgrzewka** przed pomiarami i rozróżnienie zimnego/ciepłego cache.
7. **Wersje:** przed pomiarami zapiszcie dokładne wersje (`./scripts/db.sh version <baza>`) i parametry komputera.
8. **Powtórzenia:** czasy ładowania mają duży rozrzut (pliki z dysku Windows przez montowanie Docker Desktop), dlatego w etapie 5 każde ładowanie powtarzamy 3× i bierzemy medianę.

## Uwagi

- **Indeksy na FK:** InnoDB (MariaDB) automatycznie tworzy indeks na każdym kluczu obcym, PostgreSQL nie. Dlatego są warianty `none` i `fk`: przejście none → fk pokazuje, ile dają same indeksy FK, a fk → full resztę.
- **MongoDB działa jako jednowęzłowy replica set**, bo tylko wtedy obsługuje transakcje wielodokumentowe. Replica set inicjalizuje się sam przy pierwszym starcie (healthcheck).
- **Neo4j:** import pełny (`neo4j-admin`) tworzy bazę od zera przy zatrzymanym serwerze, dlatego ograniczenia unikalności powstają po imporcie (`post_import_s` w `load-times.csv`). APOC jest domyślnie wyłączony – odkomentujcie `NEO4J_PLUGINS` w `docker-compose.yml`, jeśli będzie potrzebny.
- **Import z hosta:** `Record_generation/Import.ps1` robi ten sam import z hosta, ale wymaga PowerShell 7.3 i klientów baz w PATH. Zalecany jest `scripts/load.sh`.
