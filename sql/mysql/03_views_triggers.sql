-- ============================================================================
-- AMAZON PRIME DBMS  |  03_views_triggers.sql  |  Target: MySQL 8.0+
-- Run AFTER 01_schema.sql and 02_sample_data.sql
-- ============================================================================
USE amazon_prime_db;

-- ---------------------------------------------------------------------------
-- VIEWS
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_totals;
CREATE VIEW v_order_totals AS
SELECT  o.order_id,
        o.customer_id,
        o.order_date,
        o.status,
        SUM(oi.quantity * oi.unit_price)                    AS items_total,
        o.delivery_fee,
        SUM(oi.quantity * oi.unit_price) + o.delivery_fee   AS grand_total
FROM    orders o
JOIN    order_item oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_date, o.status, o.delivery_fee;

DROP VIEW IF EXISTS v_active_subscribers;
CREATE VIEW v_active_subscribers AS
SELECT  c.customer_id, c.full_name, c.email,
        p.plan_name, s.start_date, s.end_date, s.auto_renew
FROM    subscription s
JOIN    customer c ON c.customer_id = s.customer_id
JOIN    plan     p ON p.plan_id     = s.plan_id
WHERE   s.status = 'ACTIVE';

DROP VIEW IF EXISTS v_product_ratings;
CREATE VIEW v_product_ratings AS
SELECT  p.product_id, p.product_name,
        COUNT(r.review_id)         AS review_count,
        ROUND(AVG(r.rating), 2)    AS avg_rating
FROM    product p
LEFT JOIN review r ON r.product_id = p.product_id
GROUP BY p.product_id, p.product_name;

-- ---------------------------------------------------------------------------
-- TRIGGERS
--  1. trg_reduce_stock       : stock decreases when an order line is inserted
--                              (CHECK stock_qty >= 0 aborts overselling)
--  2. trg_restore_stock      : stock returns when an order is cancelled
--  3. trg_one_active_sub     : business rule - one ACTIVE subscription / customer
--  4. trg_subscription_audit : logs every subscription status change
-- ---------------------------------------------------------------------------
DELIMITER $$

DROP TRIGGER IF EXISTS trg_reduce_stock$$
CREATE TRIGGER trg_reduce_stock
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
    UPDATE product
       SET stock_qty = stock_qty - NEW.quantity
     WHERE product_id = NEW.product_id;
END$$

DROP TRIGGER IF EXISTS trg_restore_stock$$
CREATE TRIGGER trg_restore_stock
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NEW.status = 'CANCELLED' AND OLD.status <> 'CANCELLED' THEN
        UPDATE product p
          JOIN order_item oi ON oi.product_id = p.product_id
           SET p.stock_qty = p.stock_qty + oi.quantity
         WHERE oi.order_id = NEW.order_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_one_active_sub$$
CREATE TRIGGER trg_one_active_sub
BEFORE INSERT ON subscription
FOR EACH ROW
BEGIN
    IF NEW.status = 'ACTIVE' AND EXISTS (SELECT 1 FROM subscription
                                          WHERE customer_id = NEW.customer_id
                                            AND status = 'ACTIVE') THEN
        SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'Customer already has an ACTIVE subscription';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_subscription_audit$$
CREATE TRIGGER trg_subscription_audit
AFTER UPDATE ON subscription
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        INSERT INTO subscription_audit (subscription_id, old_status, new_status)
        VALUES (NEW.subscription_id, OLD.status, NEW.status);
    END IF;
END$$

DELIMITER ;

