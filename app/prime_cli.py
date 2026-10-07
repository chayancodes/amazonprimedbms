"""
prime_cli.py - console application for the Amazon Prime database.

    python app/prime_cli.py            # interactive menu
    python app/prime_cli.py --demo     # scripted walkthrough (good for the viva)
    python app/prime_cli.py --reset    # rebuild amazon_prime.db from the SQL files

Standard library only.
"""
import argparse
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import db                                     # noqa: E402
import services as svc                        # noqa: E402
from services import ServiceError             # noqa: E402

TODAY = date(2026, 10, 5)                     # sample-data "today" (use date.today() in production)


def banner(text):
    print("\n" + "=" * 70 + f"\n  {text}\n" + "=" * 70)


# ------------------------------------------------------------------ demo
def run_demo(con):
    banner("1. Prime plans (JOIN + GROUP BY)")
    db.print_table(svc.list_plans(con))

    banner("2. Register a new customer (customer + address + profile in ONE transaction)")
    cid = svc.register_customer(con, "Demo Student", "demo.student@example.com", "9000000000",
                                "secret123", "12, College Street", "Kolkata", "West Bengal", "700073")
    print(f"  Created customer_id = {cid}")
    mid = svc.add_payment_method(con, cid, "UPI", "Google Pay", "de***@okaxis")
    print(f"  Added payment method_id = {mid}")

    banner("3. Order BEFORE Prime: delivery fee applies below Rs 499")
    addr = db.query(con, "SELECT address_id FROM address WHERE customer_id=?", (cid,))[0][0]
    r = svc.place_order(con, cid, addr, mid, [(17, 1)], today=TODAY)     # The Alchemist, Rs 249
    print(f"  {r}")

    banner("4. Subscribe to Prime Annual")
    sid = svc.subscribe(con, cid, 3, mid, today=TODAY)
    print(f"  subscription_id = {sid}")
    db.print_table(db.query(con, "SELECT * FROM v_active_subscribers WHERE customer_id=?", (cid,)))

    banner("5. Business rule: a second ACTIVE plan is rejected by a TRIGGER")
    try:
        svc.subscribe(con, cid, 1, mid, today=TODAY)
    except ServiceError as e:
        print(f"  Rejected -> {e}")

    banner("6. Order AFTER Prime: free delivery")
    r = svc.place_order(con, cid, addr, mid, [(17, 1), (5, 1)], today=TODAY)
    print(f"  {r}")
    db.print_table(db.query(con, "SELECT product_id, product_name, stock_qty FROM product "
                                 "WHERE product_id IN (5, 17)"))
    print("  ^ stock was reduced automatically by trigger trg_reduce_stock")

    banner("7. Overselling is blocked and the whole order is rolled back")
    try:
        svc.place_order(con, cid, addr, mid, [(34, 1000)], today=TODAY)
    except ServiceError as e:
        print(f"  Rejected -> {e}")

    banner("8. Cancel the order -> trigger restores stock, payment refunded")
    svc.cancel_order(con, r["order_id"])
    db.print_table(db.query(con, "SELECT product_id, product_name, stock_qty FROM product "
                                 "WHERE product_id IN (5, 17)"))

    banner("9. Kids profile cannot watch adult content")
    pid_kids = con.execute("SELECT profile_id FROM profile WHERE is_kids=1 LIMIT 1").fetchone()[0]
    try:
        svc.record_watch(con, pid_kids, 1)    # The Boys (A)
    except ServiceError as e:
        print(f"  Rejected -> {e}")

    banner("10. Cancel membership -> audit trail written by trigger")
    svc.cancel_subscription(con, cid)
    db.print_table(db.query(con, "SELECT * FROM subscription_audit WHERE subscription_id=?", (sid,)))

    banner("11. Recommendations for the first profile of customer 1")
    pid1 = con.execute("SELECT profile_id FROM profile WHERE customer_id=1 LIMIT 1").fetchone()[0]
    db.print_table(svc.recommend_titles(con, pid1))
    print("\nDemo finished. (Run with --reset to restore the original sample data.)")


