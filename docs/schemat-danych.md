# Schemat danych w 4 bazach i mapowanie między modelami

Jeden model dziedziny (sklep internetowy, 13 tabel z ERD) zapisany na trzy sposoby: relacyjnie (PostgreSQL, MariaDB), jako dokumenty (MongoDB) i jako graf (Neo4j). Kształt danych w każdej bazie jest dokładnie taki, jaki produkuje generator (`Record_generation/generate.py`), więc pliki z `sql/`, `mongo/` i `neo4j/` ładują się bez przeróbek.

## Gdzie co leży

| Baza | Schemat | Indeksy (warianty fk / full) | Po imporcie |
|---|---|---|---|
| PostgreSQL | `infra/postgres/init/01-schema.sql` (auto przy 1. starcie) | `infra/postgres/indexes/fk.sql`, `query.sql`, `drop.sql` | `infra/postgres/post-import.sql` |
| MariaDB | `infra/mariadb/init/01-schema.sql` (auto przy 1. starcie) | `infra/mariadb/indexes/query.sql`, `drop.sql` | `infra/mariadb/post-import.sql` |
| MongoDB | `infra/mongodb/schema/schema.js` | `infra/mongodb/schema/indexes-fk.js`, `indexes-query.js`, `indexes-drop.js` | – |
| Neo4j | `infra/neo4j/schema/constraints.cypher` | `infra/neo4j/schema/indexes-query.cypher`, `indexes-drop.cypher` | ograniczenia (ten sam plik) |

## Kolejność przygotowania bazy

```bash
# PostgreSQL / MariaDB – schemat tworzy się sam przy pierwszym starcie pustego wolumenu
./scripts/db.sh reset postgres
#   ... import (Record_generation/Import.ps1 albo COPY / LOAD DATA) ...
./scripts/db.sh post-import postgres     # sekwencje IDENTITY = max(id)+1, ANALYZE

# MongoDB – kolekcje z walidatorami PRZED importem
./scripts/db.sh reset mongodb
./scripts/db.sh schema mongodb
#   ... mongoimport ...

# Neo4j – import pełny tworzy bazę od zera, więc ograniczenia PO imporcie
./scripts/db.sh down
#   ... neo4j-admin database import full (przy zatrzymanej bazie) ...
./scripts/db.sh up neo4j
./scripts/db.sh schema neo4j

# Warianty indeksów do pomiarów (w dowolnej kolejności)
./scripts/db.sh indexes <baza> none     # tylko PK / UNIQUE / FK ze schematu
./scripts/db.sh indexes <baza> fk       # + indeksy na kluczach obcych
./scripts/db.sh indexes <baza> full     # + indeksy pod scenariusze
```

Neo4j z Dockera da się zaimportować jednorazowym kontenerem na tym samym wolumenie (z katalogu `infra/`, baza zatrzymana). Nazwa bazy (`neo4j`, jedyna w Community) musi stać **przed** listą `--nodes`/`--relationships`, bo te opcje przyjmują wiele plików i połknęłyby ją jako plik:

```bash
docker compose --profile neo4j run --rm --no-deps neo4j \
  neo4j-admin database import full neo4j --overwrite-destination \
  --id-type=integer --legacy-style-quoting=false \
  --nodes=User=/import/<zbiór>/neo4j/node-User.csv ... \
  --relationships=PLACED=/import/<zbiór>/neo4j/rel-PLACED.csv ...
```

## Warianty indeksów: none, fk, full

**none** to tylko to, co jest częścią **schematu**, a nie optymalizacji. Ma być takie samo we wszystkich bazach:

| | PostgreSQL | MariaDB | MongoDB | Neo4j |
|---|---|---|---|---|
| Klucz główny | PK (B-tree) | PK (indeks klastrowy) | `_id`, a dla PK, których `_id` nie pokrywa: `orders.items.id` (unikalny), `product_categories(product_id, category_id)`, `inventory(product_id, warehouse_id)` | unikalność `id` na każdej etykiecie i `CONTAINS.id` |
| UNIQUE `users.email`, `products.sku` | tak | tak | indeks unikalny | ograniczenie unikalności |
| Klucze obce | tak, **bez indeksu** | tak, **z indeksem** (InnoDB zakłada go sam) | brak (zwykłe pola) | relacje w grafie |

