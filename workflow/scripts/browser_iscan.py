#!/usr/bin/env python3
"""
Convert InterProScan TSV results to a SQL dump file.

This script reads the InterProScan TSV output and creates a SQL text file
that can be piped into sqlite3 to create the database.

RATIONALE:
Directly writing to a SQLite database on a network file system (NFS/CIFS) often
results in "database is locked" errors due to poor file locking implementations.
By generating a textual SQL dump (.sql) first, we decouple data processing from
database writing. The final DB is built in a single stream operation using the
'sqlite3' command line tool, which avoids these locking conflicts.
"""

import argparse
import os
import sys
import pandas as pd


def tsv_to_sql(input_tsv: str, output_sql: str, chunk_size: int = 100000) -> None:
    """
    Convert the iscan TSV file to a SQL dump file.

    Args:
        input_tsv: Path to the input TSV file.
        output_sql: Path to the output SQL file.
        chunk_size: Number of rows to process at a time.
    """
    table_name = "iscan"

    print(f"--- Starting TSV to SQL Dump for InterProScan ---")
    print(f"Input: {input_tsv}")
    print(f"Output: {output_sql}")

    if not os.path.exists(input_tsv):
        print(f"ERROR: Input file not found at '{input_tsv}'", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    output_dir = os.path.dirname(output_sql)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"Writing SQL to: {output_sql}")

    try:
        # Columns to use from the TSV (0-indexed)
        # 0: pid, 1: start, 2: stop, 3: length, 7: pfam, 8: pfam_desc
        cols_to_use = [0, 1, 2, 3, 7, 8]
        col_names = ["pid", "start", "stop", "length", "pfam", "pfam_desc"]
        
        # Specify dtypes to avoid warnings and mixed type issues
        dtypes = {
            1: "str", # start
            2: "str", # stop
            3: "str", # length
            7: "str", # pfam
            8: "str"  # pfam_desc
        }

        with open(output_sql, "w") as f:
            # Preamble
            f.write("PRAGMA synchronous = OFF;\n")
            f.write("PRAGMA journal_mode = MEMORY;\n")
            f.write("BEGIN TRANSACTION;\n")

            # Create Table - using appropriate types
            # pid TEXT, start INTEGER, stop INTEGER, length INTEGER, pfam TEXT, pfam_desc TEXT
            create_table_sql = (
                f"CREATE TABLE IF NOT EXISTS {table_name} ("
                "pid TEXT, start INTEGER, stop INTEGER, length INTEGER, pfam TEXT, pfam_desc TEXT);\n"
            )
            f.write(create_table_sql)
            
            # Index DDL
            index_sql = f"CREATE INDEX IF NOT EXISTS idx_iscan_pid ON {table_name} (pid);\n"

            print(f"Reading and loading chunks from {input_tsv}...")
            
            reader = pd.read_csv(
                input_tsv,
                sep="\t",
                header=None,
                chunksize=chunk_size,
                iterator=True,
                usecols=cols_to_use,
                dtype=dtypes,
                low_memory=False,
                comment="#",
            )

            for i, chunk in enumerate(reader):
                print(f"  Processing chunk {i + 1}...", end="\r")

                chunk.columns = col_names

                # Ensure correct data types for integers
                # We do this in python to handle empty strings/NaNs safely
                chunk["start"] = pd.to_numeric(chunk["start"], errors="coerce").fillna(0).astype(int)
                chunk["stop"] = pd.to_numeric(chunk["stop"], errors="coerce").fillna(0).astype(int)
                chunk["length"] = pd.to_numeric(chunk["length"], errors="coerce").fillna(0).astype(int)
                
                # Generate INSERTs
                for row in chunk.itertuples(index=False, name=None):
                    # row structure: (pid, start, stop, length, pfam, pfam_desc)
                    # pid (str), start (int), stop (int), length (int), pfam (str), pfam_desc (str)
                    
                    pid = str(row[0]).replace("'", "''") if pd.notna(row[0]) else ""
                    start = row[1]
                    stop = row[2]
                    length = row[3]
                    pfam = str(row[4]).replace("'", "''") if pd.notna(row[4]) else ""
                    pfam_desc = str(row[5]).replace("'", "''") if pd.notna(row[5]) else ""
                    
                    # Construct SQL value string - integers don't need quotes
                    val_str = f"'{pid}', {start}, {stop}, {length}, '{pfam}', '{pfam_desc}'"
                    
                    f.write(f"INSERT INTO {table_name} (pid, start, stop, length, pfam, pfam_desc) VALUES ({val_str});\n")
            
            print("\nAll chunks processed.")
            f.write("COMMIT;\n")
            f.write(index_sql)

    except Exception as e:
        print(f"\nERROR during processing: {e}", file=sys.stderr)
        if os.path.exists(output_sql):
            os.remove(output_sql)
        sys.exit(1)

    print("--- Conversion to SQL complete! ---")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert InterProScan TSV to SQL dump for browser visualizer."
    )
    parser.add_argument("input_tsv", help="Path to input TSV file")
    parser.add_argument("output_sql", help="Path to output SQL file")
    
    args = parser.parse_args()
    
    tsv_to_sql(args.input_tsv, args.output_sql)


if __name__ == "__main__":
    main()
