#!/usr/bin/env python3
"""
EZR Active Learning Driver for AFL Fuzzer Knob Optimization.

Uses Tim Menzies' EZR (https://github.com/timm/ezr) for multi-objective
active learning over AFL configuration knobs.

Workflow:
  1. Generate a grid of candidate AFL configurations (unlabeled).
  2. EZR picks which configs to evaluate (label) via active learning.
  3. Each "label" = run a 5-min fuzzing campaign, measure coverage + bugs.
  4. EZR learns and picks the next config.
  5. Output: comparison CSV, learning curve, best config recommendation.

Usage:
  python3 scripts/ezr_driver.py [--budget 7] [--timeout 5m] [--seed 42]
"""

import argparse
import itertools
import json
import os
import subprocess
import sys
import time
import csv as csv_module
import random
import math
from pathlib import Path

# ── Add ezr_lib to path ─────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
sys.path.insert(0, str(REPO_ROOT / "ezr_lib"))

from ezr.ezr import (
    Data, clone, add, adds, shuffle, distysort, disty, norm,
    mids, distx, likes, Num, Sym, o, coerce, mid
)
import ezr.ezr as ezr

# ── AFL Knob Space ───────────────────────────────────────────────────────
KNOB_DEFS = {
    "AFL_FAST_CAL":   [0, 1],
    "AFL_NO_ARITH":   [0, 1],
    "AFL_HANG_TMOUT": [50, 200, 500, 1000],
}

# EZR CSV column conventions:
#   Uppercase first letter = numeric column
#   + suffix = maximize,  - suffix = minimize
#
# Our columns:
#   AFL_FAST_CAL, AFL_NO_ARITH, AFL_HANG_TMOUT  → X inputs (knobs)
#   Bitmap_cvg+, Paths_total+, Bugs_triggered+  → Y outputs (maximize)
CSV_HEADER = [
    "AFL_FAST_CAL",     # numeric knob: 0 or 1
    "AFL_NO_ARITH",     # numeric knob: 0 or 1
    "AFL_HANG_TMOUT",   # numeric knob: 50..1000
    "Bitmap_cvg+",      # Y: maximize coverage %
    "Paths_total+",     # Y: maximize paths found
    "Bugs_triggered+",  # Y: maximize bugs
]

FIXED_SEED = 42


def generate_candidate_grid():
    """Generate all combinations of knob values as candidate rows.
    Y columns are set to '?' (unlabeled)."""
    rows = []
    for combo in itertools.product(*KNOB_DEFS.values()):
        row = list(combo) + ["?", "?", "?"]
        rows.append(row)
    return rows


def run_docker_campaign(knobs, label_name, timeout, docker_host):
    """Run a single fuzzing campaign in Docker with given AFL knobs.
    Returns metrics dict with coverage, paths, bugs."""
    env = os.environ.copy()
    env["DOCKER_HOST"] = docker_host
    host_workdir = str(REPO_ROOT / "workdir")

    print(f"\n{'='*60}")
    print(f"[EZR] Campaign: {label_name}")
    print(f"[EZR] Knobs: {knobs}")
    print(f"{'='*60}")

    # Clean workdir via Docker (may be root-owned)
    subprocess.run([
        "docker", "compose", "run", "--rm", "--user", "root", "--no-deps",
        "runner", "rm", "-rf", "/workspace/workdir"
    ], cwd=str(REPO_ROOT), env=env, capture_output=True)

    # Build docker compose run command
    cmd = [
        "docker", "compose", "run", "--rm", "--user", "root",
        "-e", "WORKDIR=/workspace/workdir",
        "-e", f"HOST_WORKDIR={host_workdir}",
        "-e", "BUILD_UID=1000",
        "-e", "BUILD_GID=1000",
    ]
    for k, v in knobs.items():
        cmd.extend(["-e", f"{k}={v}"])
    cmd.extend(["-e", "AFL_SKIP_CPUFREQ=1"])
    cmd.extend(["-e", "AFL_NO_AFFINITY=1"])
    cmd.extend(["-e", "AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1"])
    cmd.extend(["-e", "AFL_NO_UI=1"])
    cmd.extend([
        "runner",
        "./scripts/run_benchmark.sh",
        "/workspace/captainrc.5m",
        "/workspace/bugs.json",
    ])

    start_time = time.time()
    result = subprocess.run(cmd, cwd=str(REPO_ROOT), env=env,
                            capture_output=True, text=True, timeout=900)
    elapsed = time.time() - start_time

    for line in result.stdout.strip().split("\n")[-10:]:
        print(f"  {line}")
    if result.returncode != 0 and result.stderr:
        for line in result.stderr.strip().split("\n")[-5:]:
            print(f"  [stderr] {line}")

    metrics = extract_metrics(elapsed)
    print(f"[EZR] → coverage={metrics['bitmap_cvg']:.2f}%  "
          f"paths={metrics['paths_total']}  "
          f"bugs={metrics['bugs_triggered']}  "
          f"time={elapsed:.0f}s")
    return metrics


