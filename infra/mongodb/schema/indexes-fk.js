// ZTBD – wariant indeksów "fk" (MongoDB): indeksy na polach-referencjach,
// odpowiednik infra/postgres/indexes/fk.sql i indeksów FK, które InnoDB zakłada sam.
//   ./scripts/db.sh indexes mongodb fk|full
// Bez nich każde find/$lookup po tych polach to COLLSCAN. Nazwy zaczynają się od ix_.
// (product_categories.product_id i inventory.product_id pokrywają indeksy pk_* ze schema.js.)

const specs = {
  categories:         [[{ parent_id: 1 }, 'ix_categories_parent']],
  addresses:          [[{ user_id: 1 }, 'ix_addresses_user']],
  products:           [[{ supplier_id: 1 }, 'ix_products_supplier']],
  product_categories: [[{ category_id: 1 }, 'ix_product_categories_cat']],
  inventory:          [[{ warehouse_id: 1 }, 'ix_inventory_warehouse']],
  orders:             [[{ user_id: 1 }, 'ix_orders_user'],
                       [{ address_id: 1 }, 'ix_orders_address'],
                       [{ 'items.product_id': 1 }, 'ix_orders_items_product']],  // multikey
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
