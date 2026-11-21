import argparse
import csv
import json
from contextlib import ExitStack
from datetime import datetime, timedelta
from pathlib import Path
from random import Random


START = datetime(2024, 1, 1)
NULL = "__ZTBD_NULL__"
FIRST_NAMES = ("Alicja", "Anna", "Ewa", "Jan", "Kamil", "Marek", "Oliwia", "Zofia")
LAST_NAMES = ("Kowalski", "Nowak", "Wójcik", "Kamiński", "Mazur", "Król")
CITIES = ("Warszawa", "Kraków", "Łódź", "Gdańsk", "Poznań", "Wrocław")
STREETS = ("Leśna", "Krótka", "Kwiatowa", "Lipowa", "Parkowa")
PRODUCT_NAMES = ("Torba", "Lampa", "Termos", "Organizer", "Zegar", "Plecak")
STATUSES = ("PENDING", "PAID", "SHIPPED", "DELIVERED", "CANCELLED")

TABLES = {
    "categories": ("Category", "id parent_id name"),
    "suppliers": ("Supplier", "id name country email"),
    "warehouses": ("Warehouse", "id name city"),
    "users": ("User", "id email first_name last_name created_at"),
    "addresses": ("Address", "id user_id street city postal_code country is_default"),
    "products": ("Product", "id supplier_id name sku price attributes"),
    "product_categories": (None, "product_id category_id"),
    "inventory": (None, "product_id warehouse_id quantity updated_at"),
    "orders": ("Order", "id user_id address_id status total created_at"),
    "order_items": (None, "id product_id order_id quantity unit_price"),
    "payments": ("Payment", "id order_id method amount status paid_at"),
    "shipments": ("Shipment", "id order_id warehouse_id carrier status shipped_at"),
    "reviews": ("Review", "id user_id product_id rating comment created_at"),
}
COLUMNS = {table: columns.split() for table, (_, columns) in TABLES.items()}

EDGES = {
    "PARENT_CATEGORY": ("Category", "Category", ()),
    "HAS_ADDRESS": ("User", "Address", ()),
    "SUPPLIES": ("Supplier", "Product", ()),
    "IN_CATEGORY": ("Product", "Category", ()),
    "STOCKS": ("Warehouse", "Product", ("quantity:int", "updated_at:datetime")),
    "PLACED": ("User", "Order", ()),
    "SHIP_TO": ("Order", "Address", ()),
    "CONTAINS": ("Order", "Product", ("id:long", "quantity:int", "unit_price_cents:long")),
    "HAS_PAYMENT": ("Order", "Payment", ()),
    "HAS_SHIPMENT": ("Order", "Shipment", ()),
    "SHIPS_FROM": ("Shipment", "Warehouse", ()),
    "WROTE": ("User", "Review", ()),
    "REVIEWS_PRODUCT": ("Review", "Product", ()),
}

MONEY_COLUMNS = {"price", "total", "amount", "unit_price"}


