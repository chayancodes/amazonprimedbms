# Amazon Prime DBMS - Group Project

A complete relational database project modelled on **Amazon Prime** (membership + shopping + Prime Video + Prime Music):
ER diagrams, 24-table schema, sample data, views, triggers, 25 SQL queries, a Python application, automated tests
and a 29-page Word report.

> All data is **fictional sample data**. This is an academic model, not Amazon's real schema.

## Folder structure
```
amazon_prime_dbms/
├── README.md
├── amazon_prime.db              ready-to-open SQLite database (schema + data + views + triggers)
├── requirements.txt
├── docs/
│   ├── Project_Report.docx      full report (fill in names/roll numbers on the title page)
│   ├── Viva_QnA.md              likely professor questions with answers
│   ├── ER_Diagram_Conceptual.png / .svg / .pdf
│   ├── ER_Diagram_Detailed.png  / .svg / .pdf     (24 tables, PK/FK, crow's foot)
│   └── charts/                  5 analytical charts
├── sql/
│   ├── 02_sample_data.sql       shared INSERTs (~1,700 rows)
│   ├── mysql/    01_schema.sql, 03_views_triggers.sql, 04_queries.sql
│   └── sqlite/   01_schema.sql, 03_views_triggers.sql, 04_queries.sql
├── app/                         Python console application (standard library only)
│   ├── db.py  services.py  prime_cli.py  reports.py
├── tests/test_database.py       21 automated tests
└── scripts/                     generators (data, SQL variants, ER diagrams, report) + templates
```

## Quick start - SQLite (zero setup, tested)
```bash
python app/prime_cli.py --reset     # rebuild amazon_prime.db from the SQL files
python app/prime_cli.py --demo      # scripted walkthrough: triggers, rollback, free Prime delivery...
python app/prime_cli.py             # interactive menu
python -m unittest discover -s tests -v   # 21 tests
python app/reports.py               # regenerate charts (needs matplotlib)
```
Or open `amazon_prime.db` with *DB Browser for SQLite* and paste queries from `sql/sqlite/04_queries.sql`.

## Quick start - MySQL 8.0+
```bash
mysql -u root -p < sql/mysql/01_schema.sql          # creates database amazon_prime_db + 24 tables
mysql -u root -p < sql/02_sample_data.sql
mysql -u root -p < sql/mysql/03_views_triggers.sql  # uses DELIMITER, run via the mysql client / Workbench
mysql -u root -p < sql/mysql/04_queries.sql
```
In MySQL Workbench: *File > Open SQL Script*, run the four files in that order.
**Note:** the SQLite scripts and the Python app were run and tested end to end. The MySQL scripts are generated from the
same template with MySQL-specific syntax (AUTO_INCREMENT, DATE_FORMAT, DATEDIFF, SIGNAL triggers) but were not executed
against a live MySQL server while this package was built - run them once before the viva and fix any version-specific
detail (CHECK constraints need MySQL >= 8.0.16).

## What the project demonstrates
| Topic | Where |
|---|---|
| ER modelling (1:1, 1:N, M:N, recursive, exclusive arc) | docs/ER_Diagram_*.png |
| Normalization to 3NF/BCNF | report section 9 |
| DDL with PK/FK/UNIQUE/CHECK/DEFAULT, indexes | sql/*/01_schema.sql |
| DML, bulk load | sql/02_sample_data.sql |
| Views | sql/*/03_views_triggers.sql |
| Triggers (stock, business rule, audit) | sql/*/03_views_triggers.sql |
| Joins, GROUP BY/HAVING, subqueries, CTE, window functions | sql/*/04_queries.sql |
| Transactions / ACID / rollback | app/services.py, demo steps 2-8 |
| Testing | tests/test_database.py |

## Before you submit
1. Fill in team names, roll numbers, professor and college on the report title page and the last page.
2. Run the demo and the tests once so you have seen them work.
3. Read `docs/Viva_QnA.md` - everyone in the group should be able to explain the ER diagram, normalization and one trigger.

## Regenerating everything
```bash
python scripts/generate_data.py   # sample data (fixed seed)
python scripts/build_sql.py       # MySQL + SQLite scripts from templates
python scripts/build_er_diagram.py
python scripts/build_report.py
```
