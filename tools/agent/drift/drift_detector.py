#!/usr/bin/env python3
"""
Drift Detector - Layer 2 of the Combat Watchdog

Reads metrics_history.csv and detects statistical anomalies.
For each metric, computes mean and stddev over last 7 rows (excluding tonight).
If tonight's value is outside ±2σ, emits a drift finding.

Only runs if there are ≥7 historical rows; otherwise no-op.

Usage:
    from drift.drift_detector import DriftDetector

    detector = DriftDetector(drift_dir)
    findings = detector.detect(tonights_row)
"""

import csv
import math
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple


class DriftDetector:
    """
    Detects statistical drift in combat metrics over time.

    Compares tonight's metrics against a 7-day rolling baseline.
    Flags anything outside ±2 standard deviations.
    """

    # Minimum rows needed for meaningful statistics
    MIN_HISTORY_ROWS = 7

    # Metrics to track for drift (others are informational only)
    TRACKED_METRICS = [
        # Faction balance
        "faction_empire_win_rate",
        "faction_orcs_win_rate",
        "faction_dwarfs_win_rate",
        "faction_undead_win_rate",
        "faction_skaven_win_rate",
        "faction_chaos_win_rate",
        "faction_bretonnia_win_rate",
        # System health
        "flank_to_rear_ratio",
        "charge_impacts_per_battle",
        "avg_battle_duration",
        "pct_decisive",
        "routs_per_battle",
        "ai_plays_per_battle",
        "zero_casualty_battles",
    ]

    # Thresholds for σ multiplier (can be tuned)
    SIGMA_THRESHOLD = 2.0

    def __init__(self, drift_dir: Path, project_path: Path = None):
        """
        Initialize the detector.

        Args:
            drift_dir: Directory containing metrics_history.csv
            project_path: Git repo path for commit lookup
        """
        self.drift_dir = Path(drift_dir)
        self.project_path = project_path or self.drift_dir.parent.parent.parent
        self.csv_path = self.drift_dir / "metrics_history.csv"

    def detect(self, tonights_row: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        """
        Detect drift in tonight's metrics.

        Args:
            tonights_row: Tonight's metrics (if None, uses last row in CSV)

        Returns:
            List of drift findings in standard schema
        """
        history = self._load_history()

        if len(history) < self.MIN_HISTORY_ROWS:
            print(f"[DriftDetector] Only {len(history)} rows, need {self.MIN_HISTORY_ROWS}. Skipping.")
            return []

        # Split history vs tonight
        if tonights_row is None:
            tonights_row = history[-1]
            baseline_rows = history[:-1]
        else:
            baseline_rows = history

        # Take only last 7 for baseline (excluding tonight)
        baseline_rows = baseline_rows[-self.MIN_HISTORY_ROWS:]

        findings = []

        # Check each tracked metric
        for metric in self.TRACKED_METRICS:
            finding = self._check_metric(metric, tonights_row, baseline_rows)
            if finding:
                findings.append(finding)

        # Also check any unit_*_win_rate columns dynamically
        for key in tonights_row.keys():
            if key.startswith("unit_") and key.endswith("_win_rate"):
                if key not in self.TRACKED_METRICS:
                    finding = self._check_metric(key, tonights_row, baseline_rows)
                    if finding:
                        findings.append(finding)

        return findings

    def _load_history(self) -> List[Dict[str, Any]]:
        """Load all historical rows from CSV."""
        if not self.csv_path.exists():
            return []

        rows = []
        with open(self.csv_path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                converted = {}
                for k, v in row.items():
                    if v == '' or v == 'None' or v is None:
                        converted[k] = None
                    else:
                        try:
                            if '.' in str(v):
                                converted[k] = float(v)
                            else:
                                converted[k] = int(v)
                        except (ValueError, TypeError):
                            converted[k] = v
                rows.append(converted)

        return rows

    def _check_metric(
        self,
        metric: str,
        tonight: Dict[str, Any],
        baseline: List[Dict[str, Any]]
    ) -> Optional[Dict[str, Any]]:
        """
        Check a single metric for drift.

        Args:
            metric: Metric name
            tonight: Tonight's row
            baseline: Historical rows for baseline

        Returns:
            Finding dict if drift detected, None otherwise
        """
        # Get tonight's value
        tonight_val = tonight.get(metric)
        if tonight_val is None:
            return None

        try:
            tonight_val = float(tonight_val)
        except (TypeError, ValueError):
            return None

        # Get baseline values
        baseline_vals = []
        for row in baseline:
            val = row.get(metric)
            if val is not None:
                try:
                    baseline_vals.append(float(val))
                except (TypeError, ValueError):
                    pass

        if len(baseline_vals) < 3:
            # Not enough data for this metric
            return None

        # Compute mean and stddev
        mean = sum(baseline_vals) / len(baseline_vals)
        variance = sum((x - mean) ** 2 for x in baseline_vals) / len(baseline_vals)
        stddev = math.sqrt(variance)

        # Check for drift
        if stddev == 0:
            # No variance - only flag if tonight is different
            if tonight_val != mean:
                deviation = abs(tonight_val - mean)
                direction = "higher" if tonight_val > mean else "lower"
            else:
                return None
        else:
            z_score = (tonight_val - mean) / stddev
            if abs(z_score) < self.SIGMA_THRESHOLD:
                return None
            deviation = abs(z_score)
            direction = "higher" if z_score > 0 else "lower"

        # Find last stable date (when metric was within bounds)
        last_stable = self._find_last_stable(metric, baseline, mean, stddev)
        commits_since = self._get_commits_since(last_stable)

        # Determine severity
        if stddev > 0:
            if abs((tonight_val - mean) / stddev) > 3.0:
                severity = "critical"
            elif abs((tonight_val - mean) / stddev) > 2.5:
                severity = "high"
            else:
                severity = "medium"
        else:
            severity = "high"

        # Build finding
        return {
            "id": f"DRIFT-{metric}-{datetime.now().strftime('%Y%m%d')}",
            "source": "drift",
            "category": "drift",
            "severity": severity,
            "title": f"{metric} is {direction} than baseline ({tonight_val:.2f} vs {mean:.2f}±{stddev:.2f})",
            "evidence": {
                "metric": metric,
                "tonight_value": tonight_val,
                "baseline_mean": mean,
                "baseline_stddev": stddev,
                "z_score": (tonight_val - mean) / stddev if stddev > 0 else None,
                "direction": direction,
                "baseline_samples": len(baseline_vals),
            },
            "code_hints": self._get_code_hints(metric),
            "first_seen": datetime.now().strftime("%Y-%m-%d"),
            "git_context": {
                "last_stable_date": last_stable,
                "commits_since_stable": commits_since,
            }
        }

    def _find_last_stable(
        self,
        metric: str,
        baseline: List[Dict[str, Any]],
        mean: float,
        stddev: float
    ) -> Optional[str]:
        """Find the last date when this metric was within bounds."""
        for row in reversed(baseline):
            val = row.get(metric)
            if val is None:
                continue
            try:
                val = float(val)
            except (TypeError, ValueError):
                continue

            if stddev == 0 or abs((val - mean) / stddev) <= self.SIGMA_THRESHOLD:
                return row.get("timestamp", "unknown")[:10]  # Date only

        return None

    def _get_commits_since(self, since_date: Optional[str]) -> List[str]:
        """Get combat-related commits since a date."""
        if not since_date:
            return []

        try:
            result = subprocess.run(
                [
                    "git", "log",
                    f"--since={since_date}",
                    "--oneline",
                    "--",
                    "battle_system/",
                    "scenes/unit_zoo*",
                ],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                return [line for line in lines if line][:10]  # Max 10
        except Exception:
            pass

        return []

    def _get_code_hints(self, metric: str) -> List[str]:
        """Get code hints based on metric type."""
        hints = []

        if "faction" in metric and "win_rate" in metric:
            faction = metric.replace("faction_", "").replace("_win_rate", "")
            hints = [
                f"Check unit stats for {faction} faction in battle_system/data/regiments/",
                "Look for matchup multipliers in matchup_calculator.gd",
                "Verify faction-specific traits aren't double-applying",
            ]
        elif "unit" in metric and "win_rate" in metric:
            unit = metric.replace("unit_", "").replace("_win_rate", "")
            hints = [
                f"Check {unit}.tres for stat changes",
                "Compare to peer units in same tier",
                "Check for recent matchup table changes",
            ]
        elif metric == "flank_to_rear_ratio":
            hints = [
                "Check flanking_calculator.gd angle thresholds",
                "Verify _facing_direction is being set correctly",
                "Check unit rotation during combat",
            ]
        elif metric == "charge_impacts_per_battle":
            hints = [
                "Check charge_speed_distance threshold in combat_manager.gd",
                "Verify AI is issuing charge orders",
                "Check cavalry unit pool in test scenarios",
            ]
        elif metric == "avg_battle_duration":
            hints = [
                "Check damage scaling in melee_resolver.gd",
                "Verify morale damage rates in combat_manager.gd",
                "Check if rout thresholds changed",
            ]
        elif metric == "pct_decisive":
            hints = [
                "Check outcome classification logic",
                "Verify casualty thresholds for decisive victories",
            ]
        elif metric == "routs_per_battle":
            hints = [
                "Check morale_system.gd thresholds",
                "Verify MELEE_MORALE_PER_CASUALTY constant",
            ]
        elif metric == "ai_plays_per_battle":
            hints = [
                "Check GeneralAI tick rate",
                "Verify AI registration at battle start",
                "Check play evaluation hysteresis",
            ]
        elif metric == "zero_casualty_battles":
            hints = [
                "Check combat resolution is being called",
                "Verify units are actually engaging",
                "Check pathfinding to enemy units",
            ]

        return hints

    def get_baseline_summary(self) -> Dict[str, Any]:
        """Get summary of current baseline for debugging."""
        history = self._load_history()

        if len(history) < self.MIN_HISTORY_ROWS:
            return {"status": "insufficient_data", "rows": len(history)}

        baseline = history[-self.MIN_HISTORY_ROWS:]
        summary = {"status": "ready", "rows": len(baseline), "metrics": {}}

        for metric in self.TRACKED_METRICS:
            vals = [r.get(metric) for r in baseline if r.get(metric) is not None]
            if vals:
                try:
                    vals = [float(v) for v in vals]
                    mean = sum(vals) / len(vals)
                    variance = sum((x - mean) ** 2 for x in vals) / len(vals)
                    stddev = math.sqrt(variance)
                    summary["metrics"][metric] = {
                        "mean": mean,
                        "stddev": stddev,
                        "samples": len(vals),
                    }
                except (TypeError, ValueError):
                    pass

        return summary


def main():
    """Test the drift detector."""
    detector = DriftDetector(
        drift_dir=Path("C:/Users/caleb/BP_RTS_Dark_Shadows/tools/agent/drift"),
        project_path=Path("C:/Users/caleb/BP_RTS_Dark_Shadows")
    )

    # Check baseline status
    summary = detector.get_baseline_summary()
    print("Baseline summary:")
    print(f"  Status: {summary['status']}")
    print(f"  Rows: {summary.get('rows', 0)}")

    if summary['status'] == 'ready':
        print("\nMetric baselines:")
        for metric, stats in summary.get('metrics', {}).items():
            print(f"  {metric}: {stats['mean']:.3f} ± {stats['stddev']:.3f}")

    # Detect drift (will use latest row)
    findings = detector.detect()
    print(f"\nDrift findings: {len(findings)}")
    for f in findings:
        print(f"  [{f['severity'].upper()}] {f['title']}")


if __name__ == "__main__":
    main()
