-- ZTBD – wariant indeksów "full", część poza FK (MariaDB)
--   ./scripts/db.sh indexes mariadb full
--
-- Wariant "fk" w MariaDB nic nie zakłada: indeksy na FK założył InnoDB przy CREATE TABLE
-- (odpowiednik infra/postgres/indexes/fk.sql), więc w MariaDB none = fk.

-- Filtry/sortowania w scenariuszach READ/UPDATE/DELETE.
CREATE INDEX IF NOT EXISTS ix_orders_status_created ON orders (status, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_created        ON orders (created_at);
CREATE INDEX IF NOT EXISTS ix_products_price        ON products (price);

-- JSON: MariaDB nie indeksuje dokumentu JSON bezpośrednio, więc indeksujemy atrybut
-- color przez wirtualną kolumnę wyliczaną. Zapytanie: WHERE attr_color = 'czarny'
-- (albo to samo wyrażenie JSON_VALUE(attributes, '$.color')).
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS attr_color VARCHAR(20)
        AS (JSON_VALUE(attributes, '$.color')) VIRTUAL;
CREATE INDEX IF NOT EXISTS ix_products_attr_color ON products (attr_color);

ANALYZE TABLE orders, products;
