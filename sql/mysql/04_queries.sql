-- ============================================================================
-- AMAZON PRIME DBMS  |  04_queries.sql  |  Target: MySQL 8.0+
-- 25 queries: joins, GROUP BY/HAVING, subqueries, CTEs, window functions, views
-- Each query starts with a "-- Q<n>:" title line (used by the Python reports).
-- Reference "today" of the sample data set is 2026-10-05.
-- ============================================================================
USE amazon_prime_db;

-- Q1: Active Prime members with their plan and renewal date (JOIN via view)
SELECT full_name, plan_name, start_date, end_date, auto_renew
FROM   v_active_subscribers
ORDER  BY end_date;

-- Q2: Number of subscriptions per plan (GROUP BY)
SELECT p.plan_name, COUNT(*) AS total_subscriptions
FROM   subscription s
JOIN   plan p ON p.plan_id = s.plan_id
GROUP  BY p.plan_name
ORDER  BY total_subscriptions DESC;

-- Q3: Net subscription revenue per plan (refunded payments excluded)
SELECT p.plan_name, SUM(pay.amount) AS net_revenue
FROM   payment pay
JOIN   subscription s ON s.subscription_id = pay.subscription_id
JOIN   plan p         ON p.plan_id = s.plan_id
WHERE  pay.status = 'SUCCESS'
GROUP  BY p.plan_name
ORDER  BY net_revenue DESC;

-- Q4: Customers who have NEVER subscribed to Prime (anti-join with NOT EXISTS)
SELECT c.customer_id, c.full_name, c.email
FROM   customer c
WHERE  NOT EXISTS (SELECT 1 FROM subscription s WHERE s.customer_id = c.customer_id)
ORDER  BY c.customer_id;

-- Q5: Active subscriptions expiring in the next 30 days (renewal campaign list)
SELECT c.full_name, c.phone, p.plan_name, s.end_date, s.auto_renew
FROM   subscription s
JOIN   customer c ON c.customer_id = s.customer_id
JOIN   plan p     ON p.plan_id = s.plan_id
WHERE  s.status = 'ACTIVE'
  AND  s.end_date BETWEEN '2026-10-05' AND '2026-11-04'
ORDER  BY s.end_date;

-- Q6: Top 5 best-selling products by units sold (cancelled/returned excluded)
SELECT pr.product_name, SUM(oi.quantity) AS units_sold
FROM   order_item oi
JOIN   orders  o  ON o.order_id = oi.order_id
JOIN   product pr ON pr.product_id = oi.product_id
WHERE  o.status NOT IN ('CANCELLED','RETURNED')
GROUP  BY pr.product_id, pr.product_name
ORDER  BY units_sold DESC, pr.product_name
LIMIT  5;

-- Q7: Revenue per top-level category (self-join on the category hierarchy)
SELECT COALESCE(par.category_name, cat.category_name) AS top_category,
       SUM(oi.quantity * oi.unit_price)               AS revenue
FROM   order_item oi
JOIN   orders  o   ON o.order_id = oi.order_id
JOIN   product pr  ON pr.product_id = oi.product_id
JOIN   category cat ON cat.category_id = pr.category_id
LEFT JOIN category par ON par.category_id = cat.parent_category_id
WHERE  o.status NOT IN ('CANCELLED','RETURNED')
GROUP  BY COALESCE(par.category_name, cat.category_name)
ORDER  BY revenue DESC;

-- Q8: Products with at least 3 reviews, ranked by average rating (HAVING)
SELECT pr.product_name, COUNT(r.review_id) AS reviews, ROUND(AVG(r.rating), 2) AS avg_rating
FROM   product pr
JOIN   review r ON r.product_id = pr.product_id
GROUP  BY pr.product_id, pr.product_name
HAVING COUNT(r.review_id) >= 3
ORDER  BY avg_rating DESC, reviews DESC;

-- Q9: Average order value - Prime delivery vs standard delivery (CASE + view)
SELECT CASE WHEN sh.delivery_type = 'STANDARD' THEN 'Standard delivery'
            ELSE 'Prime delivery' END           AS delivery_group,
       COUNT(*)                                  AS orders,
       ROUND(AVG(t.grand_total), 2)              AS avg_order_value
FROM   v_order_totals t
JOIN   shipment sh ON sh.order_id = t.order_id
GROUP  BY CASE WHEN sh.delivery_type = 'STANDARD' THEN 'Standard delivery'
               ELSE 'Prime delivery' END;

-- Q10: Late deliveries and how many days late
SELECT o.order_id, c.full_name, sh.delivery_type, sh.expected_date, sh.delivered_date,
       DATEDIFF(sh.delivered_date, sh.expected_date) AS days_late
