#!/usr/bin/env python3
"""
Verify that Pandoomain browser visualization databases are correctly created.
"""

import os
import sqlite3
import sys
from pathlib import Path


def verify_db(db_path: Path, table_name: str, expected_cols: list) -> bool:
    """
    Verify a single SQLite database.

    Args:
        db_path: Path to the database file.
        table_name: Expected table name.
        expected_cols: List of expected column names.

    Returns:
        True if valid, False otherwise.
    """
    print(f"Verifying {db_path}...")
    
    if not db_path.exists():
        print(f"  ERROR: File not found: {db_path}")
        return False

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # Check table existence
        cursor.execute(
            f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table_name}';"
        )
        if not cursor.fetchone():
            print(f"  ERROR: Table '{table_name}' not found.")
            return False

        # Check columns
        cursor.execute(f"PRAGMA table_info({table_name})")
        columns = [row[1] for row in cursor.fetchall()]
        
        missing_cols = [col for col in expected_cols if col not in columns]
        if missing_cols:
            print(f"  ERROR: Missing columns in '{table_name}': {missing_cols}")
            return False

        # Quick row count check
        cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = cursor.fetchone()[0]
        print(f"  Found {count} rows in '{table_name}'.")

        conn.close()
        print(f"  OK.")
        return True

    except Exception as e:
        print(f"  ERROR verifying database: {e}")
        return False


def main():
    results_dir = Path("tests/results/browser_visualizer")
    
    databases = [
        {
            "path": results_dir / "iscan.db",
            "table": "iscan",
            "cols": ["pid", "start", "stop", "length", "pfam", "pfam_desc"],
        },
        {
            "path": results_dir / "metadata.db",
            "table": "metadata",
            "cols": ["genome", "org", "strain"],
        },
        {
            "path": results_dir / "neighbors.db",
            "table": "neighbors",
            "cols": ["genome", "nei", "pid", "gene"],
        },
    ]

    all_valid = True
    for db in databases:
        if not verify_db(db["path"], db["table"], db["cols"]):
            all_valid = False

    if all_valid:
        print("\nAll browser databases verified successfully!")
        sys.exit(0)
    else:
        print("\nSome browser databases failed verification.")
        sys.exit(1)


if __name__ == "__main__":
    main()
