"""Idempotent schema-only migration; no demo users or balances."""
import os
from pathlib import Path
from psycopg2 import sql
from app.db import get_connection


def main():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(7142026)")
            cursor.execute(Path(__file__).with_name("schema.sql").read_text())
            cursor.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", ("sentinelpay_app",))
            if cursor.fetchone() is None:
                cursor.execute("CREATE ROLE sentinelpay_app LOGIN")
            cursor.execute(sql.SQL("ALTER ROLE sentinelpay_app PASSWORD {}").format(sql.Literal(os.environ["APP_DB_PASSWORD"])))
            cursor.execute("GRANT CONNECT ON DATABASE sentinelpay TO sentinelpay_app")
            cursor.execute("GRANT USAGE ON SCHEMA public TO sentinelpay_app")
            cursor.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO sentinelpay_app")
            cursor.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO sentinelpay_app")
    print("Schema migration completed; no demo accounts were seeded.")


if __name__ == "__main__":
    main()
