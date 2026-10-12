"""Database connection helpers."""
import os
import psycopg2
import psycopg2.extras


def get_connection():
    return psycopg2.connect(
        os.environ["DATABASE_URL"],
        cursor_factory=psycopg2.extras.RealDictCursor
    )
