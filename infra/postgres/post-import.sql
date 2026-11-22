-- ZTBD – po imporcie danych do PostgreSQL (./scripts/db.sh post-import postgres)
--
-- 1. Import (COPY) wstawia jawne wartości id, więc sekwencje kolumn IDENTITY
--    zostają na 1. Bez tego pierwszy INSERT w benchmarku dostałby id=1
--    i błąd duplikatu klucza.
-- 2. ANALYZE zbiera statystyki dla planera – tak samo jak ANALYZE TABLE w MariaDB.

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['categories', 'suppliers', 'warehouses', 'users', 'addresses',
                             'products', 'orders', 'order_items', 'payments', 'shipments', 'reviews']
    LOOP
        EXECUTE format(
            'SELECT setval(pg_get_serial_sequence(%L, ''id''), COALESCE((SELECT max(id) FROM %I), 0) + 1, false)',
            t, t);
    END LOOP;
END
$$;

ANALYZE;
