-- ZTBD – wariant indeksów "full", część poza FK (PostgreSQL)
--   ./scripts/db.sh indexes postgres full
-- Ten sam zestaw jest w mariadb/indexes/query.sql, mongodb/schema/indexes-query.js
-- i neo4j/schema/indexes-query.cypher – zmieniając tu, zmieńcie też tam.

-- Filtry/sortowania w scenariuszach READ/UPDATE/DELETE.
-- status ma tylko 5 wartości, więc sam status jest słabo selektywny – indeks
-- złożony ma sens dla "status + zakres dat", a created_at/price dla zakresów.
CREATE INDEX IF NOT EXISTS ix_orders_status_created    ON orders (status, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_created           ON orders (created_at);
CREATE INDEX IF NOT EXISTS ix_products_price           ON products (price);

-- JSON: indeks na JEDNYM atrybucie (color), tak samo jak w MariaDB i MongoDB.
-- Zapytanie musi używać tego wyrażenia: WHERE attributes->>'color' = 'czarny'.
-- (GIN na całym attributes byłby silniejszy niż indeksy w pozostałych bazach.)
CREATE INDEX IF NOT EXISTS ix_products_attr_color      ON products ((attributes->>'color'));

ANALYZE;
