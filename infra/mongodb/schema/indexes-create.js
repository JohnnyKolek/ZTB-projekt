// ZTBD – indeksy do DRUGIEJ serii pomiarów (MongoDB)
//   ./scripts/db.sh indexes mongodb on|off
// Odpowiedniki infra/postgres/indexes/create.sql. Nazwy zaczynają się od ix_.

const specs = {
  // 1. "klucze obce" – w MongoDB to zwykłe pola, bez indeksu każde $lookup / find po nich to COLLSCAN
  categories:         [[{ parent_id: 1 }, 'ix_categories_parent']],
  addresses:          [[{ user_id: 1 }, 'ix_addresses_user']],
  products:           [[{ supplier_id: 1 }, 'ix_products_supplier'],
                       [{ price: 1 }, 'ix_products_price'],
                       [{ 'attributes.color': 1 }, 'ix_products_attr_color']],   // 3. JSON
  product_categories: [[{ product_id: 1 }, 'ix_product_categories_product'],
                       [{ category_id: 1 }, 'ix_product_categories_cat']],
  inventory:          [[{ product_id: 1 }, 'ix_inventory_product'],
                       [{ warehouse_id: 1 }, 'ix_inventory_warehouse']],
  orders:             [[{ user_id: 1 }, 'ix_orders_user'],
                       [{ address_id: 1 }, 'ix_orders_address'],
                       [{ 'items.product_id': 1 }, 'ix_orders_items_product'],   // multikey
                       [{ 'items.id': 1 }, 'ix_orders_items_id'],                // = PK order_items
  // 2. filtry/sortowania
                       [{ status: 1, created_at: 1 }, 'ix_orders_status_created'],
                       [{ created_at: 1 }, 'ix_orders_created']],
  payments:           [[{ order_id: 1 }, 'ix_payments_order']],
  shipments:          [[{ order_id: 1 }, 'ix_shipments_order'],
                       [{ warehouse_id: 1 }, 'ix_shipments_warehouse']],
  reviews:            [[{ user_id: 1 }, 'ix_reviews_user'],
                       [{ product_id: 1 }, 'ix_reviews_product']],
};

for (const [coll, list] of Object.entries(specs)) {
  for (const [keys, name] of list) {
    db.getCollection(coll).createIndex(keys, { name });
    print(`created  ${coll}.${name}`);
  }
}
