// ZTBD – wariant indeksów "full", część poza FK (MongoDB)
//   ./scripts/db.sh indexes mongodb full    (indexes-fk.js + ten plik)
// Odpowiednik infra/postgres/indexes/query.sql.

const specs = {
  orders:   [[{ status: 1, created_at: 1 }, 'ix_orders_status_created'],
             [{ created_at: 1 }, 'ix_orders_created']],
  products: [[{ price: 1 }, 'ix_products_price'],
             [{ 'attributes.color': 1 }, 'ix_products_attr_color']],   // JSON: jeden atrybut, jak w SQL
};

for (const [coll, list] of Object.entries(specs)) {
  for (const [keys, name] of list) {
    db.getCollection(coll).createIndex(keys, { name });
    print(`created  ${coll}.${name}`);
  }
}
