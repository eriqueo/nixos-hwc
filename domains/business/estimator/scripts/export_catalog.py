#!/usr/bin/env python3
"""Permanent operator entry for the PostgreSQL catalog exporter.

The retired SQLite producer wrote the same files from an absent database.
All arguments pass to the database owner's one exporter.
"""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parents[2] / "databases" / "export_estimator_data.py"),
                   run_name="__main__")