FROM   shipment sh
JOIN   orders   o ON o.order_id = sh.order_id
JOIN   customer c ON c.customer_id = o.customer_id
WHERE  sh.delivered_date > sh.expected_date
ORDER  BY days_late DESC, o.order_id;

-- Q11: Customers who spent more than the average customer (scalar subquery)
SELECT c.full_name, ROUND(SUM(t.grand_total), 2) AS total_spent
FROM   v_order_totals t
JOIN   customer c ON c.customer_id = t.customer_id
WHERE  t.status NOT IN ('CANCELLED','RETURNED')
GROUP  BY c.customer_id, c.full_name
HAVING SUM(t.grand_total) > (SELECT AVG(x.s) FROM
          (SELECT SUM(grand_total) AS s FROM v_order_totals
            WHERE status NOT IN ('CANCELLED','RETURNED') GROUP BY customer_id) x)
ORDER  BY total_spent DESC;

-- Q12: Ten most-watched titles (distinct profiles that watched them)
SELECT v.title, v.content_type, COUNT(*) AS views, COUNT(DISTINCT w.profile_id) AS unique_viewers
FROM   watch_history w
JOIN   video_content v ON v.content_id = w.content_id
GROUP  BY v.content_id, v.title, v.content_type
ORDER  BY views DESC, v.title
LIMIT  10;

-- Q13: Genre popularity on Prime Video
SELECT v.genre, COUNT(*) AS views, ROUND(AVG(w.progress_percent), 1) AS avg_completion_pct
FROM   watch_history w
JOIN   video_content v ON v.content_id = w.content_id
GROUP  BY v.genre
ORDER  BY views DESC;

-- Q14: Parental-control audit - kids profiles that watched 'A' (adult) content
SELECT c.full_name AS account_holder, pf.profile_name, v.title, v.maturity_rating, w.watched_at
FROM   watch_history w
JOIN   profile pf       ON pf.profile_id = w.profile_id
JOIN   customer c       ON c.customer_id = pf.customer_id
JOIN   video_content v  ON v.content_id  = w.content_id
WHERE  pf.is_kids = 1 AND v.maturity_rating = 'A';

-- Q15: Each profile's most-watched title (window function RANK)
SELECT profile_name, title, views FROM (
    SELECT pf.profile_name, v.title, COUNT(*) AS views,
           RANK() OVER (PARTITION BY pf.profile_id ORDER BY COUNT(*) DESC) AS rnk
    FROM   watch_history w
    JOIN   profile pf      ON pf.profile_id = w.profile_id
    JOIN   video_content v ON v.content_id  = w.content_id
    GROUP  BY pf.profile_id, pf.profile_name, v.content_id, v.title
) ranked
WHERE rnk = 1 AND views >= 3
ORDER BY views DESC, profile_name;

-- Q16: Monthly revenue and running total (CTE + window SUM OVER)
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(grand_total) AS revenue
    FROM   v_order_totals
    WHERE  status NOT IN ('CANCELLED','RETURNED')
    GROUP  BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month, ROUND(revenue, 2) AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS running_total
FROM   monthly
ORDER  BY month;

-- Q17: Rank customers by spend inside each city (PARTITION BY)
SELECT city, full_name, total_spent, city_rank FROM (
    SELECT a.city, c.full_name, ROUND(SUM(t.grand_total), 2) AS total_spent,
           RANK() OVER (PARTITION BY a.city ORDER BY SUM(t.grand_total) DESC) AS city_rank
    FROM   v_order_totals t
    JOIN   orders o   ON o.order_id = t.order_id
    JOIN   address a  ON a.address_id = o.address_id
    JOIN   customer c ON c.customer_id = t.customer_id
    WHERE  t.status NOT IN ('CANCELLED','RETURNED')
    GROUP  BY a.city, c.customer_id, c.full_name
) r
WHERE city_rank <= 2
ORDER BY city, city_rank;

-- Q18: Active Prime members who placed 3 or more orders (CTE + join)
WITH order_counts AS (
    SELECT customer_id, COUNT(*) AS n_orders FROM orders GROUP BY customer_id
)
SELECT v.full_name, v.plan_name, oc.n_orders
FROM   v_active_subscribers v
JOIN   order_counts oc ON oc.customer_id = v.customer_id
WHERE  oc.n_orders >= 3
ORDER  BY oc.n_orders DESC, v.full_name;

-- Q19: Products that were never ordered (LEFT JOIN ... IS NULL)
SELECT pr.product_id, pr.product_name, pr.stock_qty
FROM   product pr
LEFT JOIN order_item oi ON oi.product_id = pr.product_id
WHERE  oi.product_id IS NULL;

-- Q20: Seller scorecard - revenue and average customer rating
SELECT s.seller_name,
       COALESCE(rev.revenue, 0)       AS revenue,
       COALESCE(rat.avg_rating, 0)    AS avg_product_rating
