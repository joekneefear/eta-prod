#!/usr/bin/env python3
"""Run SQL migration file against Oracle using python-oracledb.

Usage:
  ORACLE_DSN=host:port/service ORACLE_USER=... ORACLE_PASSWORD=... python scripts/run_migration.py

This is intentionally small and pragmatic: it reads `sql/create_pipeline_runs.sql`,
splits statements on semicolons and executes each non-empty statement. It is not a
full-featured migration framework but is useful for quick local/apply runs.
"""
import os
import sys
from pathlib import Path

def load_sql(path: Path) -> str:
    return path.read_text(encoding="utf-8")

def split_statements(sql: str):
    # Very small splitter: split on semicolons. This assumes semicolons are
    # used only as statement terminators in the migration file.
    parts = [p.strip() for p in sql.split(';')]
    return [p for p in parts if p]

def main():
    dsn = os.environ.get('ORACLE_DSN')
    user = os.environ.get('ORACLE_USER')
    password = os.environ.get('ORACLE_PASSWORD')

    if not all([dsn, user, password]):
        print("Missing ORACLE_DSN, ORACLE_USER or ORACLE_PASSWORD environment variables.", file=sys.stderr)
        sys.exit(2)

    sql_path = Path(__file__).parents[1] / 'sql' / 'create_pipeline_runs.sql'
    if not sql_path.exists():
        print(f"SQL file not found: {sql_path}", file=sys.stderr)
        sys.exit(2)

    try:
        import oracledb
    except Exception:
    print("python-oracledb is required (cx_Oracle deprecated). Install with: pip install python-oracledb", file=sys.stderr)
        sys.exit(2)

    sql_text = load_sql(sql_path)
    statements = split_statements(sql_text)

    print(f"Connecting to Oracle DSN={dsn} as {user}")
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    try:
        cur = conn.cursor()
        for i, stmt in enumerate(statements, 1):
            try:
                print(f"Executing statement {i}/{len(statements)}...")
                cur.execute(stmt)
            except Exception as e:
                print(f"Error executing statement {i}: {e}", file=sys.stderr)
                # Abort on error; you may want to continue for idempotent ops
                conn.rollback()
                raise
        conn.commit()
        print("Migration applied successfully.")
    finally:
        conn.close()

if __name__ == '__main__':
    main()
