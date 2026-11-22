// ZTBD – usuwa indeksy z indexes-query.cypher (wariant "none"/"fk"); db.sh uruchamia go też przed "full".
// Indeksy założone przez ograniczenia unikalności zostają.
DROP INDEX ix_order_status_created IF EXISTS;
DROP INDEX ix_order_created        IF EXISTS;
DROP INDEX ix_product_price        IF EXISTS;
