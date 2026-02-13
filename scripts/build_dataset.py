#!/usr/bin/env python3
"""
Build dataset by running all 32 AFL parameter combinations.
Supports resuming from saved state for VCL disconnections.
"""

import argparse
import itertools
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PARAMS_FILE = SCRIPT_DIR / "afl_params.json"
STATE_FILE = REPO_ROOT / "dataset_state.json"
RESULTS_DIR = REPO_ROOT / "dataset_results"
LOG_FILE = REPO_ROOT / "dataset_build.log"

def log(msg):
    """Log message to both stdout and log file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_msg = f"[{timestamp}] {msg}"
    print(log_msg)
    with open(LOG_FILE, "a") as f:
        f.write(log_msg + "\n")

def load_params():
    """Load AFL parameter definitions from JSON."""
    with open(PARAMS_FILE) as f:
        return json.load(f)

def generate_combinations(params):
    """Generate all parameter combinations."""
    param_names = list(params.keys())
    param_values = [params[name] for name in param_names]
    combinations = []
    
    for combo in itertools.product(*param_values):
        combo_dict = {name: val for name, val in zip(param_names, combo)}
        # Generate label: combo_0 through combo_31 based on binary encoding
        binary_str = "".join(str(combo_dict[name]) for name in param_names)
        combo_id = int(binary_str, 2)
        label = f"combo_{combo_id}"
        combinations.append((label, combo_dict))
    
    return combinations

def load_state():
    """Load state file or create new one."""
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {
        "completed": [],
        "in_progress": None,
        "start_time": datetime.now().isoformat(),
        "last_update": None,
        "total_combinations": 32,
        "time_budget_minutes": 20
    }

def save_state(state):
    """Save state file."""
    state["last_update"] = datetime.now().isoformat()
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def parse_timeout(timeout_str):
    """Parse timeout string (e.g., '20m', '1h') to seconds."""
    if timeout_str.endswith("m"):
        return int(timeout_str[:-1]) * 60
    elif timeout_str.endswith("h"):
        return int(timeout_str[:-1]) * 3600
    elif timeout_str.endswith("s"):
        return int(timeout_str[:-1])
    else:
        return int(timeout_str) * 60  # Default to minutes

def check_docker_image():
    """Check if Docker image exists. Returns True if it does."""
    try:
        result = subprocess.run(
            ["docker", "images", "magma/afl/libpng", "--format", "{{.Repository}}"],
            capture_output=True,
            text=True,
            timeout=5
        )
        return "magma" in result.stdout
    except Exception:
        return False

def ensure_docker_image_built():
    """
    Build Docker image if missing. No time limit - wait until build finishes.
    After this, campaigns only use the fuzz time budget (+ small buffer).
    """
    if check_docker_image():
        log("Docker image magma/afl/libpng already exists - skipping build")
        return True
    log("Docker image not found. Building now (no time limit - will wait until done)...")
    prebuild = SCRIPT_DIR / "prebuild_image.sh"
    if not prebuild.exists():
        log("ERROR: scripts/prebuild_image.sh not found")
        return False
    try:
        result = subprocess.run(
            [str(prebuild)],
            cwd=str(REPO_ROOT),
            env=os.environ.copy(),
            timeout=None,  # No timeout - wait for full build
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            log(f"Build failed with exit code {result.returncode}")
            log(f"STDOUT: {result.stdout[-2000:]}")
            log(f"STDERR: {result.stderr[-2000:]}")
            return False
        log("Docker image built successfully. Starting campaigns with time budget only.")
        return True
    except Exception as e:
        log(f"Build failed: {e}")
        return False

def extract_metrics_from_workdir(workdir, results_dir, label):
    """Extract fuzzer_stats from workdir and write metrics.json for label (e.g. after timeout)."""
    workdir = Path(workdir)
    results_dir = Path(results_dir)
    stats_files = list(workdir.rglob("fuzzer_stats"))
    if not stats_files:
        return
    stats_file = stats_files[0]
    text = stats_file.read_text()
    def get(key, default="0"):
        m = re.search(rf"{key}\s*:\s*(\S+)", text)
        return m.group(1) if m else default
    coverage = get("bitmap_cvg", "0")
    paths_total = get("paths_total", "0")
    execs_done = get("execs_done", "0")
    execs_per_sec = get("execs_per_sec", "0")
    out_dir = results_dir / label
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics = {
        "label": label,
        "bitmap_cvg_pct": float(coverage),
        "paths_total": int(paths_total),
        "execs_done": int(execs_done),
        "execs_per_sec": float(execs_per_sec),
        "bugs_triggered": 0,
        "bugs_reached": 0,
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    try:
        import shutil
        shutil.copy(stats_file, out_dir / "fuzzer_stats")
    except Exception:
        pass

def run_campaign(label, params, timeout_seconds, captainrc):
    """Run a single fuzzing campaign with given parameters."""
    log(f"Starting campaign: {label}")
    log(f"Parameters: {params}")
    
    # Build is done separately. Here we only need fuzz budget + small buffer for start/stop.
    effective_timeout = timeout_seconds + 300  # 5 min buffer for container start/stop
    log(f"  Process timeout: {effective_timeout}s (fuzz budget {timeout_seconds}s + buffer)")
    
    # Set environment variables
    env = os.environ.copy()
    for key, value in params.items():
        env[key] = str(value)
    
    # Additional AFL flags for local execution
    env["AFL_SKIP_CPUFREQ"] = "1"
    env["AFL_NO_AFFINITY"] = "1"
    env["AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES"] = "1"
    env["AFL_NO_UI"] = "1"
    
    # Run the campaign script
    cmd = [
        str(SCRIPT_DIR / "run_knob_campaign.sh"),
        label,
        str(captainrc),
        str(RESULTS_DIR)
    ]
    
    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            cwd=str(REPO_ROOT),
            env=env,
            timeout=effective_timeout,
            capture_output=True,
            text=True
        )
        elapsed = time.time() - start_time
        
        if result.returncode != 0:
            log(f"Campaign {label} failed with return code {result.returncode}")
            log(f"STDOUT: {result.stdout[-1000:]}")
            log(f"STDERR: {result.stderr[-1000:]}")
            return False
        
        # Check if campaign actually ran (should take more than a few seconds)
        if elapsed < 5:
            log(f"WARNING: Campaign {label} completed too quickly ({elapsed:.1f}s)")
            log(f"This likely indicates captain failed or didn't run properly")
            log(f"STDOUT: {result.stdout[-1000:]}")
            log(f"STDERR: {result.stderr[-1000:]}")
            return False
        
        log(f"Campaign {label} completed in {elapsed:.1f}s")
        return True
        
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start_time
        log(f"Campaign {label} timed out after {elapsed:.1f}s")
        # Try to extract partial metrics from workdir (in case fuzzer was running)
        workdir = REPO_ROOT / "workdir"
        if workdir.exists():
            try:
                extract_metrics_from_workdir(workdir, RESULTS_DIR, label)
            except Exception as e:
                log(f"  (could not extract partial metrics: {e})")
            # Log diagnostic
            log_dir = workdir / "log"
            if log_dir.exists():
                for f in sorted(log_dir.iterdir())[:5]:
                    if f.is_file():
                        try:
                            tail = f.read_text(errors="replace").strip().split("\n")[-30:]
                            log(f"  --- {f.name} (last 30 lines) ---")
                            for line in tail:
                                log(f"  {line}")
                        except Exception:
                            pass
        log(f"  Check workdir/log/ for build/fuzzing logs")
        return False

def check_combo_complete(label):
    """Check if a combination has valid results."""
    combo_dir = RESULTS_DIR / label
    metrics_file = combo_dir / "metrics.json"
    if not metrics_file.exists():
        return False
    
    # Check if metrics show actual fuzzing happened (not just build failure)
    try:
        with open(metrics_file) as f:
            metrics = json.load(f)
        # If execs_done is 0, fuzzing didn't happen
        execs_done = metrics.get("execs_done", 0)
        if execs_done == 0:
            log(f"  combo {label}: execs_done=0, fuzzing didn't run")
            return False
        # Also check if paths_total > 0 as another indicator
        paths_total = metrics.get("paths_total", 0)
        if paths_total == 0 and execs_done < 100:
            log(f"  combo {label}: paths_total=0 and execs_done={execs_done}, likely incomplete")
            return False
        return True
    except Exception as e:
        log(f"  Error checking combo {label}: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Build dataset by running all AFL parameter combinations"
    )
    parser.add_argument(
        "--budget",
        default="20m",
        help="Time budget per combination (default: 20m)"
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume from saved state"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview combinations without running"
    )
    parser.add_argument(
        "--captainrc",
        default=str(REPO_ROOT / "captainrc.dataset"),
        help="Path to captainrc config file (default: captainrc.dataset)"
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip Docker image build phase (use if image already exists)"
    )
    args = parser.parse_args()
    
    # Parse timeout
    timeout_seconds = parse_timeout(args.budget)
    
    # Load parameters and generate combinations
    params = load_params()
    combinations = generate_combinations(params)
    
    log(f"Loaded {len(combinations)} parameter combinations")
    log(f"Time budget per combination: {args.budget} ({timeout_seconds}s)")
    
    if args.dry_run:
        log("DRY RUN MODE - Preview only")
        for label, combo_params in combinations:
            print(f"  {label}: {combo_params}")
        return
    
    # Load or create state
    state = load_state()
    state["time_budget_minutes"] = timeout_seconds // 60
    save_state(state)
    
    # Create results directory
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    
    # Build Docker image once (no time limit). Then each campaign gets full time budget for fuzzing only.
    if not args.skip_build:
        if not ensure_docker_image_built():
            log("ERROR: Docker image build failed. Fix build and re-run.")
            sys.exit(1)
    else:
        log("Skipping build phase (--skip-build). Image must already exist.")
        if not check_docker_image():
            log("ERROR: Docker image magma/afl/libpng not found. Remove --skip-build or run ./scripts/prebuild_image.sh")
            sys.exit(1)
    
    # Handle resume logic
    completed_set = set(state.get("completed", []))
    in_progress = state.get("in_progress")
    
    if in_progress and in_progress not in completed_set:
        log(f"Found in-progress combination: {in_progress}")
        if check_combo_complete(in_progress):
            log(f"Combination {in_progress} has valid results, marking complete")
            completed_set.add(in_progress)
            state["completed"] = list(completed_set)
            state["in_progress"] = None
            save_state(state)
        else:
            log(f"Restarting combination: {in_progress}")
    
    # Run each combination
    for label, combo_params in combinations:
        if label in completed_set:
            log(f"Skipping completed combination: {label}")
            continue
        
        # Update state
        state["in_progress"] = label
        save_state(state)
        
        # Run campaign
        success = run_campaign(label, combo_params, timeout_seconds, args.captainrc)
        
        # Check if combo completed successfully
        is_complete = check_combo_complete(label)
        
        if success and is_complete:
            completed_set.add(label)
            state["completed"] = list(completed_set)
            state["in_progress"] = None
            save_state(state)
            log(f"✓ Completed: {label} ({len(completed_set)}/{len(combinations)})")
        else:
            if success:
                log(f"✗ Incomplete: {label} (fuzzing didn't run or produced no results)")
                log(f"  Check workdir/log/ for container/fuzzing logs")
            else:
                log(f"✗ Failed: {label} (check logs for details)")
            # Clear in_progress so we don't get stuck retrying the same failing combo
            # User can manually investigate and fix the issue
            state["in_progress"] = None
            save_state(state)
        
        # Brief pause between campaigns
        time.sleep(2)
    
    # Final summary
    log(f"\n{'='*60}")
    log(f"Dataset build complete!")
    log(f"Completed: {len(completed_set)}/{len(combinations)}")
    log(f"Results directory: {RESULTS_DIR}")
    log(f"{'='*60}")

if __name__ == "__main__":
    main()
