"""
services.py - business logic of the Amazon Prime database application.

Every function that changes data runs inside ONE transaction (`with con:`),
so a failure rolls back everything (ACID: atomicity + consistency).
Integrity is enforced twice: by the schema (constraints/triggers) and here
(friendly error messages).
"""
import hashlib
import os
import sqlite3
from calendar import monthrange
from datetime import date, datetime


class ServiceError(Exception):
    """A business rule was violated (shown to the user as a friendly message)."""


def _add_months(d: date, months: int) -> date:
    m = d.month - 1 + months
    y, m = d.year + m // 12, m % 12 + 1
    return date(y, m, min(d.day, monthrange(y, m)[1]))


def _now(today):
    today = today or date.today()
    return today, datetime.combine(today, datetime.now().time()).strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------ customers
def hash_password(password: str) -> str:
    salt = os.urandom(8).hex()
    return "sha256$" + salt + "$" + hashlib.sha256((salt + password).encode()).hexdigest()


def register_customer(con, full_name, email, phone, password,
                      line1, city, state, pincode) -> int:
    """Create customer + default address + default profile in one transaction."""
    if "@" not in email:
        raise ServiceError("Invalid e-mail address.")
    try:
        with con:
            cur = con.execute(
                "INSERT INTO customer (full_name, email, phone, password_hash) VALUES (?,?,?,?)",
                (full_name, email, phone, hash_password(password)))
            cid = cur.lastrowid
            con.execute("INSERT INTO address (customer_id, label, line1, city, state, pincode, is_default)"
                        " VALUES (?, 'Home', ?, ?, ?, ?, 1)", (cid, line1, city, state, pincode))
            con.execute("INSERT INTO profile (customer_id, profile_name) VALUES (?, ?)",
                        (cid, full_name.split()[0]))
        return cid
    except sqlite3.IntegrityError as e:
        raise ServiceError(f"Could not register: {e}")


def add_payment_method(con, customer_id, method_type, provider, masked_detail) -> int:
    try:
        with con:
            first = con.execute("SELECT COUNT(*) FROM payment_method WHERE customer_id=?",
                                (customer_id,)).fetchone()[0] == 0
            cur = con.execute(
                "INSERT INTO payment_method (customer_id, method_type, provider, masked_detail, is_default)"
                " VALUES (?,?,?,?,?)", (customer_id, method_type, provider, masked_detail, first))
        return cur.lastrowid
    except sqlite3.IntegrityError as e:
        raise ServiceError(f"Invalid payment method: {e}")


# --------------------------------------------------------- subscriptions
def list_plans(con):
    return con.execute("""
        SELECT p.plan_id, p.plan_name, p.price, p.duration_months, p.max_profiles,
               CASE WHEN p.has_ads THEN 'Yes' ELSE 'No' END AS has_ads,
               COUNT(pb.benefit_id) AS benefits
        FROM plan p LEFT JOIN plan_benefit pb ON pb.plan_id = p.plan_id
        GROUP BY p.plan_id ORDER BY p.price""").fetchall()


def get_active_subscription(con, customer_id):
    return con.execute(
        "SELECT * FROM v_active_subscribers WHERE customer_id = ?", (customer_id,)).fetchone()


def is_prime_member(con, customer_id, on_date: date) -> bool:
    """True if the customer held any membership covering `on_date`."""
    d = on_date.isoformat()
    return con.execute(
        "SELECT 1 FROM subscription WHERE customer_id=? AND start_date<=? AND end_date>?",
        (customer_id, d, d)).fetchone() is not None


def subscribe(con, customer_id, plan_id, method_id, today=None, auto_renew=True) -> int:
    """Buy a Prime plan: inserts subscription + successful payment atomically."""
    today, ts = _now(today)
    plan = con.execute("SELECT * FROM plan WHERE plan_id=?", (plan_id,)).fetchone()
    if plan is None:
        raise ServiceError("Unknown plan.")
    owner = con.execute("SELECT customer_id FROM payment_method WHERE method_id=?",
                        (method_id,)).fetchone()
    if owner is None or owner["customer_id"] != customer_id:
        raise ServiceError("That payment method does not belong to this customer.")
    try:
        with con:       # the trigger trg_one_active_sub rejects a 2nd ACTIVE plan
            cur = con.execute(
                "INSERT INTO subscription (customer_id, plan_id, start_date, end_date, status, auto_renew)"
                " VALUES (?,?,?,?, 'ACTIVE', ?)",
                (customer_id, plan_id, today.isoformat(),
                 _add_months(today, plan["duration_months"]).isoformat(), int(auto_renew)))
            sid = cur.lastrowid
            con.execute("INSERT INTO payment (method_id, subscription_id, amount, payment_date, status)"
                        " VALUES (?,?,?,?, 'SUCCESS')", (method_id, sid, plan["price"], ts))
        return sid
    except sqlite3.IntegrityError as e:
        raise ServiceError(str(e).replace("ABORT: ", ""))


