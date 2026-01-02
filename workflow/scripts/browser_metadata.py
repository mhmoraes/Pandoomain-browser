#!/usr/bin/env python3
"""
Convert Genome Metadata TSV to a SQL dump file.

This script reads the genomes_metadata.tsv output and creates a SQL text file
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


def tsv_to_sql(input_tsv: str, output_sql: str) -> None:
    """
    Convert the metadata TSV file to a SQL dump file.

    Args:
        input_tsv: Path to the input TSV file.
        output_sql: Path to the output SQL file.
    """
    table_name = "metadata"
    required_columns = ["genome", "org", "strain"]

    print(f"--- Starting TSV to SQL Dump for Metadata ---")
    print(f"Input: {input_tsv}")
    print(f"Output: {output_sql}")

    if not os.path.exists(input_tsv):
        print(f"ERROR: Input file not found at '{input_tsv}'", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    output_dir = os.path.dirname(output_sql)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"Inspecting header of {input_tsv}...")
    try:
        header = pd.read_csv(input_tsv, sep="\t", nrows=0).columns.tolist()
        cols_to_use = [col for col in required_columns if col in header]

        if not cols_to_use:
            print(f"ERROR: None of required cols {required_columns} found.", file=sys.stderr)
            sys.exit(1)
        
        if "genome" not in cols_to_use:
            print(f"ERROR: Essential 'genome' column missing.", file=sys.stderr)
            sys.exit(1)

        print(f"  ...Found columns: {cols_to_use}")

    except Exception as e:
        print(f"ERROR reading header: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Writing SQL to: {output_sql}")
    
    try:
        with open(output_sql, "w") as f:
            # Preamble for speed
            f.write("PRAGMA synchronous = OFF;\n")
            f.write("PRAGMA journal_mode = MEMORY;\n")
            f.write("BEGIN TRANSACTION;\n")
            
            # Create Table
            # We assume all columns are TEXT for metadata to be safe, or we could infer.
            # Given it's metadata, TEXT is usually fine.
            cols_def = ", ".join([f"{col} TEXT" for col in required_columns])
            f.write(f"CREATE TABLE IF NOT EXISTS {table_name} ({cols_def});\n")
            
            # Create Index DDL (to be executed at the end)
            index_sql = f"CREATE INDEX IF NOT EXISTS idx_metadata_genome ON {table_name} (genome);\n"

            print(f"Processing data from {input_tsv}...")
            
            # Read and write chunks
            chunk_size = 10000
            reader = pd.read_csv(input_tsv, sep="\t", usecols=cols_to_use, chunksize=chunk_size)

            for chunk in reader:
                # Ensure all required columns are present
                for col in required_columns:
                    if col not in chunk.columns:
                        chunk[col] = None
                
                # Reorder
                chunk = chunk[required_columns]
                
                # Generate INSERT values efficiently
                for row in chunk.itertuples(index=False, name=None):
                    # Escape single quotes in strings
                    values = []
                    for val in row:
                        if pd.isna(val):
                            values.append("NULL")
                        else:
                            val_str = str(val).replace("'", "''")
                            values.append(f"'{val_str}'")
                    
                    val_str = ", ".join(values)
                    f.write(f"INSERT INTO {table_name} ({', '.join(required_columns)}) VALUES ({val_str});\n")
            
            f.write("COMMIT;\n")
            # Create index after commit for speed
            f.write(index_sql)
            
    except Exception as e:
        print(f"ERROR generating SQL: {e}", file=sys.stderr)
        # remove incomplete file
        if os.path.exists(output_sql):
            os.remove(output_sql)
        sys.exit(1)

    print("--- Conversion to SQL complete! ---")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Metadata TSV to SQL dump for browser visualizer."
    )
    parser.add_argument("input_tsv", help="Path to input TSV file")
    parser.add_argument("output_sql", help="Path to output SQL file")
    
    args = parser.parse_args()
    
    tsv_to_sql(args.input_tsv, args.output_sql)


if __name__ == "__main__":
    main()
