#!/usr/bin/env python3
"""
Read bugs.json (from exp2json) and produce benchmark graphs:
  - Per-bug time to first trigger (bar chart)
  - Cumulative bugs triggered over time (line plot)
  - Summary table (CSV) and optional summary JSON.
"""

import argparse
import json
import sys
from pathlib import Path

def load_bugs_json(path):
    with open(path) as f:
        data = json.load(f)
    return data.get("results", data)

def collect_runs(results, fuzzer="afl", target="libpng", program="libpng_read_fuzzer"):
    """Yield (run_id, triggered_dict, reached_dict) for each run."""
    try:
        by_program = results[fuzzer][target][program]
    except KeyError:
        return
    for run_id, run_data in by_program.items():
        triggered = run_data.get("triggered") or {}
        reached = run_data.get("reached") or {}
        yield run_id, triggered, reached

def aggregate_trigger_times(runs_data):
    """From list of (run_id, triggered_dict), return bug_id -> list of first-trigger times (sec)."""
    from collections import defaultdict
    by_bug = defaultdict(list)
    for _run_id, triggered, _reached in runs_data:
        for bug_id, t in triggered.items():
            by_bug[bug_id].append(int(t))
    return dict(by_bug)

def cumulative_bugs_curve(triggered_dict, poll_resolution=5):
    """From one run's triggered dict (bug_id -> first trigger time in sec), return (times, counts)."""
    if not triggered_dict:
        return [0], [0]
    times_sorted = sorted(triggered_dict.values())
    # At each first-trigger time T, cumulative count goes up by 1
    out_t = [0]
    out_c = [0]
    for t in times_sorted:
        out_t.append(t)
        out_c.append(out_c[-1] + 1)
    return out_t, out_c

def main():
    ap = argparse.ArgumentParser(description="Plot benchmark graphs from bugs.json")
    ap.add_argument("bugs_json", help="Path to bugs.json (output of exp2json)")
    ap.add_argument("-o", "--output-dir", default=".", help="Directory for output PNGs and summary CSV")
    ap.add_argument("--fuzzer", default="afl", help="Fuzzer name in results")
    ap.add_argument("--target", default="libpng", help="Target name")
    ap.add_argument("--program", default="libpng_read_fuzzer", help="Program name")
    args = ap.parse_args()

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib is required: pip install matplotlib", file=sys.stderr)
        sys.exit(1)

    path = Path(args.bugs_json)
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    results = load_bugs_json(path)
    runs_data = list(collect_runs(results, args.fuzzer, args.target, args.program))
    if not runs_data:
        print(f"No runs found for {args.fuzzer}/{args.target}/{args.program}", file=sys.stderr)
        sys.exit(1)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- Per-bug time to first trigger (aggregate: min across runs) ---
    by_bug = aggregate_trigger_times(runs_data)
    if not by_bug:
        print("No triggered bugs in any run.", file=sys.stderr)
    else:
        bug_ids = sorted(by_bug.keys())
        # Use minimum time across runs as "time to first trigger" for that bug
        times = [min(by_bug[b]) for b in bug_ids]
        fig, ax = plt.subplots(figsize=(max(8, len(bug_ids) * 0.4), 5))
        ax.bar(range(len(bug_ids)), [t / 60 for t in times], tick_label=bug_ids, color="steelblue", edgecolor="navy")
        ax.set_xlabel("Bug ID")
        ax.set_ylabel("Time to first trigger (minutes)")
        ax.set_title("Time to first trigger per bug (min across runs)")
        plt.xticks(rotation=45, ha="right")
        plt.tight_layout()
        fig.savefig(out_dir / "benchmark_time_to_first_bug.png", dpi=150)
        plt.close(fig)
        print(f"Wrote {out_dir / 'benchmark_time_to_first_bug.png'}")

    # --- Cumulative bugs over time (one curve per run, or median) ---
    fig, ax = plt.subplots(figsize=(8, 5))
    for run_id, triggered, _ in runs_data:
        t_vals, c_vals = cumulative_bugs_curve(triggered)
        ax.step(t_vals, c_vals, where="post", alpha=0.7, label=f"Run {run_id}")
    ax.set_xlabel("Time (seconds from campaign start)")
    ax.set_ylabel("Cumulative bugs triggered")
    ax.set_title("Bugs triggered over time")
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(out_dir / "benchmark_bugs_over_time.png", dpi=150)
    plt.close(fig)
    print(f"Wrote {out_dir / 'benchmark_bugs_over_time.png'}")

    # --- Summary table (CSV) ---
    summary_rows = []
    for bug_id in sorted(by_bug.keys()):
        trigger_times = by_bug[bug_id]
        summary_rows.append({
            "bug_id": bug_id,
            "time_to_first_trigger_sec_min": min(trigger_times),
            "time_to_first_trigger_sec_median": sorted(trigger_times)[len(trigger_times) // 2] if trigger_times else None,
            "runs_triggered": len(trigger_times),
        })
    csv_path = out_dir / "benchmark_summary.csv"
    if summary_rows:
        import csv as csv_module
        with open(csv_path, "w", newline="") as f:
            w = csv_module.DictWriter(f, fieldnames=["bug_id", "time_to_first_trigger_sec_min", "time_to_first_trigger_sec_median", "runs_triggered"])
            w.writeheader()
            w.writerows(summary_rows)
        print(f"Wrote {csv_path}")

    # --- Optional summary JSON ---
    summary_json = {
        "bugs_json": str(path.resolve()),
        "fuzzer": args.fuzzer,
        "target": args.target,
        "program": args.program,
        "num_runs": len(runs_data),
        "per_bug_min_trigger_sec": {b: min(times) for b, times in by_bug.items()} if by_bug else {},
    }
    json_path = out_dir / "benchmark_summary.json"
    with open(json_path, "w") as f:
        json.dump(summary_json, f, indent=2)
    print(f"Wrote {json_path}")

if __name__ == "__main__":
    main()
