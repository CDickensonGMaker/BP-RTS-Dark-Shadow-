#!/usr/bin/env python3
"""
Night Shift - Combat Referee Orchestrator

The overnight referee that:
1. Reads shift orders (focus areas, skip list, time budget)
2. Loads and runs scenarios from tools/agent/scenarios/
3. Generates variants and runs those too
4. Checks expectations against event logs
5. Produces morning briefing

IMPORTANT: This is OBSERVE-ONLY mode. It does NOT modify code.
For autonomous fix-and-apply mode, use battle_daemon.py instead.

Usage:
    python night_shift.py --order shift_orders/2026-05-08.md

    # Or with defaults:
    python night_shift.py

Cron example (run at 11:30 PM):
    30 23 * * * cd /path/to/project && python tools/agent/night_shift.py >> logs/night_shift.log 2>&1
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Any, List, Optional

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "agent"))

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    print("Warning: PyYAML not installed. Run: pip install pyyaml")

from agent_orchestrator import AgentOrchestrator
from checker.expectation_checker import ExpectationChecker
from fuzzer.variant_generator import VariantGenerator
from briefing.briefing_generator import BriefingGenerator, ShiftResults, ScenarioResult, Finding


class NightShift:
    """
    Night shift orchestrator for the Combat Referee.

    Runs scenarios, generates variants, checks expectations,
    and produces morning briefings. Observe-only - never modifies code.
    """

    def __init__(
        self,
        project_path: Path,
        scenarios_dir: Path = None,
        shift_order_path: Path = None,
        output_dir: Path = None,
        time_budget_hours: float = 5.0,
        llm_budget_dollars: float = 5.0
    ):
        """
        Initialize the night shift.

        Args:
            project_path: Path to Godot project
            scenarios_dir: Path to scenarios directory
            shift_order_path: Path to shift order markdown
            output_dir: Where to write briefings and findings
            time_budget_hours: Maximum runtime
            llm_budget_dollars: Maximum LLM spend
        """
        self.project_path = Path(project_path)
        self.scenarios_dir = scenarios_dir or (self.project_path / "tools" / "agent" / "scenarios")
        self.output_dir = output_dir or (self.project_path / "tools" / "agent")
        self.shift_order_path = shift_order_path
        self.time_budget = timedelta(hours=time_budget_hours)
        self.llm_budget = llm_budget_dollars

        # Initialize components
        self.orchestrator = AgentOrchestrator(project_path=str(self.project_path))
        self.checker = ExpectationChecker()
        self.variant_generator = VariantGenerator(max_variants=50)
        self.briefing_generator = BriefingGenerator()

        # State
        self.start_time: Optional[datetime] = None
        self.results: List[Dict[str, Any]] = []
        self.llm_calls: int = 0
        self.llm_cost: float = 0.0
        self.errors: List[str] = []

        # Shift order config
        self.focus_areas: List[str] = []
        self.skip_scenarios: List[str] = []
        self.skip_tags: List[str] = []

    def run(self) -> ShiftResults:
        """
        Execute the night shift.

        Returns:
            ShiftResults with aggregate results
        """
        self.start_time = datetime.now()
        print(f"[NightShift] Starting at {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"[NightShift] Time budget: {self.time_budget}")
        print(f"[NightShift] LLM budget: ${self.llm_budget:.2f}")

        # Load shift order if provided
        if self.shift_order_path:
            self._load_shift_order()

        # Discover scenarios
        scenarios = self._discover_scenarios()
        print(f"[NightShift] Found {len(scenarios)} scenarios")

        # Run scenarios
        scenarios_run = 0
        variants_run = 0

        for scenario_path in scenarios:
            # Check time budget
            if self._time_remaining() <= timedelta(minutes=5):
                print("[NightShift] Time budget nearly exhausted, stopping")
                break

            try:
                scenario = self._load_scenario(scenario_path)
                if scenario is None:
                    continue

                # Check if scenario should be skipped
                if self._should_skip(scenario):
                    print(f"[NightShift] Skipping {scenario.get('id', 'unknown')} (in skip list)")
                    continue

                print(f"\n[NightShift] Running: {scenario.get('id', 'unknown')}")

                # Run base scenario
                result = self._run_scenario(scenario)
                self.results.append(result)
                scenarios_run += 1

                # Generate and run variants
                variants = self.variant_generator.generate_variants(scenario)
                for variant in variants:
                    if self._time_remaining() <= timedelta(minutes=2):
                        break

                    variant_result = self._run_scenario(variant)
                    self.results.append(variant_result)
                    variants_run += 1

            except Exception as e:
                error_msg = f"Error running {scenario_path}: {e}"
                print(f"[NightShift] {error_msg}")
                self.errors.append(error_msg)

        # Generate briefing
        end_time = datetime.now()
        shift_results = self._aggregate_results(end_time, scenarios_run, variants_run)

        # Save briefing
        briefing_path = self.output_dir / "briefings" / f"{end_time.strftime('%Y-%m-%d')}.md"
        briefing_content = self.briefing_generator.generate(shift_results)
        self.briefing_generator.save(briefing_content, briefing_path)

        # Save intermediate results
        self._save_intermediate_results(end_time)

        print(f"\n[NightShift] Completed at {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"[NightShift] Duration: {end_time - self.start_time}")
        print(f"[NightShift] Scenarios: {scenarios_run}, Variants: {variants_run}")
        print(f"[NightShift] Passes: {shift_results.passes}, Failures: {shift_results.failures}")
        print(f"[NightShift] Briefing saved to: {briefing_path}")

        return shift_results

    def _load_shift_order(self) -> None:
        """Load and parse shift order markdown."""
        if not self.shift_order_path or not Path(self.shift_order_path).exists():
            return

        try:
            with open(self.shift_order_path, 'r', encoding='utf-8') as f:
                content = f.read()

            # Parse focus areas (lines starting with numbers after "## Focus areas")
            if "## Focus areas" in content:
                focus_section = content.split("## Focus areas")[1].split("##")[0]
                for line in focus_section.split('\n'):
                    line = line.strip()
                    if line and line[0].isdigit():
                        self.focus_areas.append(line)

            # Parse skip list
            if "## Skip" in content:
                skip_section = content.split("## Skip")[1].split("##")[0]
                for line in skip_section.split('\n'):
                    line = line.strip()
                    if line.startswith('-'):
                        skip_item = line[1:].strip()
                        if skip_item:
                            self.skip_scenarios.append(skip_item.lower())

            print(f"[NightShift] Loaded shift order: {len(self.focus_areas)} focus areas, {len(self.skip_scenarios)} skip items")

        except Exception as e:
            print(f"[NightShift] Warning: Failed to parse shift order: {e}")

    def _discover_scenarios(self) -> List[Path]:
        """Find all scenario YAML files."""
        if not self.scenarios_dir.exists():
            return []

        scenarios = []
        for f in self.scenarios_dir.glob("*.yaml"):
            if f.name.startswith("_"):  # Skip templates
                continue
            scenarios.append(f)

        return sorted(scenarios)

    def _load_scenario(self, path: Path) -> Optional[Dict[str, Any]]:
        """Load a scenario YAML file."""
        if not YAML_AVAILABLE:
            return None

        try:
            with open(path, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"[NightShift] Failed to load {path}: {e}")
            return None

    def _should_skip(self, scenario: Dict[str, Any]) -> bool:
        """Check if scenario should be skipped based on shift order."""
        scenario_id = scenario.get("id", "").lower()
        tags = [t.lower() for t in scenario.get("tags", [])]

        # Check against skip list
        for skip_item in self.skip_scenarios:
            if skip_item in scenario_id:
                return True
            if skip_item in tags:
                return True

        return False

    def _run_scenario(self, scenario: Dict[str, Any]) -> Dict[str, Any]:
        """Run a single scenario and check expectations."""
        scenario_id = scenario.get("id", "unknown")

        # Run via orchestrator
        digest = self.orchestrator.run_scenario_file(
            Path(self.scenarios_dir / f"{scenario_id}.yaml")
        ) if (self.scenarios_dir / f"{scenario_id}.yaml").exists() else self._run_inline_scenario(scenario)

        # Check expectations
        check_result = self.checker.check(scenario, digest)

        return {
            "scenario_id": scenario_id,
            "variant_id": scenario.get("variant_id"),
            "passed": check_result["passed"],
            "passes": check_result["passes"],
            "failures": check_result["failures"],
            "events_seen": check_result["events_seen"],
            "digest": digest
        }

    def _run_inline_scenario(self, scenario: Dict[str, Any]) -> Dict[str, Any]:
        """Run a scenario that doesn't have a file (e.g., generated variant)."""
        spec = self.orchestrator._scenario_to_spec(scenario)
        return self.orchestrator.run_experiment(spec)

    def _time_remaining(self) -> timedelta:
        """Calculate remaining time in budget."""
        if not self.start_time:
            return self.time_budget
        elapsed = datetime.now() - self.start_time
        return max(timedelta(0), self.time_budget - elapsed)

    def _aggregate_results(
        self,
        end_time: datetime,
        scenarios_run: int,
        variants_run: int
    ) -> ShiftResults:
        """Aggregate individual results into shift summary."""
        shift = ShiftResults(
            start_time=self.start_time,
            end_time=end_time,
            scenarios_run=scenarios_run,
            variants_run=variants_run,
            llm_calls=self.llm_calls,
            llm_cost=self.llm_cost,
            errors=self.errors
        )

        # Group results by base scenario
        by_scenario: Dict[str, List[Dict]] = {}
        for result in self.results:
            base_id = result["scenario_id"]
            if base_id not in by_scenario:
                by_scenario[base_id] = []
            by_scenario[base_id].append(result)

        # Classify each scenario
        for scenario_id, results in by_scenario.items():
            pass_count = sum(1 for r in results if r["passed"])
            fail_count = len(results) - pass_count
            all_failures = []
            for r in results:
                all_failures.extend(r.get("failures", []))

            scenario_result = ScenarioResult(
                scenario_id=scenario_id,
                passed=(fail_count == 0),
                variant_count=len(results),
                pass_count=pass_count,
                fail_count=fail_count,
                failures=all_failures[:5]  # Limit stored failures
            )

            if fail_count == 0:
                shift.passes += 1
                shift.holding_steady.append(scenario_result)
            else:
                shift.failures += 1
                scenario_result.is_regression = True
                shift.regressions.append(scenario_result)

        return shift

    def _save_intermediate_results(self, end_time: datetime) -> None:
        """Save raw results for debugging."""
        results_path = self.output_dir / "findings" / end_time.strftime("%Y-%m-%d") / "raw_results.json"
        results_path.parent.mkdir(parents=True, exist_ok=True)

        with open(results_path, 'w', encoding='utf-8') as f:
            json.dump({
                "start_time": self.start_time.isoformat(),
                "end_time": end_time.isoformat(),
                "results": self.results,
                "errors": self.errors
            }, f, indent=2, default=str)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Night Shift - Combat Referee (OBSERVE-ONLY)",
        epilog="For autonomous fix-and-apply mode, use battle_daemon.py instead."
    )
    parser.add_argument(
        "--project", "-p",
        default=str(PROJECT_ROOT),
        help="Path to Godot project"
    )
    parser.add_argument(
        "--order", "-o",
        help="Path to shift order markdown"
    )
    parser.add_argument(
        "--hours",
        type=float,
        default=5.0,
        help="Time budget in hours"
    )
    parser.add_argument(
        "--llm-budget",
        type=float,
        default=5.0,
        help="LLM budget in dollars"
    )

    args = parser.parse_args()

    shift = NightShift(
        project_path=args.project,
        shift_order_path=args.order,
        time_budget_hours=args.hours,
        llm_budget_dollars=args.llm_budget
    )

    results = shift.run()

    # Exit with error code if there were failures
    return 1 if results.failures > 0 else 0


if __name__ == "__main__":
    exit(main())
