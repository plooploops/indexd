import os
import psycopg2


def main():
    # TODO: can this come from kv?
    DB_CONNECTION_STRING = os.environ.get("DB_CONNECTION_STRING")

    try:
        db = psycopg2.connect(DB_CONNECTION_STRING)  # noqa: F841
    except:  # noqa: E722
        exit(1)

    exit(0)
