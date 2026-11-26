-- ZTBD – po imporcie danych do MariaDB (./scripts/db.sh post-import mariadb)
-- AUTO_INCREMENT ustawia się sam po LOAD DATA, więc zostaje tylko odświeżenie
-- statystyk optymalizatora (odpowiednik ANALYZE w PostgreSQL).
ANALYZE TABLE categories, suppliers, warehouses, users, addresses, products,
              product_categories, inventory, orders, order_items, payments, shipments, reviews;