W MongoDB indeksy odpowiadające PK są w `schema.js` (nazwy `pk_*`), bo bez nich operacja na pojedynczej pozycji zamówienia albo stanie magazynowym byłaby w serii none pełnym skanem, a w SQL i Neo4j trafiałaby w indeks klucza.

**fk** dokłada indeksy na kolumnach FK (nazwy `ix_*`). W PostgreSQL i MongoDB to realna zmiana. W MariaDB nic się nie zmienia, bo InnoDB wymaga indeksu na każdej kolumnie FK i nie pozwala go skasować, dopóki istnieje klucz obcy. W Neo4j też nic, bo połączenie to relacja, a przejście po niej nie potrzebuje indeksu. Dzięki temu w sprawozdaniu da się rozdzielić dwa efekty: none → fk pokazuje, ile dają same indeksy FK (i tłumaczy przewagę MariaDB w serii none), a fk → full pokazuje resztę.

**full** dokłada indeksy pod scenariusze, ten sam zestaw w każdej bazie:

1. `orders(status, created_at)`, `orders(created_at)`, `products(price)`,
2. JSON na jednym atrybucie `attributes.color`: PostgreSQL indeks na wyrażeniu `(attributes->>'color')`, MariaDB indeks na wirtualnej kolumnie `attr_color = JSON_VALUE(attributes,'$.color')`, MongoDB `attributes.color`. W Neo4j `attributes` jest tekstem JSON, więc scenariusze JSON porównują PostgreSQL, MariaDB i MongoDB. GIN na całym `attributes` w PostgreSQL celowo pominięty, bo pokrywałby wszystkie klucze, a pozostałe bazy tylko `color`. Scenariusze JSON filtrują więc po `color`.

`db.sh indexes` zawsze najpierw usuwa wszystkie `ix_*`, więc warianty można przełączać w dowolnej kolejności. W Neo4j skrypt czeka, aż wszystkie indeksy będą `ONLINE` (`db.awaitIndexes` po przekroczeniu czasu nie zgłasza błędu, a pomiar na budującym się indeksie byłby przekłamany).

### Selektywność danych z generatora

`status` ma 5 wartości, a `color` 3, rozłożone równomiernie. Filtr po samym statusie albo kolorze zwraca 20–33% wierszy, więc planery i tak wybiorą pełny skan i indeks nic nie pokaże. Scenariusze, które mają mierzyć efekt indeksu, powinny filtrować zakresem (`created_at`, `price`) albo statusem razem z zakresem dat. Zapytania po statusie/kolorze zostawcie jako przykład, że indeks na mało selektywnej kolumnie nie pomaga.

## Model relacyjny (PostgreSQL, MariaDB)

13 tabel dokładnie jak w ERD. Typy podano w notacji PostgreSQL. W MariaDB `jsonb` → `JSON`, `timestamp` → `DATETIME(6)`, `boolean` → `BOOLEAN`, `IDENTITY` → `AUTO_INCREMENT`.

