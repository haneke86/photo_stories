#!/usr/bin/env python3
"""
MacPhoto Travel Stats Dashboard

Reads geotagged photo data from the macOS Photos library and generates
an interactive HTML dashboard with maps and travel statistics.

Usage:
    python main.py [--db-path PATH] [--debug-plists] [--no-open]
"""

import argparse
import os
import sqlite3
import sys
import webbrowser
from datetime import datetime

from extract import extract_photo_data
from dashboard import generate_dashboard


def main():
    parser = argparse.ArgumentParser(
        description="Generate a travel stats dashboard from your macOS Photos library."
    )
    parser.add_argument(
        "--db-path",
        help="Path to Photos.sqlite (uses default Photos library if omitted)",
    )
    parser.add_argument(
        "--debug-plists",
        action="store_true",
        help="Print the structure of the first few reverse location plists for debugging",
    )
    parser.add_argument(
        "--no-open",
        action="store_true",
        help="Don't auto-open the dashboard in a browser",
    )
    args = parser.parse_args()

    print()
    print("  ==========================================")
    print("    MacPhoto Travel Stats Dashboard")
    print("  ==========================================")
    print()

    # Step 1: Extract photo data
    print("Reading Photos library...")
    try:
        df = extract_photo_data(
            db_path=args.db_path,
            debug_plists=args.debug_plists,
        )
    except FileNotFoundError as e:
        print(f"\n  Error: {e}")
        sys.exit(1)
    except sqlite3.OperationalError as e:
        error_msg = str(e).lower()
        if "unable to open" in error_msg or "not authorized" in error_msg:
            print("\n  Permission denied! Full Disk Access is required.")
            print("  Go to: System Settings > Privacy & Security > Full Disk Access")
            print("  Add your Terminal app (Terminal, iTerm2, etc.) to the list.")
            sys.exit(1)
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "operation not permitted" in error_msg:
            print("\n  Permission denied! Full Disk Access is required.")
            print("  Go to: System Settings > Privacy & Security > Full Disk Access")
            print("  Add your Terminal app (Terminal, iTerm2, etc.) to the list.")
            sys.exit(1)
        raise

    # Step 2: Print summary
    if df.empty:
        print("No geotagged photos found in the last 6 years.")
    else:
        n_countries = df["country"].nunique()
        n_cities = df["city"].nunique()
        print(f"Found {len(df):,} geotagged photos across {n_countries} countries and {n_cities} cities.")

    # Step 3: Generate dashboard
    timestamp = datetime.now().strftime("%Y-%m-%d-%H%M")
    output_path = os.path.join(
        os.path.dirname(__file__),
        "output",
        f"{timestamp}-travel-dashboard.html",
    )

    print("Generating dashboard...")
    generate_dashboard(df, output_path)

    # Step 4: Open in browser
    if not args.no_open:
        file_url = f"file://{os.path.abspath(output_path)}"
        print(f"Opening in browser...")
        webbrowser.open(file_url)

    print("\nDone!")


if __name__ == "__main__":
    main()
