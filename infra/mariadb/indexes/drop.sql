-- ZTBD – usuwa indeksy z create.sql (powrót do serii "bez indeksów").
-- PK, UNIQUE i FK (razem z indeksami FK założonymi przez InnoDB) zostają.
DROP INDEX IF EXISTS ix_orders_status_created ON orders;
DROP INDEX IF EXISTS ix_orders_created        ON orders;
DROP INDEX IF EXISTS ix_products_price        ON products;
DROP INDEX IF EXISTS ix_products_attr_color   ON products;
ALTER TABLE products DROP COLUMN IF EXISTS attr_color;

ANALYZE TABLE orders, products;
