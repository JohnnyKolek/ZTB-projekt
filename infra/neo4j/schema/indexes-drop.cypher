// ZTBD – usuwa indeksy z indexes-create.cypher (powrót do serii "bez indeksów").
// Indeksy założone przez ograniczenia unikalności zostają.
DROP INDEX ix_order_status_created IF EXISTS;
DROP INDEX ix_order_created        IF EXISTS;
DROP INDEX ix_product_price        IF EXISTS;
