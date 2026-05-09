#!/usr/bin/env python3
"""
Combat Watchdog - Unified Combat Testing System

Merges the daemon's population-scale vision with the referee's surgical assertions
and drift detection's historical memory. All writing into one schema, processed
by one aggregator, summarized into one document.

Three perception systems:
1. DRIFT DETECTOR - Catches "small problems that develop over time"
2. SNAPSHOT ANALYZER - Finds in-the-moment bugs from tonight's stress tests
3. SCENARIO REFEREE - Named regression checks with explicit expectations

Usage:
    # Default observe-only mode (SAFE)
    python combat_watchdog.py --hours 5

    # Quick 25-battle stress test
    python combat_watchdog.py --stress-only --battles 25

    # Run specific scenarios only
    python combat_watchdog.py --scenarios-only

    # Full run with shift order
    python combat_watchdog.py --order shift_orders/2026-05-08.md

Environment:
    ANTHROPIC_API_KEY - Optional, for LLM-proposed variants only
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Any, List, Optional

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "agent"))

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    print("Warning: PyYAML not installed. Run: pip install pyyaml")


# =============================================================================
# CONFIGURATION
# =============================================================================

GODOT_EXECUTABLE = r"C:\Users\caleb\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
DEFAULT_STRESS_BATTLES = 25
DEFAULT_BATTLE_DURATION = 60.0
DEFAULT_UNITS_PER_SIDE = 10


# =============================================================================
# IMPORTS (after path setup)
# =============================================================================

from agent_orchestrator import AgentOrchestrator
from checker.expectation_checker import ExpectationChecker
from fuzzer.variant_generator import VariantGenerator
from drift.metrics_historian import MetricsHistorian
from drift.drift_detector import DriftDetector
from briefing.aggregator import BriefingAggregator, RunStats, UnifiedFinding


class CombatWatchdog:
    """
    Unified combat testing system.

    Runs stress tests (daemon mode) and scenario tests (referee mode) in one session,
    writes all findings to one stream, produces one morning briefing.
    """

    # Unit pools by faction for stress tests
    UNIT_POOLS = {
        "empire": [
            "grtsword", "mcsword", "empsword", "halb", "nlnhlb", "peasant",
            "reik", "brdhrs", "xbow", "mercxbow", "mortar", "voleygun"
        ],
        "orcs": [
            "gob1", "ntgoblin", "orcboyz", "biguns", "blackorc", "fanatic",
            "wolfride", "boarboyz", "gobarch", "rocklob", "troll", "giant"
        ],
        "dwarfs": [
            "dwwar", "iron", "ironbrks", "dwslay", "dwxbow", "engr"
        ],
        "undead": [
            "vanheims", "graveguard", "graveknight", "gravearch"
        ],
        "skaven": [
            "clanrats", "stmverm", "ratslave", "eshin", "plagmonk",
            "warpfire", "ratogre"
        ]
    }

    def __init__(
        self,
        project_path: Path = PROJECT_ROOT,
        output_dir: Path = None,
        time_budget_hours: float = 5.0,
        verbose: bool = True
    ):
        """
        Initialize the watchdog.

        Args:
            project_path: Path to Godot project
            output_dir: Directory for output (briefings, findings, drift)
            time_budget_hours: Maximum runtime
            verbose: Print progress
        """
        self.project_path = Path(project_path)
        self.output_dir = output_dir or (self.project_path / "tools" / "agent")
        self.time_budget = timedelta(hours=time_budget_hours)
        self.verbose = verbose

        # Initialize components
        self.orchestrator = AgentOrchestrator(
            project_path=str(self.project_path),
            godot_executable=GODOT_EXECUTABLE,
            timeout_seconds=300
        )
        self.checker = ExpectationChecker()
        self.variant_generator = VariantGenerator(max_variants=50)
        self.historian = MetricsHistorian(
            output_dir=self.output_dir / "drift",
            project_path=self.project_path
        )
        self.drift_detector = DriftDetector(
            drift_dir=self.output_dir / "drift",
            project_path=self.project_path
        )
        self.aggregator = BriefingAggregator(
            output_dir=self.output_dir,
            findings_dir=self.output_dir / "findings"
        )

        # State
        self.start_time: Optional[datetime] = None
        self.commit_sha: str = ""
        self.difficulty_profile: str = "normal"

        # Results accumulators
        self.stress_results: Optional[Dict] = None
        self.scenario_results: List[Dict] = []
        self.all_battles: List[Dict] = []

        # Findings by layer
        self.snapshot_findings: List[Dict] = []
        self.regression_findings: List[Dict] = []
        self.drift_findings: List[Dict] = []

        # Errors
        self.errors: List[str] = []

    def _log(self, message: str) -> None:
        """Log a message if verbose."""
        if self.verbose:
            timestamp = datetime.now().strftime("%H:%M:%S")
            print(f"[{timestamp}] {message}")

    def _time_remaining(self) -> timedelta:
        """Calculate remaining time budget."""
        if not self.start_time:
            return self.time_budget
        elapsed = datetime.now() - self.start_time
        return max(timedelta(0), self.time_budget - elapsed)

    def _get_commit_sha(self) -> str:
        """Get current git commit."""
        try:
            result = subprocess.run(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass
        return "unknown"

    # =========================================================================
    # STRESS TESTING (Layer 3 input)
    # =========================================================================

    def run_stress_tests(
        self,
        num_battles: int = DEFAULT_STRESS_BATTLES,
        units_per_side: int = DEFAULT_UNITS_PER_SIDE,
        duration_sec: float = DEFAULT_BATTLE_DURATION
    ) -> Dict[str, Any]:
        """
        Run random stress battles.

        Args:
            num_battles: Number of battles to run
            units_per_side: Units per side per battle
            duration_sec: Duration per battle

        Returns:
            Combined results dict
        """
        import random

        self._log(f"Running {num_battles} stress battles ({units_per_side}v{units_per_side})")

        # Generate battle specs
        battles = []
        random.seed(42)  # Reproducible

        for i in range(num_battles):
            player_faction = random.choice(list(self.UNIT_POOLS.keys()))
            enemy_faction = random.choice(list(self.UNIT_POOLS.keys()))

            player_pool = self.UNIT_POOLS[player_faction]
            enemy_pool = self.UNIT_POOLS[enemy_faction]

            # Generate units
            player_units = []
            for j in range(min(3, len(player_pool))):
                unit_id = random.choice(player_pool)
                count = units_per_side // 3 + (1 if j == 0 else 0)
                player_units.append({
                    "unit": unit_id,
                    "soldiers": count,
                    "pos": [-20 + j * 5, 0, j * 3 - 3],
                    "facing": [1, 0, 0],
                    "order": random.choice(["charge", "hold", "march"])
                })

            enemy_units = []
            for j in range(min(3, len(enemy_pool))):
                unit_id = random.choice(enemy_pool)
                count = units_per_side // 3 + (1 if j == 0 else 0)
                enemy_units.append({
                    "unit": unit_id,
                    "soldiers": count,
                    "pos": [20 - j * 5, 0, j * 3 - 3],
                    "facing": [-1, 0, 0],
                    "order": random.choice(["hold", "march"])
                })

            battles.append({
                "label": f"stress_{i+1:02d}_{player_faction}_vs_{enemy_faction}",
                "player": player_units,
                "enemy": enemy_units,
                "duration_sec": duration_sec,
                "repeats": 1
            })

        # Create experiment spec
        spec = {
            "experiment_name": f"stress_test_{num_battles}_battles",
            "hypothesis": "Find edge cases in combat system",
            "battles": battles
        }

        # Run via orchestrator
        result = self.orchestrator.run_experiment(spec)

        if result.get("status") == "error":
            self.errors.append(f"Stress test failed: {result.get('error')}")
            return {}

        return result

    # =========================================================================
    # SNAPSHOT ANALYSIS (Layer 3)
    # =========================================================================

    def analyze_results(self, results: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Analyze stress test results for issues.

        This is the Layer 3 snapshot analyzer - 15+ checks running on tonight's results.
        Imported from battle_daemon.py's analyze_results logic.
        """
        findings = []

        totals = results.get("totals", {})
        battles = results.get("battles", [])
        battles_run = totals.get("battles_run", len(battles))

        sample_size_reliable = battles_run >= 10

        # ------------------------------------------------------------------
        # Check 1: Sample size sanity
        # ------------------------------------------------------------------
        if battles_run < 10:
            findings.append(self._mk_finding(
                category="meta",
                severity="low",
                title=f"Sample size is small ({battles_run} battles)",
                evidence={"battles_run": battles_run},
                code_hints=["Consider running more battles for reliable signals"],
            ))

        # ------------------------------------------------------------------
        # Check 2: Faction balance
        # ------------------------------------------------------------------
        by_faction = results.get("by_faction", {})
        if sample_size_reliable:
            for faction, stats in by_faction.items():
                wins = stats.get("wins", 0)
                losses = stats.get("losses", 0)
                n = wins + losses
                if n < 4:
                    continue
                win_rate = wins / n if n > 0 else 0.5
                if win_rate > 0.80:
                    findings.append(self._mk_finding(
                        category="balance",
                        severity="high" if win_rate > 0.90 else "medium",
                        title=f"{faction} has {win_rate*100:.0f}% win rate ({wins}/{n})",
                        evidence={"faction": faction, "wins": wins, "losses": losses, "win_rate": win_rate},
                        code_hints=[f"Check unit stats for {faction} faction"],
                    ))
                elif win_rate < 0.20:
                    findings.append(self._mk_finding(
                        category="balance",
                        severity="high" if win_rate < 0.10 else "medium",
                        title=f"{faction} only wins {win_rate*100:.0f}% ({wins}/{n})",
                        evidence={"faction": faction, "wins": wins, "losses": losses, "win_rate": win_rate},
                        code_hints=[f"Check unit stats for {faction} faction"],
                    ))

        # ------------------------------------------------------------------
        # Per-battle checks
        # ------------------------------------------------------------------
        total_flank = 0
        total_rear = 0
        total_charge_impacts = 0
        total_routs = 0

        for battle in battles:
            events = battle.get("events", [])
            ai_plays = battle.get("ai_plays", [])
            battle_idx = battle.get("battle_idx", battle.get("label", "?"))
            duration = battle.get("duration_sec", 0.0)
            player_cas = battle.get("player_casualties", 0)
            enemy_cas = battle.get("enemy_casualties", 0)

            # Count events
            first_contacts = [e for e in events if e.get("type") == "first_contact"]
            charge_impacts = [e for e in events if e.get("type") == "charge_impact"]
            flank_events = [e for e in events if e.get("type") == "flank"]
            rear_events = [e for e in events if e.get("type") == "rear"]
            rout_events = [e for e in events if e.get("type") == "rout"]

            total_flank += len(flank_events)
            total_rear += len(rear_events)
            total_charge_impacts += len(charge_impacts)
            total_routs += len(rout_events)

            # Check: Battle too fast
            if duration < 5.0 and (player_cas + enemy_cas) > 0:
                findings.append(self._mk_finding(
                    category="bug",
                    severity="high",
                    title=f"Battle {battle_idx} ended in {duration:.1f}s with casualties",
                    evidence={
                        "battle_idx": battle_idx,
                        "duration_sec": duration,
                        "player_casualties": player_cas,
                        "enemy_casualties": enemy_cas,
                    },
                    code_hints=["Check melee_resolver.gd damage scaling"],
                ))

            # Check: Zero casualties
            if player_cas == 0 and enemy_cas == 0:
                if len(first_contacts) == 0:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"Battle {battle_idx}: no contact ever made ({duration:.1f}s)",
                        evidence={"battle_idx": battle_idx, "duration_sec": duration},
                        code_hints=["Pathfinding may not be routing units to enemies"],
                    ))
                else:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="critical",
                        title=f"Battle {battle_idx}: contact made but ZERO damage dealt",
                        evidence={"battle_idx": battle_idx, "duration_sec": duration},
                        code_hints=["Combat resolution may be silently returning 0"],
                    ))

            # Check: Silent charges
            for ci in charge_impacts:
                if ci.get("braced"):
                    continue
                if (player_cas + enemy_cas) < len(charge_impacts) * 2:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"Battle {battle_idx}: charge_impact fired but no measurable damage",
                        evidence={
                            "battle_idx": battle_idx,
                            "total_charges": len(charge_impacts),
                            "total_casualties": player_cas + enemy_cas,
                        },
                        code_hints=["Check that impact_casualties is applied via take_casualties"],
                    ))
                    break

            # Check: AI flip-flopping
            if len(ai_plays) > 0 and duration > 5.0:
                plays_per_sec = len(ai_plays) / duration
                if plays_per_sec > 1.0:
                    findings.append(self._mk_finding(
                        category="ai",
                        severity="medium",
                        title=f"Battle {battle_idx}: AI changed plays {len(ai_plays)} times in {duration:.1f}s",
                        evidence={
                            "battle_idx": battle_idx,
                            "ai_plays_count": len(ai_plays),
                            "plays_per_sec": plays_per_sec,
                        },
                        code_hints=["Check hysteresis in general_ai.gd"],
                    ))

        # ------------------------------------------------------------------
        # System-wide checks
        # ------------------------------------------------------------------
        if battles_run >= 5:
            if total_flank == 0 and total_rear == 0:
                findings.append(self._mk_finding(
                    category="bug",
                    severity="critical",
                    title=f"NO flank or rear events across {battles_run} battles",
                    evidence={"battles_run": battles_run, "total_flank": 0, "total_rear": 0},
                    code_hints=["Flanking detection is broken"],
                ))

            if total_flank + total_rear >= 10:
                if total_rear > total_flank * 1.2:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"More rear hits ({total_rear}) than flanks ({total_flank})",
                        evidence={"total_flank": total_flank, "total_rear": total_rear},
                        code_hints=["Facing math may be inverted"],
                    ))

        # Sort by severity
        sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
        findings.sort(key=lambda f: sev_order.get(f.get("severity", "low"), 99))

        self._log(f"Snapshot analysis: {len(findings)} findings")
        return findings

    def _mk_finding(self, category: str, severity: str, title: str,
                    evidence: Dict, code_hints: List[str]) -> Dict:
        """Create a finding in standard schema."""
        return {
            "id": f"SNAP-{datetime.now().strftime('%Y%m%d%H%M%S')}-{hash(title) % 10000:04d}",
            "source": "snapshot",
            "category": category,
            "severity": severity,
            "title": title,
            "evidence": evidence,
            "code_hints": code_hints,
            "first_seen": datetime.now().strftime("%Y-%m-%d"),
        }

    # =========================================================================
    # SCENARIO TESTING (Layer 4)
    # =========================================================================

    def run_scenarios(self, scenarios_dir: Path = None) -> List[Dict[str, Any]]:
        """
        Run all scenario YAML files.

        Args:
            scenarios_dir: Directory containing scenario files

        Returns:
            List of scenario results
        """
        if not YAML_AVAILABLE:
            self._log("PyYAML not available, skipping scenarios")
            return []

        scenarios_dir = scenarios_dir or (self.output_dir / "scenarios")
        if not scenarios_dir.exists():
            self._log(f"Scenarios directory not found: {scenarios_dir}")
            return []

        results = []
        scenario_files = sorted(scenarios_dir.glob("*.yaml"))
        scenario_files = [f for f in scenario_files if not f.name.startswith("_")]

        self._log(f"Found {len(scenario_files)} scenarios to run")

        for scenario_path in scenario_files:
            if self._time_remaining() < timedelta(minutes=2):
                self._log("Time budget exhausted, stopping scenarios")
                break

            try:
                with open(scenario_path, 'r', encoding='utf-8') as f:
                    scenario = yaml.safe_load(f)

                scenario_id = scenario.get("id", scenario_path.stem)
                self._log(f"Running scenario: {scenario_id}")

                # Run base scenario
                digest = self.orchestrator.run_scenario_file(scenario_path)

                # Check expectations
                check_result = self.checker.check(scenario, digest)

                results.append({
                    "scenario_id": scenario_id,
                    "scenario_path": str(scenario_path),
                    "passed": check_result["passed"],
                    "passes": check_result["passes"],
                    "failures": check_result["failures"],
                    "events_seen": check_result["events_seen"],
                })

                # Extract regression findings from failures
                for failure in check_result.get("failures", []):
                    self.regression_findings.append({
                        "id": f"REG-{scenario_id}-{failure.get('expectation_id', 'unknown')}",
                        "source": "regression",
                        "category": "regression",
                        "severity": "high",
                        "title": failure.get("reason", "Expectation failed"),
                        "evidence": {
                            "scenario_id": scenario_id,
                            "expectation_id": failure.get("expectation_id"),
                            "type": failure.get("type"),
                            "near_misses": failure.get("near_misses", []),
                        },
                        "code_hints": [],
                        "first_seen": datetime.now().strftime("%Y-%m-%d"),
                    })

                # Run variants
                variants = self.variant_generator.generate_variants(scenario)
                for variant in variants[:10]:  # Limit variants per scenario
                    if self._time_remaining() < timedelta(minutes=1):
                        break

                    variant_result = self._run_variant(variant)
                    results.append(variant_result)

            except Exception as e:
                self.errors.append(f"Error running scenario {scenario_path}: {e}")

        self._log(f"Scenario testing complete: {len(results)} runs")
        return results

    def _run_variant(self, variant: Dict[str, Any]) -> Dict[str, Any]:
        """Run a single scenario variant."""
        spec = self.orchestrator._scenario_to_spec(variant)
        digest = self.orchestrator.run_experiment(spec)

        check_result = self.checker.check(variant, digest)

        return {
            "scenario_id": variant.get("id", "unknown"),
            "variant_id": variant.get("variant_id"),
            "passed": check_result["passed"],
            "passes": check_result["passes"],
            "failures": check_result["failures"],
            "events_seen": check_result["events_seen"],
        }

    # =========================================================================
    # MAIN RUN LOOP
    # =========================================================================

    def run(
        self,
        stress_battles: int = DEFAULT_STRESS_BATTLES,
        run_scenarios: bool = True,
        scenarios_only: bool = False,
        stress_only: bool = False
    ) -> str:
        """
        Execute the full watchdog run.

        Args:
            stress_battles: Number of stress test battles
            run_scenarios: Whether to run scenario tests
            scenarios_only: Only run scenarios (no stress tests)
            stress_only: Only run stress tests (no scenarios)

        Returns:
            Path to the generated briefing
        """
        self.start_time = datetime.now()
        self.commit_sha = self._get_commit_sha()

        self._log("=" * 60)
        self._log("COMBAT WATCHDOG - Starting")
        self._log("=" * 60)
        self._log(f"Time: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        self._log(f"Commit: {self.commit_sha}")
        self._log(f"Time budget: {self.time_budget}")
        self._log("")

        total_battles = 0
        scenarios_run = 0
        variants_run = 0

        # 1. Run stress tests
        if not scenarios_only:
            self._log("--- PHASE 1: Stress Testing ---")
            self.stress_results = self.run_stress_tests(num_battles=stress_battles)

            if self.stress_results:
                # Layer 3: Snapshot analysis
                self.snapshot_findings = self.analyze_results(self.stress_results)
                total_battles += stress_battles

        # 2. Run scenario tests
        if not stress_only and run_scenarios:
            self._log("")
            self._log("--- PHASE 2: Scenario Testing ---")
            self.scenario_results = self.run_scenarios()

            for result in self.scenario_results:
                if result.get("variant_id"):
                    variants_run += 1
                else:
                    scenarios_run += 1

        # 3. Record metrics to historian (Layer 1)
        self._log("")
        self._log("--- PHASE 3: Recording Metrics ---")

        combined_results = self._build_combined_results()
        if combined_results.get("battles"):
            self.historian.record_run(
                combined_results,
                difficulty_profile=self.difficulty_profile,
                commit_sha=self.commit_sha
            )
            self._log("Metrics recorded to history")

        # 4. Run drift detection (Layer 2)
        self._log("")
        self._log("--- PHASE 4: Drift Detection ---")

        self.drift_findings = self.drift_detector.detect()
        self._log(f"Drift detector: {len(self.drift_findings)} findings")

        # 5. Aggregate and write briefing (Layer 5)
        self._log("")
        self._log("--- PHASE 5: Generating Briefing ---")

        end_time = datetime.now()
        stats = RunStats(
            start_time=self.start_time,
            end_time=end_time,
            battles_run=total_battles + scenarios_run + variants_run,
            scenarios_run=scenarios_run,
            variants_run=variants_run,
            stress_battles=total_battles,
            commit_sha=self.commit_sha,
            difficulty_profile=self.difficulty_profile,
        )

        briefing_path = self.aggregator.aggregate_and_write(
            drift_findings=self.drift_findings,
            snapshot_findings=self.snapshot_findings,
            regression_findings=self.regression_findings,
            run_stats=stats
        )

        # Summary
        self._log("")
        self._log("=" * 60)
        self._log("COMBAT WATCHDOG - Complete")
        self._log("=" * 60)
        self._log(f"Duration: {end_time - self.start_time}")
        self._log(f"Stress battles: {total_battles}")
        self._log(f"Scenarios: {scenarios_run} + {variants_run} variants")
        self._log(f"Findings: {len(self.drift_findings)} drift, {len(self.snapshot_findings)} snapshot, {len(self.regression_findings)} regression")
        self._log(f"Briefing: {briefing_path}")

        if self.errors:
            self._log(f"Errors: {len(self.errors)}")
            for err in self.errors[:5]:
                self._log(f"  - {err}")

        return briefing_path

    def _build_combined_results(self) -> Dict[str, Any]:
        """Combine stress and scenario results for historian."""
        combined = {
            "totals": {},
            "by_faction": {},
            "battles": [],
        }

        # Add stress results
        if self.stress_results:
            combined["totals"] = self.stress_results.get("totals", {})
            combined["by_faction"] = self.stress_results.get("by_faction", {})
            combined["battles"].extend(self.stress_results.get("battles", []))

        # Add scenario results as battles
        for result in self.scenario_results:
            combined["battles"].append({
                "label": result.get("scenario_id"),
                "variant_id": result.get("variant_id"),
                "passed": result.get("passed"),
                "events": [],  # Simplified
            })

        if not combined["totals"].get("battles_run"):
            combined["totals"]["battles_run"] = len(combined["battles"])

        return combined


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Combat Watchdog - Unified Combat Testing System",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Quick 25-battle stress test
    python combat_watchdog.py --battles 25

    # Full overnight run
    python combat_watchdog.py --hours 5

    # Scenarios only
    python combat_watchdog.py --scenarios-only

    # Stress tests only
    python combat_watchdog.py --stress-only --battles 50
        """
    )

    parser.add_argument(
        "--project", "-p",
        default=str(PROJECT_ROOT),
        help="Path to Godot project"
    )
    parser.add_argument(
        "--hours",
        type=float,
        default=1.0,
        help="Time budget in hours"
    )
    parser.add_argument(
        "--battles", "-b",
        type=int,
        default=DEFAULT_STRESS_BATTLES,
        help="Number of stress test battles"
    )
    parser.add_argument(
        "--scenarios-only",
        action="store_true",
        help="Only run scenario tests"
    )
    parser.add_argument(
        "--stress-only",
        action="store_true",
        help="Only run stress tests"
    )
    parser.add_argument(
        "--no-scenarios",
        action="store_true",
        help="Skip scenario tests"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Reduce output"
    )

    args = parser.parse_args()

    watchdog = CombatWatchdog(
        project_path=Path(args.project),
        time_budget_hours=args.hours,
        verbose=not args.quiet
    )

    briefing_path = watchdog.run(
        stress_battles=args.battles,
        run_scenarios=not args.no_scenarios,
        scenarios_only=args.scenarios_only,
        stress_only=args.stress_only
    )

    print(f"\nBriefing saved to: {briefing_path}")
    return 0


if __name__ == "__main__":
    exit(main())