def cancel_subscription(con, customer_id) -> int:
    """Cancel the ACTIVE membership and mark its payment REFUNDED."""
    sub = con.execute("SELECT subscription_id FROM subscription"
                      " WHERE customer_id=? AND status='ACTIVE'", (customer_id,)).fetchone()
    if sub is None:
        raise ServiceError("No active subscription to cancel.")
    with con:
        con.execute("UPDATE subscription SET status='CANCELLED', auto_renew=0 WHERE subscription_id=?",
                    (sub["subscription_id"],))   # audit row written by trigger
        con.execute("UPDATE payment SET status='REFUNDED' WHERE subscription_id=? AND status='SUCCESS'",
                    (sub["subscription_id"],))
    return sub["subscription_id"]


# --------------------------------------------------------------- shopping
def search_products(con, keyword):
    like = f"%{keyword}%"
    return con.execute("""
        SELECT p.product_id, p.product_name, p.price, p.stock_qty,
               CASE WHEN p.is_prime_eligible THEN 'Prime' ELSE '-' END AS prime,
               c.category_name, s.seller_name
        FROM product p
        JOIN category c ON c.category_id = p.category_id
        JOIN seller   s ON s.seller_id   = p.seller_id
        WHERE p.product_name LIKE ? OR c.category_name LIKE ?
        ORDER BY p.product_name""", (like, like)).fetchall()


def place_order(con, customer_id, address_id, method_id, cart, today=None) -> dict:
    """
    cart = [(product_id, quantity), ...]
    Prime members get free delivery; others pay Rs 40 below Rs 499.
    Stock is reduced by trigger trg_reduce_stock; the CHECK(stock_qty >= 0)
    constraint aborts (and rolls back) the whole order if stock is insufficient.
    """
    if not cart:
        raise ServiceError("Cart is empty.")
    today, ts = _now(today)
    addr = con.execute("SELECT customer_id FROM address WHERE address_id=?", (address_id,)).fetchone()
    if addr is None or addr["customer_id"] != customer_id:
        raise ServiceError("Address does not belong to this customer.")
    pm = con.execute("SELECT customer_id FROM payment_method WHERE method_id=?", (method_id,)).fetchone()
    if pm is None or pm["customer_id"] != customer_id:
        raise ServiceError("Payment method does not belong to this customer.")

    lines, subtotal = [], 0.0
    for pid, qty in cart:
        p = con.execute("SELECT product_id, product_name, price, stock_qty FROM product WHERE product_id=?",
                        (pid,)).fetchone()
        if p is None:
            raise ServiceError(f"Product {pid} not found.")
        if qty <= 0:
            raise ServiceError("Quantity must be positive.")
        if p["stock_qty"] < qty:
            raise ServiceError(f"Only {p['stock_qty']} unit(s) of '{p['product_name']}' in stock.")
        lines.append((pid, qty, p["price"]))
        subtotal += qty * p["price"]

    prime = is_prime_member(con, customer_id, today)
    fee = 0.0 if (prime or subtotal >= 499) else 40.0
    try:
        with con:
            oid = con.execute(
                "INSERT INTO orders (customer_id, address_id, order_date, status, delivery_fee)"
                " VALUES (?,?,?, 'PLACED', ?)", (customer_id, address_id, ts, fee)).lastrowid
            for pid, qty, price in lines:
                con.execute("INSERT INTO order_item (order_id, product_id, quantity, unit_price)"
                            " VALUES (?,?,?,?)", (oid, pid, qty, price))
            con.execute("INSERT INTO payment (method_id, order_id, amount, payment_date, status)"
                        " VALUES (?,?,?,?, 'SUCCESS')", (method_id, oid, round(subtotal + fee, 2), ts))
    except sqlite3.IntegrityError as e:
        raise ServiceError(f"Order rejected, nothing was saved: {e}")
    return {"order_id": oid, "items_total": subtotal, "delivery_fee": fee,
            "grand_total": round(subtotal + fee, 2), "prime_member": prime}


