// ZTBD – usuwa wszystkie indeksy ix_* (wariant "none"); db.sh uruchamia go też przed "fk" i "full".
// _id oraz indeksy ze schema.js (uq_*, pk_*) zostają.
for (const coll of db.getCollectionNames()) {
  for (const ix of db.getCollection(coll).getIndexes()) {
    if (ix.name.startsWith('ix_')) {
      db.getCollection(coll).dropIndex(ix.name);
      print(`dropped  ${coll}.${ix.name}`);
    }
  }
}
