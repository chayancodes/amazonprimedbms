# Viva preparation - Amazon Prime DBMS

**Q1. Why did you choose this topic?** It combines several real data domains (membership, e-commerce, streaming) so it needs every DBMS concept: many relationship types, constraints, triggers and analytical queries.

**Q2. How many tables, and what are the main ones?** 24 tables in 5 modules: Customer & Account, Prime Membership, Shopping, Prime Video, Prime Music. Core ones: customer, plan, subscription, product, orders, order_item, payment, video_content.

**Q3. Which relationship types did you use?** 1:N (customer-address), M:N (orders-product via order_item, plan-benefit, profile-video), 1:1 (orders-shipment, UNIQUE FK), recursive (category-parent), exclusive arc (payment pays a subscription OR an order).

**Q4. How is an M:N relationship converted to tables?** Into an associative table whose primary key is the combination of the two foreign keys, e.g. order_item(order_id, product_id, quantity, unit_price).

**Q5. Why is the table called `orders` and not `order`?** ORDER is a reserved SQL keyword.

**Q6. What is the exclusive arc in `payment`?** Two nullable FKs (subscription_id, order_id) plus a CHECK that exactly one is NOT NULL, so a payment is for one thing only.

**Q7. Why does order_item store unit_price when product has price?** Product prices change; unit_price is the price at purchase time, so past orders stay correct. It is history, not redundancy.

**Q8. Why is there no `total_amount` column in orders?** It is derived data. Storing it risks inconsistency, so it is computed in the view v_order_totals.

**Q9. Which normal form are your tables in and why?** At least 3NF (mostly BCNF): atomic columns (1NF), no partial dependencies on composite keys (2NF), no transitive dependencies such as product -> seller -> city (3NF). See report section 9.

**Q10. Give a functional dependency.** plan_id -> plan_name, price, duration_months; (order_id, product_id) -> quantity, unit_price.

**Q11. Primary key vs candidate key vs foreign key?** PK uniquely identifies a row (customer_id); a candidate key is any minimal unique column set (email is also one); FK references the PK of another table (address.customer_id).

**Q12. What constraints did you use?** PRIMARY KEY, FOREIGN KEY (with ON DELETE CASCADE where logical), UNIQUE, NOT NULL, CHECK (price > 0, rating 1-5, end_date > start_date, status lists), DEFAULT.

**Q13. Explain one trigger.** `trg_one_active_sub` fires BEFORE INSERT on subscription and aborts if the customer already has an ACTIVE one - a business rule that no application bug can bypass.

**Q14. How do you stop overselling?** CHECK (stock_qty >= 0) plus trigger trg_reduce_stock. If stock would go negative the INSERT fails and the whole order transaction rolls back.

**Q15. What is a view and which did you create?** A stored query that behaves like a table: v_order_totals, v_active_subscribers, v_product_ratings. They hide joins and avoid storing derived data.

**Q16. Why indexes? Which ones?** Faster joins/filters. On all frequently joined foreign keys plus subscription(status, end_date) and orders(order_date). Trade-off: slower writes, more storage.

**Q17. What are ACID properties and where do you show them?** Atomicity, Consistency, Isolation, Durability. `place_order` inserts orders, order_item and payment in one transaction; demo step 7 shows a failed order leaving no partial rows.

**Q18. INNER vs LEFT JOIN - example?** Q19 uses LEFT JOIN ... IS NULL to find products never ordered; Q1-Q3 use INNER JOIN.

**Q19. WHERE vs HAVING?** WHERE filters rows before grouping; HAVING filters groups after aggregation (Q8: products with >= 3 reviews).

**Q20. What is a window function? Example?** A calculation across related rows without collapsing them: Q16 running total with SUM() OVER (ORDER BY month); Q15/Q17 RANK() OVER (PARTITION BY ...).

**Q21. CTE vs subquery?** A CTE (WITH ...) names an intermediate result for readability and reuse (Q16, Q18); a subquery is inline (Q11).

**Q22. How is security handled?** Passwords stored as salted hashes, card/UPI details stored masked, parameterised queries (`?`) prevent SQL injection. Production would add GRANT/REVOKE roles and bcrypt/argon2.

**Q23. Why two SQL dialects?** SQLite lets anyone run the project with zero setup (and the Python app uses it); MySQL scripts are given because MySQL is the common classroom DBMS. Both come from one template so the design is identical.

**Q24. Limitations / future work?** Fictional data, no payment gateway, no web UI, no concurrency stress test. Future: Flask/Django front-end, returns & coupons, recommendation engine, star-schema warehouse.

**Q25. What would you change to scale to millions of users?** Partition large tables (orders, watch_history) by date, add read replicas, cache hot data, move analytics to a warehouse, use SELECT ... FOR UPDATE for stock.
