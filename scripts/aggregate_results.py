#!/usr/bin/env python3
"""
Aggregate results from all completed combinations into a single CSV dataset.
"""

import argparse
import csv
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
RESULTS_DIR = REPO_ROOT / "dataset_results"
OUTPUT_CSV = REPO_ROOT / "dataset_results.csv"

def load_metrics(combo_dir):
    """Load metrics.json from a combination directory."""
    metrics_file = combo_dir / "metrics.json"
    if not metrics_file.exists():
        return None
    
    with open(metrics_file) as f:
        return json.load(f)

def parse_afl_knobs(knobs_str):
    """Parse AFL knobs string into individual values."""
    # Format: "AFL_FAST_CAL=0;AFL_NO_ARITH=1;..."
    knobs = {}
    for pair in knobs_str.split(";"):
        if "=" in pair:
            key, value = pair.split("=", 1)
            knobs[key.strip()] = value.strip()
    return knobs

def main():
    parser = argparse.ArgumentParser(
        description="Aggregate dataset results into CSV"
    )
    parser.add_argument(
        "--output",
        default=str(OUTPUT_CSV),
        help="Output CSV file path (default: dataset_results.csv)"
    )
    args = parser.parse_args()
    
    if not RESULTS_DIR.exists():
        print(f"Error: Results directory not found: {RESULTS_DIR}")
        return 1
    
    # Find all combination directories
    combo_dirs = sorted([d for d in RESULTS_DIR.iterdir() if d.is_dir() and d.name.startswith("combo_")])
    
    if not combo_dirs:
        print(f"Error: No combination directories found in {RESULTS_DIR}")
        return 1
    
    # Collect all results
    results = []
    for combo_dir in combo_dirs:
        metrics = load_metrics(combo_dir)
        if not metrics:
            print(f"Warning: No metrics.json found in {combo_dir.name}")
            continue
        
        # Extract AFL knob values
        knobs_str = metrics.get("afl_knobs", "")
        knobs = parse_afl_knobs(knobs_str)
        
        # Build result row
        row = {
            "combo_id": combo_dir.name,
            "AFL_FAST_CAL": knobs.get("AFL_FAST_CAL", "?"),
            "AFL_NO_ARITH": knobs.get("AFL_NO_ARITH", "?"),
            "AFL_NO_HAVOC": knobs.get("AFL_NO_HAVOC", "?"),
            "AFL_DISABLE_TRIM": knobs.get("AFL_DISABLE_TRIM", "?"),
            "AFL_SHUFFLE_QUEUE": knobs.get("AFL_SHUFFLE_QUEUE", "?"),
            "bitmap_cvg_pct": metrics.get("bitmap_cvg_pct", 0),
            "paths_total": metrics.get("paths_total", 0),
            "execs_done": metrics.get("execs_done", 0),
            "execs_per_sec": metrics.get("execs_per_sec", 0),
            "bugs_triggered": metrics.get("bugs_triggered", 0),
            "bugs_reached": metrics.get("bugs_reached", 0),
        }
        results.append(row)
    
    # Write CSV
    if not results:
        print("Error: No valid results found")
        return 1
    
    fieldnames = [
        "combo_id",
        "AFL_FAST_CAL",
        "AFL_NO_ARITH",
        "AFL_NO_HAVOC",
        "AFL_DISABLE_TRIM",
        "AFL_SHUFFLE_QUEUE",
        "bitmap_cvg_pct",
        "paths_total",
        "execs_done",
        "execs_per_sec",
        "bugs_triggered",
        "bugs_reached",
    ]
    
    output_path = Path(args.output)
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    
    print(f"✓ Aggregated {len(results)} combinations")
    print(f"✓ Output: {output_path}")
    
    # Print summary statistics
    if results:
        coverages = [r["bitmap_cvg_pct"] for r in results]
        bugs = [r["bugs_triggered"] for r in results]
        paths = [r["paths_total"] for r in results]
        
        print(f"\nSummary:")
        print(f"  Coverage: min={min(coverages):.2f}%, max={max(coverages):.2f}%, avg={sum(coverages)/len(coverages):.2f}%")
        print(f"  Bugs triggered: min={min(bugs)}, max={max(bugs)}, total={sum(bugs)}")
        print(f"  Paths: min={min(paths)}, max={max(paths)}, avg={sum(paths)/len(paths):.0f}")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
