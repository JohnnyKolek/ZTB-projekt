// ZTBD – indeksy do DRUGIEJ serii pomiarów (Neo4j)
//   ./scripts/db.sh indexes neo4j on|off
//
// Odpowiednik części 2 z infra/postgres/indexes/create.sql.
// Odpowiednika części 1 (indeksy na FK) nie ma: w grafie połączenie to relacja,
// a przejście po niej nie potrzebuje indeksu (index-free adjacency).
// Odpowiednika części 3 (JSON) też nie ma: attributes jest w Neo4j tekstem JSON.

CREATE INDEX ix_order_status_created IF NOT EXISTS FOR (n:Order)   ON (n.status, n.created_at);
CREATE INDEX ix_order_created        IF NOT EXISTS FOR (n:Order)   ON (n.created_at);
CREATE INDEX ix_product_price        IF NOT EXISTS FOR (n:Product) ON (n.price_cents);

CALL db.awaitIndexes(600);
