// ZTBD – model dokumentowy (MongoDB 8.0): kolekcje z walidatorami $jsonSchema.
//
//   ./scripts/db.sh schema mongodb        (PRZED importem – mongoimport wstawia do gotowych kolekcji)
//
// Skrypt jest idempotentny: nowe kolekcje tworzy, istniejącym podmienia walidator (collMod).
// Dokumenty mają kształt z generatora (Record_generation/generate.py, katalog mongo/):
//   * _id = id z modelu relacyjnego (liczba), pole "id" jest powtórzone w dokumencie,
//   * kwoty: Decimal128, daty: Date (UTC), attributes: obiekt,
//   * orders.items[] – OSADZONE pozycje zamówienia (zamiast kolekcji order_items),
//   * product_categories i inventory – osobne kolekcje z _id "product_id:drugi_klucz".
// Uzasadnienie embed/reference: docs/schemat-danych.md.
//
// Poza _id są tu tylko indeksy, które w SQL są częścią schematu (PK i UNIQUE),
// żeby seria "bez indeksów" była w każdej bazie taka sama.
// Pozostałe indeksy: indexes-fk.js, indexes-query.js, indexes-drop.js (db.sh indexes).

const INT = { bsonType: ['int', 'long'] };
const INT_MIN = (min) => ({ bsonType: ['int', 'long'], minimum: min });
const STR = (max) => ({ bsonType: 'string', maxLength: max });
const MONEY = { bsonType: 'decimal', minimum: 0 };
const DATE = { bsonType: 'date' };
const NULLABLE = (s) => ({ ...s, bsonType: [].concat(s.bsonType, 'null') });

const ORDER_STATUSES = ['PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED'];

function object(required, properties) {
  return { $jsonSchema: { bsonType: 'object', required, properties } };
}

const collections = {
  // --- słowniki --------------------------------------------------------
  categories: object(['_id', 'id', 'name'], {
    _id: INT, id: INT,
    parent_id: NULLABLE(INT),
    name: STR(100),
  }),
  suppliers: object(['_id', 'id', 'name', 'country', 'email'], {
    _id: INT, id: INT,
    name: STR(200), country: { bsonType: 'string', minLength: 2, maxLength: 2 }, email: STR(255),
  }),
  warehouses: object(['_id', 'id', 'name', 'city'], {
    _id: INT, id: INT,
    name: STR(100), city: STR(100),
  }),

  // --- klienci ---------------------------------------------------------
  users: object(['_id', 'id', 'email', 'first_name', 'last_name', 'created_at'], {
    _id: INT, id: INT,
    email: STR(255), first_name: STR(100), last_name: STR(100), created_at: DATE,
  }),
  addresses: object(['_id', 'id', 'user_id', 'street', 'city', 'postal_code', 'country', 'is_default'], {
    _id: INT, id: INT, user_id: INT,
    street: STR(255), city: STR(100), postal_code: STR(10),
    country: { bsonType: 'string', minLength: 2, maxLength: 2 },
    is_default: { bsonType: 'bool' },
  }),

  // --- katalog i magazyn -----------------------------------------------
  products: object(['_id', 'id', 'supplier_id', 'name', 'sku', 'price', 'attributes'], {
    _id: INT, id: INT, supplier_id: INT,
    name: STR(255), sku: STR(32), price: MONEY,
    attributes: { bsonType: 'object' },          // dane półustrukturalne – bez sztywnego schematu
  }),
  product_categories: object(['_id', 'product_id', 'category_id'], {
    _id: { bsonType: 'string', pattern: '^[0-9]+:[0-9]+$' },
    product_id: INT, category_id: INT,
  }),
  inventory: object(['_id', 'product_id', 'warehouse_id', 'quantity', 'updated_at'], {
    _id: { bsonType: 'string', pattern: '^[0-9]+:[0-9]+$' },
    product_id: INT, warehouse_id: INT, quantity: INT_MIN(0), updated_at: DATE,
  }),

  // --- zamówienia i logistyka ------------------------------------------
  orders: object(['_id', 'id', 'user_id', 'address_id', 'status', 'total', 'created_at', 'items'], {
    _id: INT, id: INT, user_id: INT, address_id: INT,
    status: { enum: ORDER_STATUSES },
    total: MONEY, created_at: DATE,
    items: {                                      // = tabela order_items
      bsonType: 'array',
      minItems: 1,
      items: {
        bsonType: 'object',
        required: ['id', 'product_id', 'order_id', 'quantity', 'unit_price'],
        properties: {
          id: INT, product_id: INT, order_id: INT,
          quantity: INT_MIN(1), unit_price: MONEY,
        },
      },
    },
  }),
  payments: object(['_id', 'id', 'order_id', 'method', 'amount', 'status'], {
    _id: INT, id: INT, order_id: INT,
    method: STR(20), amount: MONEY, status: STR(20), paid_at: NULLABLE(DATE),
  }),
  shipments: object(['_id', 'id', 'order_id', 'warehouse_id', 'carrier', 'status'], {
    _id: INT, id: INT, order_id: INT, warehouse_id: INT,
    carrier: STR(50), status: STR(20), shipped_at: NULLABLE(DATE),
  }),
  reviews: object(['_id', 'id', 'user_id', 'product_id', 'rating', 'created_at'], {
    _id: INT, id: INT, user_id: INT, product_id: INT,
    rating: { bsonType: ['int', 'long'], minimum: 1, maximum: 5 },
    comment: NULLABLE({ bsonType: 'string' }),
    created_at: DATE,
  }),
};

const existing = new Set(db.getCollectionNames());
for (const [name, validator] of Object.entries(collections)) {
  const options = { validator, validationLevel: 'strict', validationAction: 'error' };
  if (existing.has(name)) {
    db.runCommand({ collMod: name, ...options });
    print(`collMod      ${name}`);
  } else {
    db.createCollection(name, options);
    print(`created      ${name}`);
  }
}

// Odpowiedniki UNIQUE z SQL (w SQL też tworzą indeks, więc są we wszystkich wariantach).
db.users.createIndex({ email: 1 }, { unique: true, name: 'uq_users_email' });
db.products.createIndex({ sku: 1 }, { unique: true, name: 'uq_products_sku' });

// Odpowiedniki PRIMARY KEY z SQL, których nie pokrywa _id:
//  * order_items.id -> orders.items.id (PK pozycji; SQL ma go w PK, Neo4j w contains_id),
//  * PK (product_id, warehouse_id/category_id) w SQL pokrywa też wyszukiwanie po samym
//    product_id; _id "p:c" jest stringiem, więc potrzebny jest indeks na polach.
db.orders.createIndex({ 'items.id': 1 }, { unique: true, name: 'pk_orders_items_id' });
db.product_categories.createIndex({ product_id: 1, category_id: 1 }, { unique: true, name: 'pk_product_categories' });
db.inventory.createIndex({ product_id: 1, warehouse_id: 1 }, { unique: true, name: 'pk_inventory' });
print('indexes      uq_users_email, uq_products_sku, pk_orders_items_id, pk_product_categories, pk_inventory');
