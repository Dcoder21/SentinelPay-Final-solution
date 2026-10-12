"""Database connections for local development and TLS-protected RDS."""
import os
import psycopg2
import psycopg2.extras


def get_connection():
    if os.environ.get("DATABASE_URL"):
        return psycopg2.connect(os.environ["DATABASE_URL"], cursor_factory=psycopg2.extras.RealDictCursor)
    return psycopg2.connect(
        host=os.environ["DB_HOST"], port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"], user=os.environ["DB_USERNAME"],
        password=os.environ["DB_PASSWORD"], sslmode="verify-full",
        sslrootcert=os.environ["DB_SSLROOTCERT"], connect_timeout=10,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
