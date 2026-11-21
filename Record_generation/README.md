# Generowanie danych testowych ZTBD

Generator wymaga Pythona 3.10 lub nowszego i korzysta z biblioteki standardowej. Nazwy, adresy i opisy pochodzą ze słowników w kodzie, a identyfikatory i wartości liczbowe powstają z użyciem stałych reguł i ziarna losowania.

```powershell
python generate.py 1000 42 generated/sample
```

Argumenty to kolejno liczba pozycji zamówień, seed oraz ścieżka do nowego katalogu. Generator pozostawia dotychczasowe zbiory na dysku. Po przerwaniu generowania wybierz nowy katalog. Zapis `manifest.json` oznacza, że generowanie wszystkich plików się zakończyło.

```powershell
python generate.py 500000 42 generated/500k
python generate.py 1000000 42 generated/1m
python generate.py 10000000 42 generated/10m
```

Rozmiary oznaczają liczbę pozycji w `order_items`. Klienci, produkty i recenzje rosną proporcjonalnie do tego parametru. Słowniki mają po 24 kategorie, 12 dostawców i 5 magazynów. Identyczne parametry przy tej samej wersji Pythona odtwarzają ten sam zbiór. Wersja w Pythonie używa własnej sekwencji losowania. Zbiory o różnych rozmiarach generują własne populacje klientów i produktów.

| Katalog | Zawartość |
|---|---|
| `sql/` | 13 plików CSV z nagłówkami według ERD, wspólnych dla PostgreSQL i MariaDB |
| `mongo/` | Extended JSON po jednym dokumencie na wiersz. Pozycje zamówień są w `orders.items`, kwoty mają typ Decimal128, a daty są zapisane w UTC. |
| `neo4j/` | CSV z nagłówkami importera Neo4j. Pozycje zamówień to relacje `CONTAINS`, przypisania kategorii to `IN_CATEGORY`, a stany magazynowe to `STOCKS`. Kwoty są zapisane jako całkowita liczba groszy, a `attributes` jako tekst JSON. |

## Import

Uruchom polecenia z tego folderu w PowerShell 7.3 lub nowszym. Dla PostgreSQL i MariaDB najpierw utwórz pustą bazę z tabelami i kolumnami z ERD. Nazwy i kolejność kolumn znajdziesz w nagłówkach CSV. Jeśli `id` w PostgreSQL korzysta z sekwencji, po załadowaniu danych ustaw wartość sekwencji zgodnie z największym zaimportowanym ID przed testami INSERT. Zainstaluj klientów baz i dodaj ich do PATH. Skrypt używa ich standardowych ustawień połączenia. W MariaDB włącz obsługę `LOCAL INFILE` na serwerze. Jeśli import przerwie się w połowie, ponów go na pustej bazie.

```powershell
./Import.ps1 postgresql generated/sample ztbd
./Import.ps1 mariadb    generated/sample ztbd
./Import.ps1 mongodb    generated/sample ztbd
./Import.ps1 neo4j      generated/sample ztbd
```

MongoDB używa `mongoimport` i zakłada puste kolekcje docelowe. Import Neo4j uruchom na hoście lub w kontenerze z dostępem do plików i katalogu danych Neo4j. Polecenie wykonuje pełny import do nowej bazy. Zależnie od edycji i konfiguracji po imporcie trzeba jeszcze udostępnić bazę w instancji.

Po imporcie porównaj liczbę rekordów z `manifest.json`. Pozycje zamówień licz przez `COUNT(*)` w `order_items`, sumę długości `orders.items` w MongoDB i liczbę relacji `CONTAINS` w Neo4j.