FROM   seller s
LEFT JOIN (SELECT pr.seller_id, SUM(oi.quantity * oi.unit_price) AS revenue
           FROM order_item oi
           JOIN orders o   ON o.order_id = oi.order_id
           JOIN product pr ON pr.product_id = oi.product_id
           WHERE o.status NOT IN ('CANCELLED','RETURNED')
           GROUP BY pr.seller_id) rev ON rev.seller_id = s.seller_id
LEFT JOIN (SELECT pr.seller_id, ROUND(AVG(r.rating), 2) AS avg_rating
           FROM review r JOIN product pr ON pr.product_id = r.product_id
           GROUP BY pr.seller_id) rat ON rat.seller_id = s.seller_id
ORDER  BY revenue DESC;

-- Q21: Most played Prime Music artists
SELECT ar.artist_name, COUNT(*) AS plays
FROM   music_play mp
JOIN   music_track t   ON t.track_id = mp.track_id
JOIN   music_artist ar ON ar.artist_id = t.artist_id
GROUP  BY ar.artist_id, ar.artist_name
ORDER  BY plays DESC, ar.artist_name;

-- Q22: Customers who use more than one type of payment method
SELECT c.full_name, COUNT(DISTINCT pm.method_type) AS method_types,
       GROUP_CONCAT(pm.provider SEPARATOR ', ') AS providers
FROM   customer c
JOIN   payment_method pm ON pm.customer_id = c.customer_id
GROUP  BY c.customer_id, c.full_name
HAVING COUNT(DISTINCT pm.method_type) > 1
ORDER  BY method_types DESC, c.full_name
LIMIT  10;

-- Q23: Subscription churn - share of subscriptions cancelled, per plan
SELECT p.plan_name,
       COUNT(*)                                                  AS subscriptions,
       SUM(CASE WHEN s.status = 'CANCELLED' THEN 1 ELSE 0 END)   AS cancelled,
       ROUND(100.0 * SUM(CASE WHEN s.status = 'CANCELLED' THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_pct
FROM   subscription s
JOIN   plan p ON p.plan_id = s.plan_id
GROUP  BY p.plan_name
ORDER  BY churn_pct DESC, p.plan_name;

-- Q24: Benefits included in each plan (M:N resolved with GROUP_CONCAT)
SELECT p.plan_name, p.price, COUNT(b.benefit_id) AS benefit_count,
       GROUP_CONCAT(b.benefit_name SEPARATOR ', ') AS benefits
FROM   plan p
JOIN   plan_benefit pb ON pb.plan_id = p.plan_id
JOIN   benefit b       ON b.benefit_id = pb.benefit_id
GROUP  BY p.plan_id, p.plan_name, p.price
ORDER  BY p.price DESC;

-- Q25: Engagement score per account = video views + music plays (UNION ALL)
SELECT c.full_name, SUM(a.events) AS engagement_score
FROM (
    SELECT pf.customer_id, COUNT(*) AS events
    FROM watch_history w JOIN profile pf ON pf.profile_id = w.profile_id GROUP BY pf.customer_id
    UNION ALL
    SELECT pf.customer_id, COUNT(*) AS events
    FROM music_play m JOIN profile pf ON pf.profile_id = m.profile_id GROUP BY pf.customer_id
) a
JOIN customer c ON c.customer_id = a.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY engagement_score DESC
LIMIT 10;

-- ============================================================================
-- DML / TRANSACTION EXAMPLES (not auto-run by the report generator)
-- ============================================================================
-- Place an order atomically: all statements succeed or none do.
-- START TRANSACTION;                      -- SQLite: BEGIN;
--   INSERT INTO orders (customer_id, address_id, status, delivery_fee)
--   VALUES (1, 1, 'PLACED', 0);
--   INSERT INTO order_item (order_id, product_id, quantity, unit_price)
--   VALUES ((SELECT MAX(order_id) FROM orders), 5, 2, 1999.00);   -- trigger reduces stock
-- COMMIT;
--
-- Cancel an order (trigger trg_restore_stock puts the stock back):
-- UPDATE orders SET status = 'CANCELLED' WHERE order_id = 91;
--
-- Cancel a membership (trigger trg_subscription_audit logs the change):
-- UPDATE subscription SET status = 'CANCELLED' WHERE subscription_id = 5;
--
-- Mark expired memberships (run daily):
-- UPDATE subscription SET status = 'EXPIRED'
--  WHERE status = 'ACTIVE' AND end_date < CURRENT_DATE;
--
-- Remove a customer's address (safe: orders keep their own address row):
-- DELETE FROM address WHERE address_id = 999 AND is_default = 0;
