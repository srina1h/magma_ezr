#!/usr/bin/env python3
"""
Build dataset by running all 32 AFL parameter combinations.
Supports resuming from saved state for VCL disconnections.
"""

import argparse
import itertools
import json
import os
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

def run_campaign(label, params, timeout_seconds, captainrc):
    """Run a single fuzzing campaign with given parameters."""
    log(f"Starting campaign: {label}")
    log(f"Parameters: {params}")
    
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
            timeout=timeout_seconds,
            capture_output=True,
            text=True
        )
        elapsed = time.time() - start_time
        
        if result.returncode != 0:
            log(f"Campaign {label} failed with return code {result.returncode}")
            log(f"STDOUT: {result.stdout[-500:]}")
            log(f"STDERR: {result.stderr[-500:]}")
            return False
        
        log(f"Campaign {label} completed in {elapsed:.1f}s")
        return True
        
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start_time
        log(f"Campaign {label} timed out after {elapsed:.1f}s")
        return False

def check_combo_complete(label):
    """Check if a combination has valid results."""
    combo_dir = RESULTS_DIR / label
    metrics_file = combo_dir / "metrics.json"
    return metrics_file.exists()

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
        
        if success and check_combo_complete(label):
            completed_set.add(label)
            state["completed"] = list(completed_set)
            state["in_progress"] = None
            save_state(state)
            log(f"✓ Completed: {label} ({len(completed_set)}/{len(combinations)})")
        else:
            log(f"✗ Failed or incomplete: {label}")
            # Keep in_progress set so we can retry on resume
        
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
