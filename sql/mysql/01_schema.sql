-- ============================================================================
-- AMAZON PRIME DBMS  |  01_schema.sql  |  Target: MySQL 8.0+
-- 24 tables: DDL with PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK, DEFAULT
-- (generated from scripts/templates/schema.tpl.sql by scripts/build_sql.py)
-- ============================================================================
CREATE DATABASE IF NOT EXISTS amazon_prime_db CHARACTER SET utf8mb4;
USE amazon_prime_db;

-- ---------- drop in reverse dependency order (safe re-run) ------------------
DROP TABLE IF EXISTS music_play;
DROP TABLE IF EXISTS music_track;
DROP TABLE IF EXISTS music_artist;
DROP TABLE IF EXISTS watchlist;
DROP TABLE IF EXISTS watch_history;
DROP TABLE IF EXISTS episode;
DROP TABLE IF EXISTS video_content;
DROP TABLE IF EXISTS review;
DROP TABLE IF EXISTS payment;
DROP TABLE IF EXISTS shipment;
DROP TABLE IF EXISTS order_item;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS seller;
DROP TABLE IF EXISTS payment_method;
DROP TABLE IF EXISTS subscription_audit;
DROP TABLE IF EXISTS subscription;
DROP TABLE IF EXISTS plan_benefit;
DROP TABLE IF EXISTS benefit;
DROP TABLE IF EXISTS plan;
DROP TABLE IF EXISTS profile;
DROP TABLE IF EXISTS address;
DROP TABLE IF EXISTS customer;

