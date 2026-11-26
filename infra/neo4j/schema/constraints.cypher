// ZTBD – model grafowy (Neo4j 2026.10 Community): ograniczenia.
//
//   ./scripts/db.sh schema neo4j        (PO imporcie – neo4j-admin database import full
//                                        tworzy bazę od zera i nie przenosi ograniczeń)
//
// Węzły i relacje tworzy importer z plików generatora (Record_generation, katalog neo4j/).
// Model opisuje docs/schemat-danych.md.
//
// Community Edition obsługuje tylko ograniczenia UNIKALNOŚCI (każde zakłada indeks RANGE).
// Ograniczenia istnienia (IS NOT NULL), typu (IS :: INTEGER) i klucza (NODE KEY) są tylko
// w Enterprise – pilnuje ich generator/aplikacja.
//
// Unikalność id = odpowiednik PRIMARY KEY, a email/sku = odpowiednik UNIQUE z SQL.
// Bez nich każde wyszukanie węzła po id to pełny skan etykiety, a MERGE nie jest bezpieczny.

CREATE CONSTRAINT category_id  IF NOT EXISTS FOR (n:Category)  REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT supplier_id  IF NOT EXISTS FOR (n:Supplier)  REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT warehouse_id IF NOT EXISTS FOR (n:Warehouse) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT user_id      IF NOT EXISTS FOR (n:User)      REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT address_id   IF NOT EXISTS FOR (n:Address)   REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT product_id   IF NOT EXISTS FOR (n:Product)   REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT order_id     IF NOT EXISTS FOR (n:Order)     REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT payment_id   IF NOT EXISTS FOR (n:Payment)   REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT shipment_id  IF NOT EXISTS FOR (n:Shipment)  REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT review_id    IF NOT EXISTS FOR (n:Review)    REQUIRE n.id IS UNIQUE;

CREATE CONSTRAINT user_email   IF NOT EXISTS FOR (n:User)      REQUIRE n.email IS UNIQUE;
CREATE CONSTRAINT product_sku  IF NOT EXISTS FOR (n:Product)   REQUIRE n.sku IS UNIQUE;

// Pozycja zamówienia (order_items) to relacja (:Order)-[:CONTAINS]->(:Product),
// więc jej "PK" jest na relacji.
CREATE CONSTRAINT contains_id  IF NOT EXISTS FOR ()-[r:CONTAINS]-() REQUIRE r.id IS UNIQUE;

CALL db.awaitIndexes(600);
