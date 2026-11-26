// ZTBD – wariant indeksów "full" (Neo4j)
//   ./scripts/db.sh indexes neo4j full
//
// Odpowiednik infra/postgres/indexes/query.sql.
// Wariant "fk" w Neo4j nic nie zakłada (none = fk): połączenie to relacja, a przejście
// po niej nie potrzebuje indeksu (index-free adjacency). Właściwości user_id, order_id
// itd. na węzłach to kopie z importu – nie są indeksowane, nie używajcie ich w zapytaniach.
// Indeksu JSON nie ma: attributes jest w Neo4j tekstem JSON.
//
// db.sh po tym pliku czeka, aż wszystkie indeksy będą ONLINE (awaitIndexes po timeoucie
// nie zgłasza błędu, a pomiar na budującym się indeksie byłby przekłamany).

CREATE INDEX ix_order_status_created IF NOT EXISTS FOR (n:Order)   ON (n.status, n.created_at);
CREATE INDEX ix_order_created        IF NOT EXISTS FOR (n:Order)   ON (n.created_at);
CREATE INDEX ix_product_price        IF NOT EXISTS FOR (n:Product) ON (n.price_cents);

CALL db.awaitIndexes(600);