def ship_order(con, order_id, today=None) -> str:
    """Create the shipment row and move the order to SHIPPED."""
    today, _ = _now(today)
    o = con.execute("SELECT * FROM orders WHERE order_id=?", (order_id,)).fetchone()
    if o is None or o["status"] != "PLACED":
        raise ServiceError("Only orders in PLACED status can be shipped.")
    all_prime = con.execute(
        "SELECT MIN(p.is_prime_eligible) FROM order_item oi JOIN product p ON p.product_id=oi.product_id"
        " WHERE oi.order_id=?", (order_id,)).fetchone()[0]
    prime = is_prime_member(con, o["customer_id"], date.fromisoformat(o["order_date"][:10]))
    if prime and all_prime:
        dtype, days = "PRIME_ONE_DAY", 1
    elif prime:
        dtype, days = "PRIME_TWO_DAY", 2
    else:
        dtype, days = "STANDARD", 4
    from datetime import timedelta
    tracking = "AMZ" + str(abs(hash((order_id, today.isoformat()))) % 10**10).zfill(10)
    with con:
        con.execute("INSERT INTO shipment (order_id, delivery_type, carrier, tracking_no, shipped_date, expected_date)"
                    " VALUES (?,?,?,?,?,?)",
                    (order_id, dtype, "Amazon Transport", tracking, today.isoformat(),
                     (today + timedelta(days=days)).isoformat()))
        con.execute("UPDATE orders SET status='SHIPPED' WHERE order_id=?", (order_id,))
    return dtype


def cancel_order(con, order_id) -> None:
    """Cancel a PLACED order; trigger restores stock; payment is refunded."""
    o = con.execute("SELECT status FROM orders WHERE order_id=?", (order_id,)).fetchone()
    if o is None:
        raise ServiceError("Order not found.")
    if o["status"] != "PLACED":
        raise ServiceError(f"Cannot cancel an order that is {o['status']}.")
    with con:
        con.execute("UPDATE orders SET status='CANCELLED' WHERE order_id=?", (order_id,))
        con.execute("UPDATE payment SET status='REFUNDED' WHERE order_id=? AND status='SUCCESS'", (order_id,))


def add_review(con, customer_id, product_id, rating, comment) -> int:
    """Only customers who received the product may review it (one review each)."""
    bought = con.execute("""
        SELECT 1 FROM orders o JOIN order_item oi ON oi.order_id=o.order_id
        WHERE o.customer_id=? AND oi.product_id=? AND o.status='DELIVERED'""",
        (customer_id, product_id)).fetchone()
    if not bought:
        raise ServiceError("You can only review products from delivered orders.")
    try:
        with con:
            return con.execute(
                "INSERT INTO review (customer_id, product_id, rating, comment_text, review_date)"
                " VALUES (?,?,?,?,?)",
                (customer_id, product_id, rating, comment, date.today().isoformat())).lastrowid
    except sqlite3.IntegrityError as e:
        raise ServiceError(f"Review rejected: {e}")


# ------------------------------------------------------------ video/music
def record_watch(con, profile_id, content_id, episode_id=None, progress=100, when=None) -> int:
    """Log viewing; kids profiles are blocked from 'A' (adult) titles."""
    prof = con.execute("SELECT is_kids FROM profile WHERE profile_id=?", (profile_id,)).fetchone()
    vid = con.execute("SELECT title, maturity_rating FROM video_content WHERE content_id=?",
                      (content_id,)).fetchone()
    if prof is None or vid is None:
        raise ServiceError("Unknown profile or title.")
    if prof["is_kids"] and vid["maturity_rating"] in ("A", "UA 16+"):
        raise ServiceError(f"'{vid['title']}' is rated {vid['maturity_rating']} - blocked on a Kids profile.")
    when = when or datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with con:
            return con.execute(
                "INSERT INTO watch_history (profile_id, content_id, episode_id, watched_at, progress_percent)"
                " VALUES (?,?,?,?,?)", (profile_id, content_id, episode_id, when, progress)).lastrowid
    except sqlite3.IntegrityError as e:
        raise ServiceError(f"Could not record viewing: {e}")


def recommend_titles(con, profile_id, limit=5):
    """Top-rated titles in the profile's favourite genre that it has not watched yet."""
    prof = con.execute("SELECT is_kids FROM profile WHERE profile_id=?", (profile_id,)).fetchone()
    blocked = "('A','UA 16+')" if prof and prof["is_kids"] else "('')"
    return con.execute(f"""
        WITH fav AS (
            SELECT v.genre FROM watch_history w JOIN video_content v ON v.content_id=w.content_id
            WHERE w.profile_id = ? GROUP BY v.genre ORDER BY COUNT(*) DESC LIMIT 1)
        SELECT v.title, v.genre, v.language, v.rating
        FROM video_content v
        WHERE v.genre = (SELECT genre FROM fav)
          AND v.maturity_rating NOT IN {blocked}
          AND v.content_id NOT IN (SELECT content_id FROM watch_history WHERE profile_id = ?)
        ORDER BY v.rating DESC LIMIT ?""", (profile_id, profile_id, limit)).fetchall()
