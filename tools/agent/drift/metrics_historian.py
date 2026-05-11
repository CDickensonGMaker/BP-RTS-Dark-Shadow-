#!/usr/bin/env python3
"""
Metrics Historian - Layer 1 of the Combat Watchdog

Appends one row to metrics_history.csv at the end of every nightly run.
Columns track per-faction win rates, per-unit win rates, system metrics.

Just appends. Nothing reads it tonight. Starts accumulating data.

Usage:
    from drift.metrics_historian import MetricsHistorian

    historian = MetricsHistorian(output_dir)
    historian.record_run(results, commit_sha, difficulty_profile)
"""

import csv
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional


class MetricsHistorian:
    """
    Records nightly run metrics to CSV for drift detection.

    CSV columns:
    - timestamp: ISO format
    - commit_sha: Current git commit
    - difficulty_profile: Normal, Easy, Hard, etc.
    - battles_run: Total battles executed
    - faction_* columns: Win rates per faction
    - unit_* columns: Win rates for units appearing ≥5 times
    - flank_count, rear_count: Flanking event totals
    - charge_impacts_per_battle: Average charge impacts
    - avg_battle_duration: Mean battle length in seconds
    - pct_decisive: Percentage of decisive outcomes
    - routs_per_battle: Average routs per battle
    - ai_plays_per_battle: Average AI plays per battle
    - zero_casualty_battles: Count of battles with 0 casualties
    """

    KNOWN_FACTIONS = ["empire", "orcs", "dwarfs", "undead", "skaven", "chaos", "bretonnia"]

    def __init__(self, output_dir: Path, project_path: Path = None):
        """
        Initialize the historian.

        Args:
            output_dir: Directory for metrics_history.csv
            project_path: Git repo path for commit lookup
        """
        self.output_dir = Path(output_dir)
        self.project_path = project_path or self.output_dir.parent.parent.parent
        self.csv_path = self.output_dir / "metrics_history.csv"

        # Ensure directory exists
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def record_run(
        self,
        results: Dict[str, Any],
        difficulty_profile: str = "normal",
        commit_sha: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Record a run's metrics to the CSV.

        Args:
            results: Raw results dict from stress test or combined run
            difficulty_profile: Current difficulty setting
            commit_sha: Git commit SHA (auto-detected if None)

        Returns:
            The row dict that was appended
        """
        # Get commit SHA
        if commit_sha is None:
            commit_sha = self._get_current_commit()

        # Extract metrics
        row = self._extract_metrics(results, commit_sha, difficulty_profile)

        # Append to CSV
        self._append_row(row)

        return row

    def _get_current_commit(self) -> str:
        """Get current git commit SHA."""
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

    def _extract_metrics(
        self,
        results: Dict[str, Any],
        commit_sha: str,
        difficulty_profile: str
    ) -> Dict[str, Any]:
        """Extract all metrics from results."""
        row = {
            "timestamp": datetime.now().isoformat(),
            "commit_sha": commit_sha,
            "difficulty_profile": difficulty_profile,
        }

        # Basic totals
        totals = results.get("totals", {})
        battles = results.get("battles", [])

        row["battles_run"] = totals.get("battles_run", len(battles))

        # Per-faction win rates
        by_faction = results.get("by_faction", {})
        for faction in self.KNOWN_FACTIONS:
            stats = by_faction.get(faction, {})
            wins = stats.get("wins", 0)
            losses = stats.get("losses", 0)
            total = wins + losses
            row[f"faction_{faction}_win_rate"] = wins / total if total > 0 else None
            row[f"faction_{faction}_games"] = total

        # Per-unit win rates (units appearing ≥5 times)
        unit_outcomes = self._compute_unit_outcomes(battles)
        for unit_id, record in unit_outcomes.items():
            total = record["wins"] + record["losses"]
            if total >= 5:
                row[f"unit_{unit_id}_win_rate"] = record["wins"] / total
                row[f"unit_{unit_id}_games"] = total

        # System metrics
        total_flank = 0
        total_rear = 0
        total_charge_impacts = 0
        total_routs = 0
        total_ai_plays = 0
        total_duration = 0.0
        decisive_count = 0
        zero_casualty_count = 0

        for battle in battles:
            events = battle.get("events", [])
            ai_plays = battle.get("ai_plays", [])
            duration = battle.get("duration_sec", 0.0)
            player_cas = battle.get("player_casualties", 0)
            enemy_cas = battle.get("enemy_casualties", 0)
            outcome = str(battle.get("outcome", ""))

            # Count events by type
            for e in events:
                etype = e.get("type", "")
                if etype == "flank":
                    total_flank += 1
                elif etype == "rear":
                    total_rear += 1
                elif etype == "charge_impact":
                    total_charge_impacts += 1
                elif etype == "rout":
                    total_routs += 1

            total_ai_plays += len(ai_plays)
            total_duration += duration

            if "decisive" in outcome.lower():
                decisive_count += 1

            if player_cas == 0 and enemy_cas == 0:
                zero_casualty_count += 1

        battles_run = row["battles_run"]
        if battles_run > 0:
            row["flank_count"] = total_flank
            row["rear_count"] = total_rear
            row["flank_to_rear_ratio"] = total_flank / max(1, total_rear)
            row["charge_impacts_per_battle"] = total_charge_impacts / battles_run
            row["avg_battle_duration"] = total_duration / battles_run
            row["pct_decisive"] = decisive_count / battles_run * 100
            row["routs_per_battle"] = total_routs / battles_run
            row["ai_plays_per_battle"] = total_ai_plays / battles_run
            row["zero_casualty_battles"] = zero_casualty_count
        else:
            row["flank_count"] = 0
            row["rear_count"] = 0
            row["flank_to_rear_ratio"] = None
            row["charge_impacts_per_battle"] = None
            row["avg_battle_duration"] = None
            row["pct_decisive"] = None
            row["routs_per_battle"] = None
            row["ai_plays_per_battle"] = None
            row["zero_casualty_battles"] = 0

        return row

    def _compute_unit_outcomes(self, battles: List[Dict]) -> Dict[str, Dict[str, int]]:
        """Compute per-unit win/loss records."""
        outcomes = {}

        for battle in battles:
            outcome_str = str(battle.get("outcome", ""))
            player_won = "player" in outcome_str.lower() and "win" in outcome_str.lower()
            enemy_won = "enemy" in outcome_str.lower() and "win" in outcome_str.lower()

            for unit_stat in battle.get("player_units", []):
                uid = unit_stat.get("unit_id", "")
                if not uid:
                    continue
                outcomes.setdefault(uid, {"wins": 0, "losses": 0})
                if player_won:
                    outcomes[uid]["wins"] += 1
                elif enemy_won:
                    outcomes[uid]["losses"] += 1

            for unit_stat in battle.get("enemy_units", []):
                uid = unit_stat.get("unit_id", "")
                if not uid:
                    continue
                outcomes.setdefault(uid, {"wins": 0, "losses": 0})
                if enemy_won:
                    outcomes[uid]["wins"] += 1
                elif player_won:
                    outcomes[uid]["losses"] += 1

        return outcomes

    def _append_row(self, row: Dict[str, Any]) -> None:
        """Append a row to the CSV file."""
        file_exists = self.csv_path.exists()

        # Get existing fieldnames or create new
        if file_exists:
            with open(self.csv_path, 'r', newline='', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                existing_fields = reader.fieldnames or []
        else:
            existing_fields = []

        # Merge fieldnames (preserve order, add new at end)
        all_fields = list(existing_fields)
        for key in row.keys():
            if key not in all_fields:
                all_fields.append(key)

        # If new fields were added, we need to rewrite the file
        if set(all_fields) != set(existing_fields) and file_exists:
            self._rewrite_with_new_fields(all_fields, row)
        else:
            # Simple append
            with open(self.csv_path, 'a', newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=all_fields)
                if not file_exists:
                    writer.writeheader()
                writer.writerow(row)

        print(f"[MetricsHistorian] Appended row to {self.csv_path}")

    def _rewrite_with_new_fields(self, all_fields: List[str], new_row: Dict[str, Any]) -> None:
        """Rewrite CSV with expanded field set."""
        # Read existing rows
        rows = []
        with open(self.csv_path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for r in reader:
                rows.append(r)

        # Rewrite with all fields
        with open(self.csv_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=all_fields)
            writer.writeheader()
            for r in rows:
                writer.writerow(r)
            writer.writerow(new_row)

    def get_history(self, last_n: int = None) -> List[Dict[str, Any]]:
        """
        Read historical rows from CSV.

        Args:
            last_n: Only return last N rows (None = all)

        Returns:
            List of row dicts
        """
        if not self.csv_path.exists():
            return []

        rows = []
        with open(self.csv_path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Convert numeric strings back to numbers
                converted = {}
                for k, v in row.items():
                    if v == '' or v == 'None':
                        converted[k] = None
                    elif v is not None:
                        try:
                            if '.' in v:
                                converted[k] = float(v)
                            else:
                                converted[k] = int(v)
                        except (ValueError, TypeError):
                            converted[k] = v
                    else:
                        converted[k] = v
                rows.append(converted)

        if last_n is not None:
            return rows[-last_n:]
        return rows


def main():
    """Test the historian."""
    from pathlib import Path

    # Create test data
    test_results = {
        "totals": {"battles_run": 25},
        "by_faction": {
            "empire": {"wins": 8, "losses": 5},
            "orcs": {"wins": 5, "losses": 8},
        },
        "battles": [
            {
                "events": [
                    {"type": "flank", "t": 1.0},
                    {"type": "charge_impact", "t": 2.0},
                ],
                "ai_plays": [{"play": "assault"}],
                "duration_sec": 45.0,
                "player_casualties": 10,
                "enemy_casualties": 15,
                "outcome": "player_victory",
                "player_units": [{"unit_id": "grtsword"}],
                "enemy_units": [{"unit_id": "orcboyz"}],
            }
        ] * 25  # Duplicate for testing
    }

    historian = MetricsHistorian(
        output_dir=Path("C:/Users/caleb/BP_RTS_Dark_Shadows/tools/agent/drift"),
        project_path=Path("C:/Users/caleb/BP_RTS_Dark_Shadows")
    )

    row = historian.record_run(test_results, difficulty_profile="normal")
    print("Recorded row:")
    for k, v in sorted(row.items()):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
