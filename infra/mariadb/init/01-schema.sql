-- ZTBD – schemat relacyjny (MariaDB 12.3)
-- Wykonuje się automatycznie przy PIERWSZYM starcie pustej bazy, w bazie
-- z MARIADB_DATABASE (docker-entrypoint-initdb.d). Po zmianie: ./scripts/db.sh reset mariadb
--
-- Ten sam model co infra/postgres/init/01-schema.sql. Różnice typów:
--   jsonb      -> JSON (alias LONGTEXT z automatycznym CHECK json_valid)
--   timestamp  -> DATETIME(6) (bez strefy, jak timestamp w PostgreSQL; serwer działa w UTC)
--   boolean    -> BOOLEAN (TINYINT(1))
--   IDENTITY   -> AUTO_INCREMENT (po LOAD DATA licznik ustawia się sam na max(id)+1)
--
-- UWAGA: InnoDB automatycznie zakłada indeks na każdej kolumnie FK (nie da się go usunąć,
-- dopóki istnieje klucz obcy). PostgreSQL tego nie robi – patrz docs/schemat-danych.md.
-- Pozostałe indeksy: infra/mariadb/indexes/create.sql (./scripts/db.sh indexes mariadb on|off).

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Słowniki
-- ---------------------------------------------------------------------

CREATE TABLE categories (
    id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    parent_id   INT          NULL,
    name        VARCHAR(100) NOT NULL,
    CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE suppliers (
    id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    country     CHAR(2)      NOT NULL,
    email       VARCHAR(255) NOT NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE warehouses (
    id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    city        VARCHAR(100) NOT NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Klienci
-- ---------------------------------------------------------------------

CREATE TABLE users (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    email       VARCHAR(255) NOT NULL,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    created_at  DATETIME(6)  NOT NULL,
    CONSTRAINT uq_users_email UNIQUE (email)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE addresses (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT       NOT NULL,
    street      VARCHAR(255) NOT NULL,
    city        VARCHAR(100) NOT NULL,
    postal_code VARCHAR(10)  NOT NULL,
    country     CHAR(2)      NOT NULL,
    is_default  BOOLEAN      NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_addresses_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Katalog i magazyn
-- ---------------------------------------------------------------------

CREATE TABLE products (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT           NOT NULL,
    name        VARCHAR(255)  NOT NULL,
    sku         VARCHAR(32)   NOT NULL,
    price       DECIMAL(10,2) NOT NULL,
    attributes  JSON          NOT NULL DEFAULT '{}',
    CONSTRAINT uq_products_sku UNIQUE (sku),
    CONSTRAINT ck_products_price CHECK (price >= 0),
    CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE product_categories (
    product_id  BIGINT NOT NULL,
    category_id INT    NOT NULL,
    PRIMARY KEY (product_id, category_id),
    CONSTRAINT fk_pc_product  FOREIGN KEY (product_id)  REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_pc_category FOREIGN KEY (category_id) REFERENCES categories (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE inventory (
    product_id   BIGINT      NOT NULL,
    warehouse_id INT         NOT NULL,
    quantity     INT         NOT NULL,
    updated_at   DATETIME(6) NOT NULL,
    PRIMARY KEY (product_id, warehouse_id),
    CONSTRAINT ck_inventory_quantity CHECK (quantity >= 0),
    CONSTRAINT fk_inventory_product   FOREIGN KEY (product_id)   REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_inventory_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Zamówienia i logistyka
-- ---------------------------------------------------------------------

CREATE TABLE orders (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT        NOT NULL,
    address_id  BIGINT        NOT NULL,
    status      VARCHAR(20)   NOT NULL,
    total       DECIMAL(12,2) NOT NULL,
    created_at  DATETIME(6)   NOT NULL,
    CONSTRAINT ck_orders_status CHECK (status IN ('PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT ck_orders_total  CHECK (total >= 0),
    CONSTRAINT fk_orders_user    FOREIGN KEY (user_id)    REFERENCES users (id),
    CONSTRAINT fk_orders_address FOREIGN KEY (address_id) REFERENCES addresses (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- Główna tabela skalowana (100k → 10M wierszy).
CREATE TABLE order_items (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT        NOT NULL,
    order_id    BIGINT        NOT NULL,
    quantity    INT           NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,
    CONSTRAINT ck_order_items_quantity CHECK (quantity > 0),
    CONSTRAINT ck_order_items_price    CHECK (unit_price >= 0),
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_order_items_order   FOREIGN KEY (order_id)   REFERENCES orders (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE payments (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT        NOT NULL,
    method      VARCHAR(20)   NOT NULL,
    amount      DECIMAL(12,2) NOT NULL,
    status      VARCHAR(20)   NOT NULL,
    paid_at     DATETIME(6)   NULL,
    CONSTRAINT ck_payments_amount CHECK (amount >= 0),
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE shipments (
    id           BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    order_id     BIGINT      NOT NULL,
    warehouse_id INT         NOT NULL,
    carrier      VARCHAR(50) NOT NULL,
    status       VARCHAR(20) NOT NULL,
    shipped_at   DATETIME(6) NULL,
    CONSTRAINT fk_shipments_order     FOREIGN KEY (order_id)     REFERENCES orders (id) ON DELETE CASCADE,
    CONSTRAINT fk_shipments_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE reviews (
    id          BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT      NOT NULL,
    product_id  BIGINT      NOT NULL,
    rating      SMALLINT    NOT NULL,
    comment     TEXT        NULL,
    created_at  DATETIME(6) NOT NULL,
    CONSTRAINT ck_reviews_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_reviews_user    FOREIGN KEY (user_id)    REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
