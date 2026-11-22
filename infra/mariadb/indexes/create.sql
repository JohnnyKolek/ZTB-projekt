-- ZTBD – indeksy do DRUGIEJ serii pomiarów (MariaDB)
--   ./scripts/db.sh indexes mariadb on     (ten plik)
--   ./scripts/db.sh indexes mariadb off    (drop.sql)
--
-- Indeksów na FK tu NIE MA – InnoDB założył je już przy CREATE TABLE
-- (to odpowiednik części 1 w infra/postgres/indexes/create.sql).

-- 2. Indeksy pod filtry/sortowania w scenariuszach READ/UPDATE/DELETE.
CREATE INDEX IF NOT EXISTS ix_orders_status_created ON orders (status, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_created        ON orders (created_at);
CREATE INDEX IF NOT EXISTS ix_products_price        ON products (price);

-- 3. JSON. MariaDB nie ma indeksu na całym dokumencie JSON (jak GIN w PostgreSQL),
--    więc indeksujemy wybrany atrybut przez wirtualną kolumnę wyliczaną.
--    Zapytanie musi używać tego samego wyrażenia albo kolumny attr_color.
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS attr_color VARCHAR(20)
        AS (JSON_VALUE(attributes, '$.color')) VIRTUAL;
CREATE INDEX IF NOT EXISTS ix_products_attr_color ON products (attr_color);

ANALYZE TABLE orders, products;
