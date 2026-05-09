#!/usr/bin/env python3
"""
Run 25 Combat Tests (10v10)

Uses the Combat Watchdog to execute 25 stress battles with varied unit compositions.
Analyzes results, detects drift, and generates a morning briefing.

Usage:
    python run_25_battles.py
"""

import sys
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "agent"))

from combat_watchdog import CombatWatchdog


def main():
    print("=" * 60)
    print("COMBAT WATCHDOG - 25 Battle Stress Test")
    print("=" * 60)
    print()

    watchdog = CombatWatchdog(
        project_path=PROJECT_ROOT,
        time_budget_hours=1.0,  # 1 hour budget
        verbose=True
    )

    # Run 25 stress battles only (no scenario tests for speed)
    briefing_path = watchdog.run(
        stress_battles=25,
        run_scenarios=False,  # Skip scenarios for this quick test
        stress_only=True
    )

    print()
    print("=" * 60)
    print("TEST COMPLETE")
    print("=" * 60)
    print(f"Briefing: {briefing_path}")
    print()

    # Read and display the briefing
    try:
        with open(briefing_path, 'r', encoding='utf-8') as f:
            print(f.read())
    except Exception as e:
        print(f"Could not read briefing: {e}")

    return 0


if __name__ == "__main__":
    exit(main())