- Klucze `id` są `GENERATED BY DEFAULT AS IDENTITY` / `AUTO_INCREMENT`: import wstawia gotowe id z generatora, a INSERT-y w benchmarku dostają kolejne. W PostgreSQL po imporcie trzeba przestawić sekwencje (`db.sh post-import postgres`), w MariaDB licznik przestawia się sam.
- `ON DELETE CASCADE` jest tam, gdzie wiersz podrzędny nie ma sensu bez nadrzędnego: pozycje, płatności i wysyłki zamówienia, adresy i recenzje użytkownika, kategorie, stany i recenzje produktu. MongoDB i Neo4j nie mają kaskad, więc to samo trzeba zrobić jawnie w zapytaniu – patrz [Równoważne operacje DELETE](#równoważne-operacje-delete).
- CHECK: `orders.status` ze słownika (`PENDING, PAID, SHIPPED, DELIVERED, CANCELLED`), `reviews.rating` 1–5, ilości > 0 (stan magazynu ≥ 0), kwoty ≥ 0.
- Daty bez strefy czasowej, w UTC (serwer MariaDB ma `default-time-zone = '+00:00'`).
- Porównanie napisów jest binarne w każdej bazie: MariaDB `utf8mb4_bin` w każdej tabeli, PostgreSQL z locale `C.UTF-8` (`POSTGRES_INITDB_ARGS` w `docker-compose.yml`), MongoDB i Neo4j porównują binarnie domyślnie. Z domyślną kolacją `utf8mb4_unicode_ci` MariaDB ignorowałaby wielkość liter i akcenty, więc `WHERE email = ...`, `LIKE` i `ORDER BY name` dawałyby inne wyniki niż w pozostałych bazach.

## Model dokumentowy (MongoDB)

12 kolekcji. Każdy dokument ma `_id` równy `id` z SQL (pole `id` jest dodatkowo powtórzone, tak jak zapisuje je generator).

| Relacja w ERD | MongoDB | Dlaczego |
|---|---|---|
| `orders` 1–N `order_items` | **osadzone** `orders.items[]` | pozycje czyta się i zapisuje zawsze razem z zamówieniem, a zamówienie ma 1–5 pozycji. Jeden dokument = jedno zamówienie z pozycjami, bez transakcji i bez złączenia |
| `orders` → `users`, `addresses` | referencja `user_id`, `address_id` | użytkownik ma wiele zamówień, rośnie bez ograniczeń |
| `orders` 1–N `payments`, `shipments` | osobne kolekcje z `order_id` | tak robi generator; płatność i wysyłka powstają w innym momencie niż zamówienie (UPDATE statusu bez przepisywania zamówienia) |
| `products` N–M `categories` | kolekcja `product_categories`, `_id: "produkt:kategoria"` | 1:1 z tabelą łączącą, łatwe porównanie z SQL |
| `products` N–M `warehouses` (`inventory`) | kolekcja `inventory`, `_id: "produkt:magazyn"` | stan magazynu zmienia się często, niezależnie od produktu |
| `users` 1–N `addresses`, `reviews` | osobne kolekcje z `user_id` | adres jest wskazywany przez zamówienia, recenzje rosną bez ograniczeń |
| `products.attributes` | zagnieżdżony obiekt | dane półustrukturalne, bez stałego schematu |

Walidatory `$jsonSchema` (`validationLevel: strict`, `validationAction: error`) pilnują wymaganych pól, typów (`int/long`, `decimal` dla kwot, `date`), słownika statusów, zakresu oceny 1–5, ilości ≥ 1 i co najmniej jednej pozycji w zamówieniu. To odpowiednik NOT NULL + CHECK z SQL. Kluczy obcych MongoDB nie sprawdza, więc spójność `user_id`, `product_id` itd. jest po stronie aplikacji.

Liczba pozycji zamówień w MongoDB to suma długości `orders.items` (nie ma kolekcji `order_items`). Scenariusze na „pojedynczej pozycji” w MongoDB działają przez `orders.items` (`$elemMatch`, `items.$`, `$pull`/`$push`).

## Model grafowy (Neo4j)

10 etykiet węzłów (tabele z własnym `id`) i 13 typów relacji. Tabele łączące i `order_items` stają się relacjami z właściwościami.

```
(:Category)-[:PARENT_CATEGORY]->(:Category)
(:User)-[:HAS_ADDRESS]->(:Address)
(:User)-[:PLACED]->(:Order)-[:SHIP_TO]->(:Address)
(:Order)-[:CONTAINS {id, quantity, unit_price_cents}]->(:Product)      ← order_items
(:Order)-[:HAS_PAYMENT]->(:Payment)
(:Order)-[:HAS_SHIPMENT]->(:Shipment)-[:SHIPS_FROM]->(:Warehouse)
(:Supplier)-[:SUPPLIES]->(:Product)-[:IN_CATEGORY]->(:Category)        ← product_categories
(:Warehouse)-[:STOCKS {quantity, updated_at}]->(:Product)              ← inventory
(:User)-[:WROTE]->(:Review)-[:REVIEWS_PRODUCT]->(:Product)
```

- Węzły mają też kolumny FK jako właściwości (`Order.user_id` itd.), bo importer przepisuje cały wiersz. Do nawigacji używajcie relacji, nie tych pól.
- Kwoty są liczbami całkowitymi w groszach (`price_cents`, `total_cents`, `amount_cents`, `unit_price_cents`), bo Neo4j nie ma typu dziesiętnego. Przy porównaniu wyników dzielcie przez 100.
- `attributes` jest tekstem JSON (Neo4j nie ma zagnieżdżonych map we właściwościach).
- Daty to `DATETIME` w UTC.
- Ograniczenia (`constraints.cypher`): unikalność `id` na każdej etykiecie, `User.email`, `Product.sku` i `CONTAINS.id` (to PK `order_items`). Community Edition nie ma ograniczeń istnienia, typu ani klucza (tylko Enterprise), więc wymagane pola pilnuje generator/aplikacja.

## Równoważne operacje DELETE

Każdy scenariusz DELETE musi usuwać **te same dane** w każdej bazie. SQL robi część pracy kaskadą, a w MongoDB i Neo4j trzeba ją wykonać jawnie. Bez tego porównanie mierzyłoby różną ilość pracy.

**Zamówienie** = zamówienie + jego pozycje + płatności + wysyłki.

```sql
-- PostgreSQL / MariaDB: kaskada usuwa order_items, payments, shipments
DELETE FROM orders WHERE id = :id;
```
```js
// MongoDB: pozycje są w dokumencie, płatności i wysyłki trzeba usunąć osobno (w jednej transakcji)
session.withTransaction(async () => {
  await db.orders.deleteOne({ _id: id }, { session });
  await db.payments.deleteMany({ order_id: id }, { session });
  await db.shipments.deleteMany({ order_id: id }, { session });
});
```
```cypher
// Neo4j: samo DETACH DELETE zostawiłoby węzły Payment i Shipment jako sieroty
MATCH (o:Order {id: $id})
OPTIONAL MATCH (o)-[:HAS_PAYMENT|HAS_SHIPMENT]->(x)
DETACH DELETE o, x
```

W MongoDB `deleteMany` po `order_id` bez indeksu to pełny skan `payments` i `shipments`, tak samo jak kaskada w PostgreSQL w wariancie none. Wariant fk wyrównuje to w obu bazach.

**Produkt, użytkownik.** W SQL produkt z pozycjami zamówień i użytkownik z zamówieniami są **chronione** przez FK (DELETE kończy się błędem). MongoDB i Neo4j ich nie chronią: usunęłyby produkt, a Neo4j przez `DETACH DELETE` usunąłby też relacje `CONTAINS`, czyli zmieniłby zawartość zamówień. Dlatego scenariusze DELETE produktów i użytkowników dotyczą tylko wierszy **bez zamówień**. Usuwane razem z nimi dane zależne:

| Usuwany | SQL (kaskada) | MongoDB (jawnie) | Neo4j (jawnie) |
|---|---|---|---|
| produkt | `product_categories`, `inventory`, `reviews` | `product_categories`, `inventory`, `reviews` po `product_id` | `DETACH DELETE` produktu + węzły `Review` przez `REVIEWS_PRODUCT` |
| użytkownik | `addresses`, `reviews` | `addresses`, `reviews` po `user_id` | `DETACH DELETE` użytkownika + węzły `Address` (`HAS_ADDRESS`) i `Review` (`WROTE`) |
| pozycja zamówienia | `DELETE FROM order_items WHERE id = :id` | `updateOne({'items.id': id}, {$pull: {items: {id}}})` | `MATCH ()-[r:CONTAINS {id: $id}]->() DELETE r` |

Usunięcie pozycji zmienia sumę zamówienia. Jeśli scenariusz ma przeliczać `total`, musi to robić we wszystkich bazach.

## Uwagi do sprawozdania

- **Uproszczenia generatora.** Każdy produkt ma dokładnie 1 kategorię i 1 magazyn, a każdy użytkownik 1 adres (adres o tym samym id). Relacje N–M z ERD są więc w danych w praktyce 1–N, a złączenia przez `product_categories` i `inventory` są lżejsze niż w ogólnym modelu. To nie błąd schematu, tylko cecha zbioru, którą trzeba opisać (albo zmienić w generatorze).
- **Koszt walidacji.** Walidatory `$jsonSchema` w MongoDB i CHECK w SQL kosztują przy INSERT/UPDATE. Neo4j Community nie ma odpowiednika (brak ograniczeń istnienia i typu), więc zapisuje bez tej kontroli.
- **Rozmiar Neo4j.** Węzły trzymają kopie kluczy obcych (`Order.user_id` itd.) obok relacji, bo importer przepisuje cały wiersz. To zawyża rozmiar bazy przy porównaniu zajętości dysku. W zapytaniach używajcie relacji, bo tych właściwości nikt nie indeksuje.
- **MariaDB i `LOAD DATA LOCAL`.** `benchmark.cnf` ma `local_infile = ON`, a `Record_generation/Import.ps1` wywołuje klienta z `--local-infile=1`, więc `LOAD DATA LOCAL INFILE` działa po obu stronach. Ustawienie serwera wczytuje się przy starcie kontenera (`./scripts/db.sh up mariadb`), reset bazy nie jest potrzebny.

## Mapowanie tabel

| Tabela (SQL) | MongoDB | Neo4j |
|---|---|---|
| categories | `categories` | `(:Category)` + `PARENT_CATEGORY` zamiast `parent_id` |
| suppliers | `suppliers` | `(:Supplier)` |
| warehouses | `warehouses` | `(:Warehouse)` |
| users | `users` | `(:User)` |
| addresses | `addresses` | `(:Address)` + `HAS_ADDRESS` |
| products | `products` | `(:Product)` + `SUPPLIES` |
| product_categories | `product_categories` | relacja `IN_CATEGORY` |
| inventory | `inventory` | relacja `STOCKS {quantity, updated_at}` |
| orders | `orders` | `(:Order)` + `PLACED`, `SHIP_TO` |
| order_items | `orders.items[]` (osadzone) | relacja `CONTAINS {id, quantity, unit_price_cents}` |
| payments | `payments` | `(:Payment)` + `HAS_PAYMENT` |
| shipments | `shipments` | `(:Shipment)` + `HAS_SHIPMENT`, `SHIPS_FROM` |
| reviews | `reviews` | `(:Review)` + `WROTE`, `REVIEWS_PRODUCT` |

| Typ (PostgreSQL) | MariaDB | MongoDB | Neo4j |
|---|---|---|---|
| bigint / integer | BIGINT / INT | int / long | INTEGER (64-bit) |
| numeric(p,2) | DECIMAL(p,2) | Decimal128 | INTEGER w groszach |
| timestamp | DATETIME(6) | Date (UTC) | DATETIME (UTC) |
| boolean | BOOLEAN | bool | BOOLEAN |
| jsonb | JSON | obiekt | STRING (tekst JSON) |
| varchar / text | VARCHAR / TEXT | string | STRING |

## Sprawdzone

Próbka z generatora (`generate.py 3000 42`) zaimportowana do wszystkich 4 baz w kontenerach z `docker-compose.yml`: liczności zgodne z `manifest.json` (3000 pozycji w `order_items`, sumie `orders.items` i relacjach `CONTAINS`), INSERT po imporcie dostaje kolejne id, walidatory MongoDB i ograniczenia Neo4j odrzucają błędne/zdublowane dane, `indexes none|fk|full` przełącza się we wszystkich bazach, operacje DELETE z sekcji wyżej usuwają w każdej bazie te same dane.