# ------------------------------------------------------------ interactive
def ask_int(prompt):
    try:
        return int(input(prompt).strip())
    except ValueError:
        raise ServiceError("Please enter a number.")


def menu(con):
    options = {
        "1": "List Prime plans", "2": "Register new customer", "3": "Subscribe to Prime",
        "4": "Cancel my Prime membership", "5": "Search products", "6": "Place an order",
        "7": "Cancel an order", "8": "Top 10 most-watched titles", "9": "Revenue report by plan",
        "10": "Show a customer's active membership", "0": "Exit"}
    while True:
        banner("AMAZON PRIME DBMS - MAIN MENU")
        for k, v in options.items():
            print(f"  {k:>2}. {v}")
        choice = input("\nChoose: ").strip()
        try:
            if choice == "0":
                print("Bye!")
                return
            elif choice == "1":
                db.print_table(svc.list_plans(con))
            elif choice == "2":
                cid = svc.register_customer(
                    con, input("Full name: "), input("E-mail: "), input("Phone: "), input("Password: "),
                    input("Address line: "), input("City: "), input("State: "), input("Pincode: "))
                print(f"Registered! Your customer id is {cid}.")
            elif choice == "3":
                cid, pid, mid = ask_int("Customer id: "), ask_int("Plan id: "), ask_int("Payment method id: ")
                print(f"Subscribed. subscription_id = {svc.subscribe(con, cid, pid, mid, today=TODAY)}")
            elif choice == "4":
                print(f"Cancelled subscription {svc.cancel_subscription(con, ask_int('Customer id: '))}.")
            elif choice == "5":
                db.print_table(svc.search_products(con, input("Search text: ")))
            elif choice == "6":
                cid, aid, mid = ask_int("Customer id: "), ask_int("Address id: "), ask_int("Payment method id: ")
                cart = []
                while True:
                    raw = input("Add item as 'product_id qty' (blank to finish): ").strip()
                    if not raw:
                        break
                    p, q = raw.split()
                    cart.append((int(p), int(q)))
                print(svc.place_order(con, cid, aid, mid, cart, today=TODAY))
            elif choice == "7":
                svc.cancel_order(con, ask_int("Order id: "))
                print("Order cancelled and stock restored.")
            elif choice == "8":
                db.print_table(db.query(con, """
                    SELECT v.title, COUNT(*) AS views FROM watch_history w
                    JOIN video_content v ON v.content_id = w.content_id
                    GROUP BY v.content_id, v.title ORDER BY views DESC LIMIT 10"""))
            elif choice == "9":
                db.print_table(db.query(con, """
                    SELECT p.plan_name, SUM(pay.amount) AS net_revenue
                    FROM payment pay JOIN subscription s ON s.subscription_id = pay.subscription_id
                    JOIN plan p ON p.plan_id = s.plan_id WHERE pay.status = 'SUCCESS'
                    GROUP BY p.plan_name ORDER BY net_revenue DESC"""))
            elif choice == "10":
                row = svc.get_active_subscription(con, ask_int("Customer id: "))
                db.print_table([row] if row else [])
            else:
                print("Invalid choice.")
        except ServiceError as e:
            print(f"  ! {e}")
        except (ValueError, EOFError):
            print("  ! Invalid input.")


def main():
    ap = argparse.ArgumentParser(description="Amazon Prime DBMS console app")
    ap.add_argument("--demo", action="store_true", help="run the scripted walkthrough")
    ap.add_argument("--reset", action="store_true", help="rebuild the database and exit")
    args = ap.parse_args()
    if args.reset or not db.DB_PATH.exists():
        db.init_db().close()
        print(f"Database created at {db.DB_PATH}")
        if args.reset:
            return
    con = db.connect()
    run_demo(con) if args.demo else menu(con)
    con.close()


if __name__ == "__main__":
    main()