def extract_metrics(elapsed):
    """Extract coverage/paths/bugs from the completed campaign."""
    workdir = REPO_ROOT / "workdir"
    metrics = {
        "bitmap_cvg": 0.0,
        "paths_total": 0,
        "bugs_triggered": 0,
        "bugs_reached": 0,
        "execs_done": 0,
        "execs_per_sec": 0.0,
        "wall_time_sec": round(elapsed, 1),
    }

    for stats_file in workdir.rglob("fuzzer_stats"):
        with open(stats_file) as f:
            for line in f:
                if ":" in line:
                    key, val = line.split(":", 1)
                    key, val = key.strip(), val.strip().rstrip("%")
                    if key == "bitmap_cvg":
                        metrics["bitmap_cvg"] = float(val)
                    elif key == "paths_total":
                        metrics["paths_total"] = int(val)
                    elif key == "execs_done":
                        metrics["execs_done"] = int(val)
                    elif key == "execs_per_sec":
                        try: metrics["execs_per_sec"] = float(val)
                        except ValueError: pass
        break

    bugs_json = REPO_ROOT / "bugs.json"
    if bugs_json.exists():
        try:
            with open(bugs_json) as f:
                data = json.load(f)
            results = data.get("results", {})
            for fuzzer in results.values():
                for target in fuzzer.values():
                    for program in target.values():
                        for run in program.values():
                            metrics["bugs_triggered"] += len(run.get("triggered", {}))
                            metrics["bugs_reached"] += len(run.get("reached", {}))
        except Exception as e:
            print(f"  [warn] Could not parse bugs.json: {e}")

    return metrics


def ezr_select_next(candidates, evaluated, seed=42):
    """Use EZR's active learning to pick which candidate to evaluate next.

    Build a Data object from labeled rows.  Score each unlabeled candidate
    using EZR's Bayesian likelihood ratio (best vs rest).  Return the
    most promising unlabeled candidate's knob values.
    """
    random.seed(seed)

    labeled_rows = []
    unlabeled_candidates = []

    for row in candidates:
        knob_key = tuple(row[:3])
        if knob_key in evaluated:
            cvg, paths, bugs = evaluated[knob_key]
            labeled_rows.append([row[0], row[1], row[2], cvg, paths, bugs])
        else:
            unlabeled_candidates.append(row[:3])

    if not unlabeled_candidates:
        return None

    if len(labeled_rows) < 2:
        return random.choice(unlabeled_candidates)

    # Build EZR Data from labeled rows
    data = Data(iter([CSV_HEADER] + labeled_rows))

    # Sort by disty (distance to ideal) — best first
    sorted_rows = distysort(data)

    # Split into best (top sqrt(n)) and rest
    n_best = max(1, round(len(sorted_rows) ** 0.5))
    best_data = clone(data, sorted_rows[:n_best])
    rest_data = clone(data, sorted_rows[n_best:])

    # Score each unlabeled candidate by likelihood ratio
    nall = best_data.n + rest_data.n
    scores = []
    for knobs in unlabeled_candidates:
        # Create a row with knob values + median Y values as placeholders
        fake_row = list(knobs) + [mid(c) for c in data.cols.y]
        b = math.exp(likes(best_data, fake_row, nall, 2))
        r = math.exp(likes(rest_data, fake_row, nall, 2))
        score = (b * b) / (r + 1e-32)
        scores.append((score, knobs))

    scores.sort(key=lambda x: x[0], reverse=True)
    return scores[0][1]


