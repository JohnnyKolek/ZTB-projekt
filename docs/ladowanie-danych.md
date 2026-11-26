# Generowanie i ładowanie danych

Dwa skrypty (Git Bash / WSL / Linux, z katalogu repozytorium) i jedna komenda na bazę i rozmiar. Na hoście potrzebne są tylko Docker i Python 3.10+, bo każde narzędzie importu działa w kontenerze swojej bazy, do którego `data/` jest zamontowane.

## 1. Generowanie zbiorów

```bash
./scripts/generate.sh              # 100k 500k 1m 5m 10m -> data/<rozmiar>
./scripts/generate.sh 1m           # jeden rozmiar
```

Rozmiar to liczba pozycji zamówień (`order_items`), seed 42. Kompletny zbiór (z `manifest.json`) jest pomijany, przerwany kasowany i generowany od nowa. Pozostałe tabele rosną proporcjonalnie:

| Zbiór | order_items | orders | users / addresses | products | reviews | na dysku | generowanie |
|---|---|---|---|---|---|---|---|
| 100k | 100 000 | ~33 tys. | 8 333 | 4 000 | 6 666 | 41 MB | 4 s |
| 500k | 500 000 | ~167 tys. | 41 666 | 20 000 | 33 333 | 208 MB | 32 s |
| 1m | 1 000 000 | ~333 tys. | 83 333 | 40 000 | 66 666 | 420 MB | 37 s |
| 5m | 5 000 000 | ~1,67 mln | 416 666 | 200 000 | 333 333 | 2,2 GB | 3,5 min |
| 10m | 10 000 000 | 3 332 418 | 833 333 | 400 000 | 666 666 | 4,3 GB | 6,5 min |

## 2. Ładowanie (reset + import + pomiar)

```bash
./scripts/load.sh postgres 1m      # jedna baza
./scripts/load.sh all 10m          # po kolei wszystkie 4 bazy
./scripts/load.sh neo4j 100k --keep   # próba bez zapisu do CSV
```

Każde wywołanie kasuje dane bazy i ładuje zbiór od zera, więc to jest też sposób na **reset stanu** przed kolejną serią pomiarów:

1. reset (`db.sh reset`; Neo4j: usunięcie wolumenu),
2. schemat (PostgreSQL/MariaDB: `init/` przy starcie, MongoDB: `schema.js` z walidatorami i indeksami PK),
3. import natywnym narzędziem w kontenerze bazy:

   | Baza | Narzędzie | Pliki |
   |---|---|---|
   | PostgreSQL | `COPY ... FROM` (serwerowy) | `data/<zbiór>/sql/*.csv` |
   | MariaDB | `LOAD DATA LOCAL INFILE` | `data/<zbiór>/sql/*.csv` |
   | MongoDB | `mongoimport` | `data/<zbiór>/mongo/*.ndjson` |
   | Neo4j | `neo4j-admin database import full` (jednorazowy kontener, serwer zatrzymany) | `data/<zbiór>/neo4j/*.csv` |

4. krok po imporcie (`db.sh post-import`: sekwencje + ANALYZE w SQL, ograniczenia unikalności w Neo4j),
5. porównanie liczby rekordów z `manifest.json` (pozycje zamówień: `order_items`, suma `orders.items` w MongoDB, relacje `CONTAINS` w Neo4j),
6. dopisanie wiersza do `results/load-times.csv`.

Po zakończeniu baza zostaje uruchomiona z danymi, w wariancie indeksów `none`. Wariant zmienia się przez `./scripts/db.sh indexes <baza> fk|full`.

## Co mierzy `results/load-times.csv`

| Kolumna | Znaczenie |
|---|---|
| `import_s` | samo ładowanie danych. PostgreSQL i MariaDB utrzymują przy tym PK, UNIQUE i FK ze schematu, MongoDB indeksy `_id` i `pk_*`, a Neo4j buduje sam magazyn grafu |
| `post_import_s` | krok po imporcie. W Neo4j to budowa ograniczeń unikalności (indeksów na `id`), które w pozostałych bazach powstają już w trakcie importu, dlatego do porównań używajcie `total_s` |
| `total_s` | `import_s + post_import_s` |
| `disk_mb` | rozmiar katalogu danych serwera po załadowaniu (`du`), razem z WAL/redo logiem i journalem. MariaDB ma stały narzut ok. 1 GB na `innodb_log_file_size`, a MongoDB ok. 200 MB |
| `counts_ok` | czy liczby rekordów zgadzają się z manifestem |
| `cpus`, `memory`, `machine` | limity kontenera i etykieta komputera, na którym mierzono (`MACHINE` w `infra/.env`, np. `pc1`, `pc2`; celowo nie nazwa urządzenia) |

Czas startu serwera i resetu nie jest wliczany. Każdy pomiar to jedno ładowanie. Kolejne wywołania dopisują wiersze, więc przy powtórzeniach w sprawozdaniu można brać średnią.

**Uwaga na rozrzut.** Pierwsza seria (26.11.2026) dała dla 5m czasy dłuższe niż dla 10m (PostgreSQL 212 s, MariaDB 177 s), a powtórka tego samego zbioru zaraz potem 79 s i 69 s. Pliki z `data/` są czytane z dysku Windows przez montowanie Docker Desktop, więc obciążenie laptopa i cache plików mocno wpływają na wynik. Do sprawozdania każde ładowanie warto powtórzyć co najmniej 3 razy i brać medianę.

`Record_generation/Import.ps1` robi ten sam import z hosta (wymaga PowerShell 7.3 i klientów baz w PATH). `scripts/load.sh` używa tych samych poleceń, ale w kontenerach.
