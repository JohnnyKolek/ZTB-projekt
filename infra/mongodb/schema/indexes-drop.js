// ZTBD – usuwa indeksy z indexes-create.js (powrót do serii "bez indeksów").
// _id i indeksy unikalne (uq_*) zostają.
for (const coll of db.getCollectionNames()) {
  for (const ix of db.getCollection(coll).getIndexes()) {
    if (ix.name.startsWith('ix_')) {
      db.getCollection(coll).dropIndex(ix.name);
      print(`dropped  ${coll}.${ix.name}`);
    }
  }
}