def json_line(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def money(cents):
    whole, fraction = divmod(cents, 100)
    return f"{whole}.{fraction:02d}"


def utc(value):
    return value.isoformat(timespec="seconds") + "Z"


def graph_column(label, column):
    if column == "id":
        return f"id:ID({label})"
    if column in MONEY_COLUMNS:
        return f"{column}_cents:long"
    if column.endswith("_at"):
        return f"{column}:datetime"
    if column.endswith("_id"):
        return f"{column}:long"
    return {"rating": "rating:int", "is_default": "is_default:boolean"}.get(column, column)


def csv_value(value, *, graph=False):
    if value is None:
        return "" if graph else NULL
    if isinstance(value, datetime):
        return utc(value) if graph else value.isoformat(sep=" ", timespec="seconds")
    if isinstance(value, bool):
        return str(value).lower() if graph else int(value)
    if isinstance(value, dict):
        return json_line(value)
    return value


def mongo_row(row):
    result = {}
    for column, value in row.items():
        if column in MONEY_COLUMNS:
            value = {"$numberDecimal": money(value)}
        elif isinstance(value, datetime):
            value = {"$date": utc(value)}
        result[column] = value
    return result


class Dataset:
    def __init__(self, root, stack):
        self.counts = dict.fromkeys(TABLES, 0)
        self.sql = {}
        self.mongo = {}
        self.nodes = {}
        self.edges = {}
        for directory in ("sql", "mongo", "neo4j"):
            (root / directory).mkdir()

        def open_output(path):
            return stack.enter_context(path.open("w", encoding="utf-8", newline=""))

        def open_csv(path, header):
            writer = csv.writer(open_output(path), lineterminator="\n")
            writer.writerow(header)
            return writer

        for table, (label, _) in TABLES.items():
            columns = COLUMNS[table]
            self.sql[table] = open_csv(root / "sql" / f"{table}.csv", columns)
            if table != "order_items":
                self.mongo[table] = open_output(root / "mongo" / f"{table}.ndjson")
            if label:
                header = [graph_column(label, column) for column in columns]
                self.nodes[table] = open_csv(root / "neo4j" / f"node-{label}.csv", header)

        for edge, (start, end, properties) in EDGES.items():
            header = (f":START_ID({start})", f":END_ID({end})", *properties)
            self.edges[edge] = open_csv(root / "neo4j" / f"rel-{edge}.csv", header)

    def row(self, table, *values, items=None):
        row = dict(zip(COLUMNS[table], values, strict=True))
        self.sql[table].writerow(
            money(value) if column in MONEY_COLUMNS else csv_value(value)
            for column, value in row.items()
        )
        self.counts[table] += 1
        if table in self.nodes:
            self.nodes[table].writerow(csv_value(value, graph=True) for value in values)
        if table in self.mongo:
            if "id" in row:
                document_id = row["id"]
            else:
                second_key = "warehouse_id" if table == "inventory" else "category_id"
                document_id = f"{row['product_id']}:{row[second_key]}"
            document = {"_id": document_id, **mongo_row(row)}
            if items is not None:
                document["items"] = items
            self.mongo[table].write(json_line(document) + "\n")
        return row

    def edge(self, name, *values):
        self.edges[name].writerow(csv_value(value, graph=True) for value in values)


def generate(out, item_count, seed):
    random = Random(seed)
    pick = random.choice
    between = random.randint
    users = max(1, item_count // 12)
    products = max(1, item_count // 25)
    prices = [0]

    for category in range(1, 25):
        parent = None if category <= 4 else (category - 5) % 4 + 1
        out.row("categories", category, parent, f"Kategoria {category}")
        if parent is not None:
            out.edge("PARENT_CATEGORY", category, parent)
    for supplier in range(1, 13):
        out.row("suppliers", supplier, f"Dostawca {supplier}", "PL", f"supplier-{supplier}@example.test")
    for warehouse in range(1, 6):
        out.row("warehouses", warehouse, f"Magazyn {warehouse}", pick(CITIES))

    for user in range(1, users + 1):
        out.row("users", user, f"user-{user}@example.test", pick(FIRST_NAMES),
                pick(LAST_NAMES), START + timedelta(days=between(0, 364)))
        postal_code = f"{between(10, 99)}-{between(100, 999)}"
        out.row("addresses", user, user, f"{pick(STREETS)} {between(1, 90)}",
                pick(CITIES), postal_code, "PL", True)
        out.edge("HAS_ADDRESS", user, user)

    updated = START + timedelta(days=365)
    for product in range(1, products + 1):
        supplier = between(1, 12)
        category = between(5, 24)
        warehouse = between(1, 5)
        stock = between(0, 500)
        price = between(499, 249999)
        prices.append(price)
        attributes = {"color": pick(("zielony", "czarny", "biały")), "weight_g": between(100, 3000)}
        out.row("products", product, supplier, f"{pick(PRODUCT_NAMES)} {product}",
                f"SKU-{product}", price, attributes)
        out.row("product_categories", product, category)
        out.row("inventory", product, warehouse, stock, updated)
        out.edge("SUPPLIES", supplier, product)
        out.edge("IN_CATEGORY", product, category)
        out.edge("STOCKS", warehouse, product, stock, updated)

    order = item = payment = shipment = 0
    while item < item_count:
        order += 1
        user = between(1, users)
        size = min(between(1, 5), item_count - item)
        created = START + timedelta(days=366, minutes=between(0, 365 * 24 * 60 - 1))
        status = pick(STATUSES)
        total = 0
        items = []
        for _ in range(size):
            item += 1
            product = between(1, products)
            quantity = between(1, 4)
            price = prices[product]
            total += quantity * price
            row = out.row("order_items", item, product, order, quantity, price)
            items.append(mongo_row(row))
            out.edge("CONTAINS", order, product, item, quantity, price)

        out.row("orders", order, user, user, status, total, created, items=items)
        out.edge("PLACED", user, order)
        out.edge("SHIP_TO", order, user)
        shipped = status in ("SHIPPED", "DELIVERED")
        if shipped or status == "PAID":
            payment += 1
            out.row("payments", payment, order, pick(("CARD", "BLIK", "TRANSFER")),
                    total, "PAID", created + timedelta(hours=1))
            out.edge("HAS_PAYMENT", order, payment)
        if shipped:
            shipment += 1
            warehouse = between(1, 5)
            out.row("shipments", shipment, order, warehouse, pick(("DHL", "DPD", "InPost")),
                    status, created + timedelta(days=1))
            out.edge("HAS_SHIPMENT", order, shipment)
            out.edge("SHIPS_FROM", shipment, warehouse)

    for review in range(1, max(1, item_count // 15) + 1):
        user = between(1, users)
        product = between(1, products)
        comment = pick(("Polecam", "Zgodny z opisem", "Produkt spełnia oczekiwania", "Mógłby być lepszy"))
        created = START + timedelta(days=731, minutes=between(0, 43_199))
        out.row("reviews", review, user, product, between(1, 5), comment, created)
        out.edge("WROTE", user, review)
        out.edge("REVIEWS_PRODUCT", review, product)


def main():
    parser = argparse.ArgumentParser(description="Generate one ZTBD dataset for four databases.")
    parser.add_argument("order_items", type=int, help="number of order items (positive)")
    parser.add_argument("seed", type=int, help="random seed")
    parser.add_argument("output", type=Path, help="path to a new output directory")
    args = parser.parse_args()

    if args.order_items < 1:
        parser.error("order_items must be positive")
    root = args.output.resolve()
    try:
        root.mkdir(parents=True)
    except FileExistsError:
        parser.error(f"output path already exists: {root}")

    with ExitStack() as stack:
        dataset = Dataset(root, stack)
        generate(dataset, args.order_items, args.seed)

    manifest = {"format_version": 1, "seed": args.seed, "order_items": args.order_items,
                "counts": dataset.counts}
    (root / "manifest.json").write_text(json_line(manifest) + "\n", encoding="utf-8", newline="")
    print(f"Generated {args.order_items} order items in {root}")


if __name__ == "__main__":
    main()
