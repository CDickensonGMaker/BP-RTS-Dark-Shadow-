#!/usr/bin/env python3
"""
BattleDebug Scheduled Runner

Runs nightly or on-demand agent sessions and appends findings.
Can be triggered by Windows Task Scheduler, cron, or manually.

Usage:
    python schedule_runner.py                    # Run default session
    python schedule_runner.py --calibration     # Run calibration check
    python schedule_runner.py --stress 20       # Run 20 stress test rounds

For Windows Task Scheduler:
    Program: python
    Arguments: C:\\Users\\caleb\\BP_RTS_Dark_Shadows\\tools\\agent\\schedule_runner.py
    Start in: C:\\Users\\caleb\\BP_RTS_Dark_Shadows\\tools\\agent

For cron (Linux/Mac):
    0 2 * * * cd /path/to/project/tools/agent && python schedule_runner.py
"""

import argparse
import json
import sys
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional


# Configuration
PROJECT_PATH = r"C:\Users\caleb\BP_RTS_Dark_Shadows"
GODOT_EXECUTABLE = "godot"  # Or full path to godot.exe
DEFAULT_BUDGET = 5
DEFAULT_STRESS_ROUNDS = 10


def run_scheduled_session(
    mode: str = "stress",
    budget: int = DEFAULT_BUDGET,
    stress_rounds: int = DEFAULT_STRESS_ROUNDS,
) -> dict:
    """
    Run a scheduled session and return summary.

    Args:
        mode: 'stress', 'calibration', or 'general'
        budget: Number of experiments for general mode
        stress_rounds: Number of rounds for stress test

    Returns:
        Summary dictionary
    """
    start_time = datetime.now()
    print(f"[ScheduledRunner] Starting at {start_time.isoformat()}")
    print(f"[ScheduledRunner] Mode: {mode}")

    from run_session import BattleDebugSession

    session = BattleDebugSession(
        project_path=PROJECT_PATH,
        budget=budget,
        focus="general",
        godot_executable=GODOT_EXECUTABLE
    )

    findings_count = 0

    try:
        if mode == "stress":
            # Run stress test
            print(f"[ScheduledRunner] Running {stress_rounds} stress test rounds...")
            result = session.orchestrator.run_stress_test(
                rounds=stress_rounds,
                duration=60.0,
                units_per_side=4
            )

            # Analyze for anomalies
            if result.get('errors'):
                for error in result['errors'][:5]:  # First 5 errors
                    session.write_finding({
                        "severity": "medium",
                        "category": "bug",
                        "title": f"Stress test error: {error.get('error', 'Unknown')[:50]}",
                        "summary": f"Error in round {error.get('round', '?')}: {error.get('error', 'Unknown')}",
                        "evidence": {
                            "experiment": "stress_test",
                            "n_battles": stress_rounds,
                            "key_stats": {"error_round": error.get('round', 0)}
                        },
                        "hypothesis": "Combat system encountered unexpected state",
                        "suggested_action": "Review error details in stress test log",
                        "confidence": 0.7
                    })
                    findings_count += 1

        elif mode == "calibration":
            # Run calibration check
            from run_session import run_calibration_session
            run_calibration_session(session)
            findings_count = len(session.findings)

        else:
            # General mode - just run stress test as baseline
            result = session.orchestrator.run_stress_test(
                rounds=stress_rounds,
                duration=60.0,
                units_per_side=4
            )

    except Exception as e:
        print(f"[ScheduledRunner] Error: {e}")
        return {
            "status": "error",
            "error": str(e),
            "start_time": start_time.isoformat()
        }

    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    summary = {
        "status": "success",
        "mode": mode,
        "start_time": start_time.isoformat(),
        "end_time": end_time.isoformat(),
        "duration_seconds": duration,
        "findings_count": findings_count,
        "session_id": session.session_id
    }

    print(f"\n[ScheduledRunner] Completed in {duration:.1f}s")
    print(f"[ScheduledRunner] Findings: {findings_count}")

    # Log the run
    log_path = Path(PROJECT_PATH) / "tools" / "agent" / "schedule_log.json"
    logs = []
    if log_path.exists():
        try:
            logs = json.loads(log_path.read_text())
        except:
            pass
    logs.append(summary)
    # Keep last 100 runs
    logs = logs[-100:]
    log_path.write_text(json.dumps(logs, indent=2))

    return summary


def main():
    parser = argparse.ArgumentParser(description="BattleDebug Scheduled Runner")
    parser.add_argument("--calibration", action="store_true", help="Run calibration check")
    parser.add_argument("--stress", type=int, metavar="ROUNDS", help="Run stress test with N rounds")
    parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET, help="Experiment budget")

    args = parser.parse_args()

    if args.calibration:
        mode = "calibration"
        stress_rounds = 0
    elif args.stress:
        mode = "stress"
        stress_rounds = args.stress
    else:
        mode = "stress"
        stress_rounds = DEFAULT_STRESS_ROUNDS

    result = run_scheduled_session(
        mode=mode,
        budget=args.budget,
        stress_rounds=stress_rounds
    )

    print(json.dumps(result, indent=2))

    if result.get("status") == "error":
        sys.exit(1)


if __name__ == "__main__":
    main()