-- ============================================================================
-- MODULE 1 : CUSTOMER & ACCOUNT
-- ============================================================================
CREATE TABLE customer (
    customer_id    INT AUTO_INCREMENT PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE,
    phone          VARCHAR(15),
    password_hash  VARCHAR(64)  NOT NULL,
    date_of_birth  DATE,
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE address (
    address_id   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT          NOT NULL,
    label        VARCHAR(20)  NOT NULL DEFAULT 'Home',
    line1        VARCHAR(150) NOT NULL,
    city         VARCHAR(60)  NOT NULL,
    state        VARCHAR(60)  NOT NULL,
    pincode      VARCHAR(10)  NOT NULL,
    country      VARCHAR(40)  NOT NULL DEFAULT 'India',
    is_default   BOOLEAN      NOT NULL DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A Prime account can have several viewing profiles (family sharing, kids)
CREATE TABLE profile (
    profile_id    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT         NOT NULL,
    profile_name  VARCHAR(40) NOT NULL,
    is_kids       BOOLEAN     NOT NULL DEFAULT 0,
    UNIQUE (customer_id, profile_name),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MODULE 2 : PRIME MEMBERSHIP (plans, benefits, subscriptions)
-- ============================================================================
CREATE TABLE plan (
    plan_id          INT AUTO_INCREMENT PRIMARY KEY,
    plan_name        VARCHAR(60)  NOT NULL UNIQUE,
    price            DECIMAL(8,2) NOT NULL CHECK (price >= 0),
    duration_months  INT          NOT NULL CHECK (duration_months > 0),
    max_profiles     INT          NOT NULL DEFAULT 6 CHECK (max_profiles BETWEEN 1 AND 6),
    has_ads          BOOLEAN      NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE benefit (
    benefit_id    INT AUTO_INCREMENT PRIMARY KEY,
    benefit_name  VARCHAR(60)  NOT NULL UNIQUE,
    description   VARCHAR(200)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- M:N between plan and benefit
CREATE TABLE plan_benefit (
    plan_id     INT NOT NULL,
    benefit_id  INT NOT NULL,
    PRIMARY KEY (plan_id, benefit_id),
    FOREIGN KEY (plan_id)    REFERENCES plan(plan_id)       ON DELETE CASCADE,
    FOREIGN KEY (benefit_id) REFERENCES benefit(benefit_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE subscription (
    subscription_id  INT AUTO_INCREMENT PRIMARY KEY,
    customer_id      INT         NOT NULL,
    plan_id          INT         NOT NULL,
    start_date       DATE        NOT NULL,
    end_date         DATE        NOT NULL,
    status           VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','EXPIRED','CANCELLED')),
    auto_renew       BOOLEAN     NOT NULL DEFAULT 1,
    CHECK (end_date > start_date),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (plan_id)     REFERENCES plan(plan_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Filled automatically by a trigger whenever subscription.status changes
CREATE TABLE subscription_audit (
    audit_id         INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id  INT         NOT NULL,
    old_status       VARCHAR(10) NOT NULL,
    new_status       VARCHAR(10) NOT NULL,
    changed_at       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (subscription_id) REFERENCES subscription(subscription_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE payment_method (
    method_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    INT         NOT NULL,
    method_type    VARCHAR(12) NOT NULL
                   CHECK (method_type IN ('CARD','UPI','NETBANKING','WALLET')),
    provider       VARCHAR(40) NOT NULL,
    masked_detail  VARCHAR(30) NOT NULL,
    is_default     BOOLEAN     NOT NULL DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MODULE 3 : SHOPPING (sellers, catalogue, orders, delivery)
-- ============================================================================
CREATE TABLE seller (
    seller_id    INT AUTO_INCREMENT PRIMARY KEY,
    seller_name  VARCHAR(80) NOT NULL UNIQUE,
    email        VARCHAR(120) NOT NULL UNIQUE,
    city         VARCHAR(60) NOT NULL,
    rating       DECIMAL(2,1) CHECK (rating BETWEEN 0 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Self-referencing (recursive) relationship: sub-categories point to a parent
CREATE TABLE category (
    category_id         INT AUTO_INCREMENT PRIMARY KEY,
    category_name       VARCHAR(60) NOT NULL UNIQUE,
    parent_category_id  INT,
    FOREIGN KEY (parent_category_id) REFERENCES category(category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE product (
    product_id         INT AUTO_INCREMENT PRIMARY KEY,
    seller_id          INT           NOT NULL,
    category_id        INT           NOT NULL,
    product_name       VARCHAR(120)  NOT NULL,
    price              DECIMAL(10,2) NOT NULL CHECK (price > 0),
    stock_qty          INT           NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    is_prime_eligible  BOOLEAN       NOT NULL DEFAULT 1,
    FOREIGN KEY (seller_id)   REFERENCES seller(seller_id),
    FOREIGN KEY (category_id) REFERENCES category(category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- "orders" because ORDER is a reserved word
CREATE TABLE orders (
    order_id     INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT          NOT NULL,
    address_id   INT          NOT NULL,
    order_date   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status       VARCHAR(10)  NOT NULL DEFAULT 'PLACED'
                 CHECK (status IN ('PLACED','SHIPPED','DELIVERED','CANCELLED','RETURNED')),
    delivery_fee DECIMAL(6,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (address_id)  REFERENCES address(address_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Associative entity for the M:N between orders and product.
-- unit_price is the price AT PURCHASE TIME (intentional, not a redundancy).
CREATE TABLE order_item (
    order_id    INT           NOT NULL,
    product_id  INT           NOT NULL,
    quantity    INT           NOT NULL CHECK (quantity > 0),
    unit_price  DECIMAL(10,2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id)   REFERENCES orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1:1 with orders (UNIQUE order_id)
CREATE TABLE shipment (
    shipment_id     INT AUTO_INCREMENT PRIMARY KEY,
    order_id        INT         NOT NULL UNIQUE,
    delivery_type   VARCHAR(15) NOT NULL
                    CHECK (delivery_type IN ('PRIME_ONE_DAY','PRIME_TWO_DAY','STANDARD')),
    carrier         VARCHAR(40) NOT NULL,
    tracking_no     VARCHAR(20) NOT NULL UNIQUE,
    shipped_date    DATE        NOT NULL,
    expected_date   DATE        NOT NULL,
    delivered_date  DATE,
    CHECK (expected_date >= shipped_date),
    CHECK (delivered_date IS NULL OR delivered_date >= shipped_date),
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A payment pays for EXACTLY ONE thing: a subscription OR an order (exclusive arc)
CREATE TABLE payment (
    payment_id       INT AUTO_INCREMENT PRIMARY KEY,
    method_id        INT           NOT NULL,
    subscription_id  INT,
    order_id         INT,
    amount           DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    payment_date     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR(10)   NOT NULL DEFAULT 'SUCCESS'
                     CHECK (status IN ('SUCCESS','FAILED','REFUNDED')),
    CHECK ((subscription_id IS NOT NULL AND order_id IS NULL)
        OR (subscription_id IS NULL AND order_id IS NOT NULL)),
    FOREIGN KEY (method_id)       REFERENCES payment_method(method_id),
    FOREIGN KEY (subscription_id) REFERENCES subscription(subscription_id),
    FOREIGN KEY (order_id)        REFERENCES orders(order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE review (
    review_id    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT      NOT NULL,
    product_id   INT      NOT NULL,
    rating       INT      NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment_text VARCHAR(300),
    review_date  DATE     NOT NULL,
    UNIQUE (customer_id, product_id),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (product_id)  REFERENCES product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MODULE 4 : PRIME VIDEO
-- ============================================================================
CREATE TABLE video_content (
    content_id        INT AUTO_INCREMENT PRIMARY KEY,
    title             VARCHAR(120) NOT NULL,
    content_type      VARCHAR(8)   NOT NULL CHECK (content_type IN ('MOVIE','SERIES')),
    genre             VARCHAR(30)  NOT NULL,
    language          VARCHAR(20)  NOT NULL,
    release_year      INT          NOT NULL CHECK (release_year BETWEEN 1950 AND 2100),
    duration_min      INT,
    maturity_rating   VARCHAR(10)  NOT NULL
                      CHECK (maturity_rating IN ('U','UA 7+','UA 13+','UA 16+','A')),
    rating            DECIMAL(3,1) CHECK (rating BETWEEN 0 AND 10),
    is_prime_original BOOLEAN      NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE episode (
    episode_id    INT AUTO_INCREMENT PRIMARY KEY,
    content_id    INT          NOT NULL,
    season_no     INT          NOT NULL CHECK (season_no > 0),
    episode_no    INT          NOT NULL CHECK (episode_no > 0),
    title         VARCHAR(120) NOT NULL,
    duration_min  INT          NOT NULL CHECK (duration_min > 0),
    UNIQUE (content_id, season_no, episode_no),
    FOREIGN KEY (content_id) REFERENCES video_content(content_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE watch_history (
    watch_id          INT AUTO_INCREMENT PRIMARY KEY,
    profile_id        INT      NOT NULL,
    content_id        INT      NOT NULL,
    episode_id        INT,
    watched_at        DATETIME NOT NULL,
    progress_percent  INT      NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    FOREIGN KEY (profile_id) REFERENCES profile(profile_id)       ON DELETE CASCADE,
    FOREIGN KEY (content_id) REFERENCES video_content(content_id),
    FOREIGN KEY (episode_id) REFERENCES episode(episode_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- M:N between profile and video_content
CREATE TABLE watchlist (
    profile_id  INT      NOT NULL,
    content_id  INT      NOT NULL,
    added_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (profile_id, content_id),
    FOREIGN KEY (profile_id) REFERENCES profile(profile_id)       ON DELETE CASCADE,
    FOREIGN KEY (content_id) REFERENCES video_content(content_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MODULE 5 : PRIME MUSIC
-- ============================================================================
CREATE TABLE music_artist (
    artist_id    INT AUTO_INCREMENT PRIMARY KEY,
    artist_name  VARCHAR(80) NOT NULL UNIQUE,
    genre        VARCHAR(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE music_track (
    track_id      INT AUTO_INCREMENT PRIMARY KEY,
    artist_id     INT          NOT NULL,
    track_title   VARCHAR(120) NOT NULL,
    album_name    VARCHAR(120),
    duration_sec  INT          NOT NULL CHECK (duration_sec > 0),
    release_year  INT,
    FOREIGN KEY (artist_id) REFERENCES music_artist(artist_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE music_play (
    play_id     INT AUTO_INCREMENT PRIMARY KEY,
    profile_id  INT      NOT NULL,
    track_id    INT      NOT NULL,
    played_at   DATETIME NOT NULL,
    FOREIGN KEY (profile_id) REFERENCES profile(profile_id) ON DELETE CASCADE,
    FOREIGN KEY (track_id)   REFERENCES music_track(track_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- INDEXES (foreign keys + columns used in frequent filters / joins)
-- ============================================================================
CREATE INDEX idx_address_customer      ON address(customer_id);
CREATE INDEX idx_subscription_customer ON subscription(customer_id);
CREATE INDEX idx_subscription_status   ON subscription(status, end_date);
CREATE INDEX idx_product_category      ON product(category_id);
CREATE INDEX idx_product_seller        ON product(seller_id);
CREATE INDEX idx_orders_customer       ON orders(customer_id);
CREATE INDEX idx_orders_date           ON orders(order_date);
CREATE INDEX idx_order_item_product    ON order_item(product_id);
CREATE INDEX idx_payment_order         ON payment(order_id);
CREATE INDEX idx_payment_subscription  ON payment(subscription_id);
CREATE INDEX idx_review_product        ON review(product_id);
CREATE INDEX idx_watch_profile         ON watch_history(profile_id);
CREATE INDEX idx_watch_content         ON watch_history(content_id);
CREATE INDEX idx_music_play_track      ON music_play(track_id);
