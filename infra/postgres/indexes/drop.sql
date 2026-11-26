-- ZTBD – usuwa wszystkie indeksy ix_* (wariant "none"); db.sh uruchamia go też przed "fk" i "full".
-- PK, UNIQUE i FK zostają.
DO $$
DECLARE
    ix record;
BEGIN
    FOR ix IN SELECT indexname FROM pg_indexes
              WHERE schemaname = 'public' AND indexname LIKE 'ix\_%'
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', ix.indexname);
    END LOOP;
END
$$;

ANALYZE;
