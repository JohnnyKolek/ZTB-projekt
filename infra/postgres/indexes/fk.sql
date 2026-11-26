-- ZTBD – wariant indeksów "fk": indeksy na kluczach obcych (PostgreSQL)
--   ./scripts/db.sh indexes postgres fk     (drop.sql + ten plik)
--   ./scripts/db.sh indexes postgres full   (drop.sql + ten plik + query.sql)
--
-- InnoDB (MariaDB) zakłada te indeksy SAM przy FOREIGN KEY i nie da się ich usunąć,
-- PostgreSQL nie zakłada ich wcale. Wariant "fk" wyrównuje więc PostgreSQL do MariaDB:
-- porównanie none -> fk pokazuje, ile dają same indeksy FK, a fk -> full resztę.
-- Wszystkie nazwy zaczynają się od ix_, żeby drop.sql mógł je znaleźć.
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

ANALYZE;
