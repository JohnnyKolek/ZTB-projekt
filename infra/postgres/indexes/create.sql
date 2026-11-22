-- ZTBD – indeksy do DRUGIEJ serii pomiarów (PostgreSQL)
--   ./scripts/db.sh indexes postgres on     (ten plik)
--   ./scripts/db.sh indexes postgres off    (drop.sql)
--
-- Ten sam zestaw (co do sensu) jest w mariadb/indexes, mongodb/schema/indexes-create.js
-- i neo4j/schema/indexes-create.cypher – zmieniając tu, zmieńcie też tam.
-- Wszystkie nazwy zaczynają się od ix_, żeby dało się je łatwo znaleźć i usunąć.

-- 1. Indeksy na kluczach obcych.
--    InnoDB (MariaDB) zakłada je SAM przy FOREIGN KEY i nie da się ich usunąć,
--    PostgreSQL nie zakłada ich wcale. Dlatego w serii "bez indeksów" MariaDB
--    ma je zawsze – opiszcie to w sprawozdaniu (patrz docs/schemat-danych.md).
CREATE INDEX IF NOT EXISTS ix_categories_parent        ON categories (parent_id);
CREATE INDEX IF NOT EXISTS ix_addresses_user           ON addresses (user_id);
CREATE INDEX IF NOT EXISTS ix_products_supplier        ON products (supplier_id);
CREATE INDEX IF NOT EXISTS ix_product_categories_cat   ON product_categories (category_id);
CREATE INDEX IF NOT EXISTS ix_inventory_warehouse      ON inventory (warehouse_id);
CREATE INDEX IF NOT EXISTS ix_orders_user              ON orders (user_id);
CREATE INDEX IF NOT EXISTS ix_orders_address           ON orders (address_id);
CREATE INDEX IF NOT EXISTS ix_order_items_order        ON order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_order_items_product      ON order_items (product_id);
CREATE INDEX IF NOT EXISTS ix_payments_order           ON payments (order_id);
CREATE INDEX IF NOT EXISTS ix_shipments_order          ON shipments (order_id);
CREATE INDEX IF NOT EXISTS ix_shipments_warehouse      ON shipments (warehouse_id);
CREATE INDEX IF NOT EXISTS ix_reviews_user             ON reviews (user_id);
CREATE INDEX IF NOT EXISTS ix_reviews_product          ON reviews (product_id);

-- 2. Indeksy pod filtry/sortowania w scenariuszach READ/UPDATE/DELETE.
CREATE INDEX IF NOT EXISTS ix_orders_status_created    ON orders (status, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_created           ON orders (created_at);
CREATE INDEX IF NOT EXISTS ix_products_price           ON products (price);

-- 3. JSON (scenariusze PostgreSQL JSONB vs MongoDB).
--    GIN jsonb_path_ops obsługuje operator @>, np. attributes @> '{"color":"czarny"}'.
CREATE INDEX IF NOT EXISTS ix_products_attributes      ON products USING gin (attributes jsonb_path_ops);

ANALYZE;