def generate_comparison(all_results, output_dir):
    """Generate comparison CSV and plots."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    output_dir.mkdir(parents=True, exist_ok=True)

    # CSV
    csv_path = output_dir / "ezr_comparison.csv"
    fieldnames = [
        "round", "AFL_FAST_CAL", "AFL_NO_ARITH", "AFL_HANG_TMOUT",
        "bitmap_cvg", "paths_total", "execs_done", "execs_per_sec",
        "bugs_triggered", "bugs_reached", "wall_time_sec"
    ]
    with open(csv_path, "w", newline="") as f:
        w = csv_module.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        w.writerows(all_results)
    print(f"\n[EZR] Wrote {csv_path}")

    labels = [str(r["round"]) for r in all_results]
    coverages = [float(r.get("bitmap_cvg", 0)) for r in all_results]
    bugs = [int(r.get("bugs_triggered", 0)) for r in all_results]
    paths = [int(r.get("paths_total", 0)) for r in all_results]

    # 3-panel bar chart
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    colors = ["#E53935" if i == 0 else "#1E88E5" for i in range(len(labels))]

    axes[0].bar(range(len(labels)), coverages, color=colors, edgecolor="navy")
    axes[0].set_xticks(range(len(labels)))
    axes[0].set_xticklabels(labels, rotation=45, ha="right", fontsize=9)
    axes[0].set_ylabel("Bitmap Coverage (%)")
    axes[0].set_title("Edge Coverage by Configuration")

    axes[1].bar(range(len(labels)), paths, color=colors, edgecolor="navy")
    axes[1].set_xticks(range(len(labels)))
    axes[1].set_xticklabels(labels, rotation=45, ha="right", fontsize=9)
    axes[1].set_ylabel("Total Paths")
    axes[1].set_title("Paths Discovered by Configuration")

    axes[2].bar(range(len(labels)), bugs, color=colors, edgecolor="darkred")
    axes[2].set_xticks(range(len(labels)))
    axes[2].set_xticklabels(labels, rotation=45, ha="right", fontsize=9)
    axes[2].set_ylabel("Bugs Triggered")
    axes[2].set_title("Bugs Found by Configuration")

    plt.suptitle("EZR Active Learning: AFL Knob Optimization for libpng\n"
                 "(Red = Baseline, Blue = EZR-selected)",
                 fontsize=14, fontweight="bold")
    plt.tight_layout()
    fig.savefig(output_dir / "ezr_comparison.png", dpi=150)
    plt.close(fig)
    print(f"[EZR] Wrote {output_dir / 'ezr_comparison.png'}")

    # Learning curve
    fig, ax = plt.subplots(figsize=(10, 5))
    rounds = list(range(len(all_results)))
    ax.plot(rounds, coverages, "o-", color="#1E88E5", linewidth=2,
            markersize=8, label="Bitmap Coverage %")
    if coverages:
        baseline = coverages[0]
        ax.axhline(y=baseline, color="red", linestyle="--", alpha=0.6,
                    label=f"Baseline ({baseline:.2f}%)")
        ax.fill_between(rounds, baseline, coverages,
                        where=[c > baseline for c in coverages],
                        alpha=0.15, color="green", label="Improvement")
    ax.set_xlabel("Round")
    ax.set_ylabel("Bitmap Coverage (%)")
    ax.set_title("EZR Learning Curve: Coverage Over Active Learning Rounds")
    ax.set_xticks(rounds)
    ax.set_xticklabels(labels, rotation=45, ha="right", fontsize=9)
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(output_dir / "ezr_learning_curve.png", dpi=150)
    plt.close(fig)
    print(f"[EZR] Wrote {output_dir / 'ezr_learning_curve.png'}")

    # EZR-compatible CSV (for feeding back into `python3 -m ezr -f ...`)
    ezr_csv_path = output_dir / "afl_knobs_ezr.csv"
    with open(ezr_csv_path, "w") as f:
        f.write(",".join(CSV_HEADER) + "\n")
        for r in all_results:
            f.write(f"{r['AFL_FAST_CAL']},{r['AFL_NO_ARITH']},"
                    f"{r['AFL_HANG_TMOUT']},{r['bitmap_cvg']},"
                    f"{r['paths_total']},{r['bugs_triggered']}\n")
    print(f"[EZR] Wrote {ezr_csv_path}")
    print(f"      (EZR-compatible: run `cd ezr_lib && python3 -m ezr -f ../{ezr_csv_path.relative_to(REPO_ROOT)}`)")

    # Final ranking
    ranked = sorted(all_results,
                    key=lambda r: (r["bitmap_cvg"], r["paths_total"], r["bugs_triggered"]),
                    reverse=True)
    print(f"\n{'='*60}")
    print("[EZR] FINAL RANKING (best → worst)")
    print(f"{'='*60}")
    for i, r in enumerate(ranked):
        marker = " ← BASELINE" if r["round"] == "0_baseline" else ""
        print(f"  #{i+1}: round={r['round']:20s}  "
              f"cov={r['bitmap_cvg']:6.2f}%  "
              f"paths={r['paths_total']:5d}  "
              f"bugs={r['bugs_triggered']}{marker}")

    best = ranked[0]
    print(f"\n[EZR] ★ Best config: round={best['round']}")
    print(f"       AFL_FAST_CAL={best['AFL_FAST_CAL']}  "
          f"AFL_NO_ARITH={best['AFL_NO_ARITH']}  "
          f"AFL_HANG_TMOUT={best['AFL_HANG_TMOUT']}")
    print(f"       Coverage: {best['bitmap_cvg']:.2f}%  "
          f"Paths: {best['paths_total']}  "
          f"Bugs: {best['bugs_triggered']}")


def main():
    ap = argparse.ArgumentParser(
        description="EZR Active Learning Driver for AFL Knob Optimization")
    ap.add_argument("--budget", type=int, default=7,
                    help="Total campaigns to run (1 baseline + N exploration, default: 7)")
    ap.add_argument("--timeout", default="5m",
                    help="Timeout per campaign (default: 5m)")
    ap.add_argument("--seed", type=int, default=FIXED_SEED,
                    help="Random seed for reproducibility (default: 42)")
    ap.add_argument("--docker-host", default="unix:///var/run/docker.sock")
    ap.add_argument("--output-dir", default=None,
                    help="Output directory (default: <repo>/ezr_results)")
    args = ap.parse_args()

    output_dir = Path(args.output_dir) if args.output_dir else REPO_ROOT / "ezr_results"
    output_dir.mkdir(parents=True, exist_ok=True)

    random.seed(args.seed)

    candidates = generate_candidate_grid()
    print(f"[EZR] Generated {len(candidates)} candidate configurations")
    print(f"[EZR] Budget: {args.budget} campaigns ({args.timeout} each)")
    print(f"[EZR] Seed: {args.seed}")
    print(f"[EZR] Knob space: {KNOB_DEFS}")

    evaluated = {}   # tuple(knob_values) -> (cvg, paths, bugs)
    all_results = []

    # ── Round 0: Baseline (default knobs) ──
    baseline_knobs = {"AFL_FAST_CAL": "0", "AFL_NO_ARITH": "0", "AFL_HANG_TMOUT": "200"}
    metrics = run_docker_campaign(baseline_knobs, "0_baseline", args.timeout, args.docker_host)
    knob_key = (0, 0, 200)
    evaluated[knob_key] = (metrics["bitmap_cvg"], metrics["paths_total"], metrics["bugs_triggered"])
    all_results.append({"round": "0_baseline", **baseline_knobs, **metrics})

    # ── Rounds 1..budget-1: EZR-guided exploration ──
    for i in range(1, args.budget):
        print(f"\n[EZR] ── Round {i}/{args.budget-1} ──")
        print(f"[EZR] Asking EZR to select next config ({len(evaluated)} labeled so far)...")

        next_knobs_vals = ezr_select_next(candidates, evaluated, seed=args.seed + i)

        if next_knobs_vals is None:
            print("[EZR] All candidates evaluated!")
            break

        knobs = {
            "AFL_FAST_CAL": str(int(next_knobs_vals[0])),
            "AFL_NO_ARITH": str(int(next_knobs_vals[1])),
            "AFL_HANG_TMOUT": str(int(next_knobs_vals[2])),
        }
        knob_key = tuple(int(v) for v in next_knobs_vals)

        if knob_key in evaluated:
            print(f"[EZR] Config {knobs} already evaluated, picking random unevaluated...")
            unevaluated = [c[:3] for c in candidates if tuple(c[:3]) not in evaluated]
            if not unevaluated:
                print("[EZR] All candidates evaluated!")
                break
            next_knobs_vals = random.choice(unevaluated)
            knobs = {
                "AFL_FAST_CAL": str(int(next_knobs_vals[0])),
                "AFL_NO_ARITH": str(int(next_knobs_vals[1])),
                "AFL_HANG_TMOUT": str(int(next_knobs_vals[2])),
            }
            knob_key = tuple(int(v) for v in next_knobs_vals)

        label_name = f"{i}_fc{knobs['AFL_FAST_CAL']}_na{knobs['AFL_NO_ARITH']}_ht{knobs['AFL_HANG_TMOUT']}"
        metrics = run_docker_campaign(knobs, label_name, args.timeout, args.docker_host)
        evaluated[knob_key] = (metrics["bitmap_cvg"], metrics["paths_total"], metrics["bugs_triggered"])
        all_results.append({"round": label_name, **knobs, **metrics})

        best_key = max(evaluated, key=lambda k: evaluated[k][0])
        print(f"[EZR] Current best: knobs={best_key} coverage={evaluated[best_key][0]:.2f}%")

    # ── Generate outputs ──
    generate_comparison(all_results, output_dir)

    with open(output_dir / "all_results.json", "w") as f:
        json.dump(all_results, f, indent=2, default=str)
    print(f"[EZR] Wrote {output_dir / 'all_results.json'}")

    print(f"\n[EZR] Done! Total campaigns: {len(all_results)}")
    print(f"[EZR] Results in: {output_dir}/")


if __name__ == "__main__":
    main()
