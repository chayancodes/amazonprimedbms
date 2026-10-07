"""
db.py - connection + initialisation helpers (Python standard library only).

The app uses SQLite so it runs anywhere with zero setup. The same SQL files for
MySQL are in sql/mysql/ - to use MySQL instead, replace connect() with a
mysql-connector-python connection (the services layer only uses standard SQL
with '?' placeholders -> change them to '%s' for MySQL).
"""
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "amazon_prime.db"

SCHEMA = SQL_DIR / "sqlite" / "01_schema.sql"
DATA = SQL_DIR / "02_sample_data.sql"
VIEWS = SQL_DIR / "sqlite" / "03_views_triggers.sql"


def connect(path=None) -> sqlite3.Connection:
    """Open a connection with foreign-key enforcement and dict-like rows."""
    con = sqlite3.connect(str(path or DB_PATH))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def init_db(path=None, with_sample_data=True) -> sqlite3.Connection:
    """(Re)create the database: schema -> sample data -> views & triggers."""
    target = Path(path) if path and path != ":memory:" else None
    if target and target.exists():
        target.unlink()
    con = connect(path)
    con.executescript(SCHEMA.read_text())
    if with_sample_data:
        con.executescript(DATA.read_text())      # load BEFORE triggers exist
    con.executescript(VIEWS.read_text())
    con.commit()
    return con


def query(con, sql, params=()):
    """Run a SELECT and return a list of sqlite3.Row."""
    return con.execute(sql, params).fetchall()


def print_table(rows, headers=None, max_width=34):
    """Tiny pretty-printer so the CLI needs no third-party packages."""
    if not rows:
        print("  (no rows)")
        return
    headers = headers or list(rows[0].keys())
    data = [[("" if v is None else str(v)) for v in tuple(r)] for r in rows]
    data = [[c if len(c) <= max_width else c[:max_width - 1] + "…" for c in r] for r in data]
    widths = [max(len(h), *(len(r[i]) for r in data)) for i, h in enumerate(headers)]
    line = "+-" + "-+-".join("-" * w for w in widths) + "-+"
    print(line)
    print("| " + " | ".join(h.ljust(w) for h, w in zip(headers, widths)) + " |")
    print(line)
    for r in data:
        print("| " + " | ".join(c.ljust(w) for c, w in zip(r, widths)) + " |")
    print(line)
    print(f"  {len(data)} row(s)")
