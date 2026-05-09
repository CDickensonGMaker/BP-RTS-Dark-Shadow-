#!/usr/bin/env python3
"""
BattleDebug Agent Orchestrator

Manages the execution of experiments by:
1. Writing experiment specs to user://agent/spec.json
2. Launching Godot headless via MCP or subprocess
3. Waiting for completion/timeout
4. Reading results JSON and building digest

Usage:
    from agent_orchestrator import AgentOrchestrator

    orchestrator = AgentOrchestrator(project_path="C:/Users/caleb/BP_RTS_Dark_Shadows")

    spec = {
        "experiment_name": "spear_anti_cav_audit",
        "hypothesis": "Spear units lose anti-cav bonus when flanked",
        "battles": [
            {
                "label": "frontal_charge_baseline",
                "player": [{"unit": "halberd", "soldiers": 30}],
                "enemy": [{"unit": "reik", "soldiers": 15}],
                "duration_sec": 30.0,
                "repeats": 20
            }
        ]
    }

    digest = orchestrator.run_experiment(spec)
    print(digest)
"""

import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


class AgentOrchestrator:
    """Orchestrates experiment execution between agent and Godot."""

    # Default Godot executable path
    DEFAULT_GODOT = r"C:\Users\caleb\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"

    def __init__(
        self,
        project_path: str,
        godot_executable: str = None,
        user_data_path: Optional[str] = None,
        timeout_seconds: int = 600,  # 10 minutes default
    ):
        """
        Initialize the orchestrator.

        Args:
            project_path: Path to the Godot project directory
            godot_executable: Path or name of Godot executable
            user_data_path: Path to Godot user:// directory (auto-detected if None)
            timeout_seconds: Maximum time to wait for experiment completion
        """
        self.project_path = Path(project_path)
        self.godot_executable = godot_executable or self.DEFAULT_GODOT
        self.timeout_seconds = timeout_seconds

        # Auto-detect user data path if not provided
        if user_data_path:
            self.user_data_path = Path(user_data_path)
        else:
            self.user_data_path = self._detect_user_data_path()

        # Ensure agent directory exists
        self.agent_dir = self.user_data_path / "agent"
        self.agent_dir.mkdir(parents=True, exist_ok=True)

        self.spec_path = self.agent_dir / "spec.json"
        self.results_path = self.agent_dir / "results.json"

    def _detect_user_data_path(self) -> Path:
        """Detect the Godot user:// directory based on OS and project name."""
        # Read actual project name from project.godot (not directory name)
        project_name = self._get_project_name()

        if os.name == 'nt':  # Windows
            appdata = os.environ.get('APPDATA', '')
            return Path(appdata) / 'Godot' / 'app_userdata' / project_name
        elif os.name == 'posix':
            if os.uname().sysname == 'Darwin':  # macOS
                return Path.home() / 'Library' / 'Application Support' / 'Godot' / 'app_userdata' / project_name
            else:  # Linux
                return Path.home() / '.local' / 'share' / 'godot' / 'app_userdata' / project_name
        else:
            raise RuntimeError(f"Unsupported OS: {os.name}")

    def _get_project_name(self) -> str:
        """Read the project name from project.godot file."""
        project_godot = self.project_path / "project.godot"
        if project_godot.exists():
            try:
                with open(project_godot, 'r', encoding='utf-8') as f:
                    for line in f:
                        if line.startswith('config/name='):
                            # Extract name from: config/name="BP RTS Dark Shadows"
                            name = line.split('=', 1)[1].strip().strip('"')
                            return name
            except Exception:
                pass
        # Fallback to directory name
        return self.project_path.name

    def run_experiment(self, spec: Dict[str, Any]) -> Dict[str, Any]:
        """
        Run an experiment and return the digest.

        Args:
            spec: Experiment specification dictionary

        Returns:
            Digest dictionary with results summary
        """
        # Write spec to file
        self._write_spec(spec)

        # Clear any existing results
        if self.results_path.exists():
            self.results_path.unlink()

        # Run Godot headless
        start_time = time.time()
        success = self._run_godot()
        elapsed = time.time() - start_time

        if not success:
            return {
                "status": "error",
                "error": "Godot execution failed or timed out",
                "elapsed_seconds": elapsed,
                "experiment_name": spec.get("experiment_name", "unknown")
            }

        # Read results
        results = self._read_results()
        if results is None:
            return {
                "status": "error",
                "error": "Failed to read results file",
                "elapsed_seconds": elapsed,
                "experiment_name": spec.get("experiment_name", "unknown")
            }

        # Build digest
        digest = self._build_digest(spec, results, elapsed)
        return digest

    def _write_spec(self, spec: Dict[str, Any]) -> None:
        """Write experiment spec to file."""
        with open(self.spec_path, 'w', encoding='utf-8') as f:
            json.dump(spec, f, indent=2)
        print(f"[Orchestrator] Wrote spec to {self.spec_path}")

    def _run_godot(self) -> bool:
        """
        Run Godot headless and wait for completion.

        Uses the unit_zoo scene as the testing ground since it has
        all the infrastructure for spawning units and running battles.

        Returns:
            True if successful, False if failed or timed out
        """
        # Use unit_zoo scene - the established testing ground
        scene_path = "res://scenes/unit_zoo.tscn"
        cmd = [
            self.godot_executable,
            "--headless",
            "--path", str(self.project_path),
            scene_path
        ]

        print(f"[Orchestrator] Running: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_path),
                timeout=self.timeout_seconds,
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                print(f"[Orchestrator] Godot exited with code {result.returncode}")
                if result.stderr:
                    print(f"[Orchestrator] stderr: {result.stderr[:500]}")
                return False

            return True

        except subprocess.TimeoutExpired:
            print(f"[Orchestrator] Godot timed out after {self.timeout_seconds}s")
            return False
        except FileNotFoundError:
            print(f"[Orchestrator] Godot executable not found: {self.godot_executable}")
            return False
        except Exception as e:
            print(f"[Orchestrator] Error running Godot: {e}")
            return False

    def _read_results(self) -> Optional[Dict[str, Any]]:
        """Read results from file."""
        if not self.results_path.exists():
            print(f"[Orchestrator] Results file not found: {self.results_path}")
            return None

        try:
            with open(self.results_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"[Orchestrator] Failed to parse results JSON: {e}")
            return None

    def _build_digest(
        self,
        spec: Dict[str, Any],
        results: Dict[str, Any],
        elapsed: float
    ) -> Dict[str, Any]:
        """
        Build a digest from raw results.

        The digest is a summary suitable for agent consumption,
        containing key statistics without raw event data.
        """
        digest = {
            "status": "success",
            "experiment_name": spec.get("experiment_name", "unknown"),
            "hypothesis": spec.get("hypothesis", ""),
            "elapsed_seconds": elapsed,
            "started_at": results.get("started_at", ""),
            "completed_at": results.get("completed_at", ""),
            "battles": []
        }

        # Summarize each battle
        for battle in results.get("battles", []):
            agg = battle.get("aggregate", {})
            battle_digest = {
                "label": battle.get("label", "unknown"),
                "repeats": battle.get("repeats", 0),
                "player_wins": agg.get("player_wins", 0),
                "enemy_wins": agg.get("enemy_wins", 0),
                "draws": agg.get("draws", 0),
                "player_win_rate": agg.get("player_win_rate", 0.0),
                "enemy_win_rate": agg.get("enemy_win_rate", 0.0),
                "avg_player_casualties": agg.get("avg_player_casualties", 0.0),
                "avg_enemy_casualties": agg.get("avg_enemy_casualties", 0.0),
            }
            digest["battles"].append(battle_digest)

        return digest

    def run_scenario_file(self, scenario_path: Path) -> Dict[str, Any]:
        """
        Load a YAML scenario file and run it.

        Converts scenario YAML format to experiment spec format,
        runs the experiment, and returns digest + raw events.

        Args:
            scenario_path: Path to scenario YAML file

        Returns:
            Dictionary with digest and events
        """
        if not YAML_AVAILABLE:
            return {
                "status": "error",
                "error": "PyYAML not installed. Run: pip install pyyaml"
            }

        scenario_path = Path(scenario_path)
        if not scenario_path.exists():
            return {
                "status": "error",
                "error": f"Scenario file not found: {scenario_path}"
            }

        try:
            with open(scenario_path, 'r', encoding='utf-8') as f:
                scenario = yaml.safe_load(f)
        except yaml.YAMLError as e:
            return {
                "status": "error",
                "error": f"Failed to parse YAML: {e}"
            }

        # Convert scenario to experiment spec
        spec = self._scenario_to_spec(scenario)

        # Run the experiment
        digest = self.run_experiment(spec)

        # Add scenario metadata to digest
        digest["scenario_id"] = scenario.get("id", "unknown")
        digest["scenario_tags"] = scenario.get("tags", [])
        digest["expectations"] = scenario.get("expectations", [])
        digest["negative_expectations"] = scenario.get("negative_expectations", [])

        return digest

    def _scenario_to_spec(self, scenario: Dict[str, Any]) -> Dict[str, Any]:
        """Convert scenario YAML format to experiment spec format."""
        setup = scenario.get("setup", {})

        # Build player units list
        player_units = []
        for unit_def in setup.get("player", []):
            player_units.append({
                "unit": unit_def.get("unit", ""),
                "soldiers": unit_def.get("count", 20),
                "pos": unit_def.get("pos", []),
                "facing": unit_def.get("facing", [1, 0, 0]),
                "order": unit_def.get("order", "hold"),
                "target": unit_def.get("target", "")
            })

        # Build enemy units list
        enemy_units = []
        for unit_def in setup.get("enemy", []):
            enemy_units.append({
                "unit": unit_def.get("unit", ""),
                "soldiers": unit_def.get("count", 20),
                "pos": unit_def.get("pos", []),
                "facing": unit_def.get("facing", [-1, 0, 0]),
                "order": unit_def.get("order", "hold"),
                "target": unit_def.get("target", "")
            })

        # Build spec
        spec = {
            "experiment_name": scenario.get("id", "scenario_test"),
            "hypothesis": scenario.get("description", ""),
            "battles": [
                {
                    "label": scenario.get("id", "scenario_battle"),
                    "player": player_units,
                    "enemy": enemy_units,
                    "duration_sec": setup.get("duration_sec", 30.0),
                    "repeats": 1  # Scenarios run once by default
                }
            ]
        }

        return spec

    def run_stress_test(
        self,
        rounds: int = 10,
        duration: float = 60.0,
        units_per_side: int = 4
    ) -> Dict[str, Any]:
        """
        Run the existing stress test and return the latest run JSON.

        This uses the unit_zoo_controller stress test instead of the
        AgentTestRunner, for when you want random battles.
        """
        # Run the main scene with stress test parameters
        cmd = [
            self.godot_executable,
            "--headless",
            "--path", str(self.project_path),
            "res://scenes/unit_zoo.tscn"
        ]

        print(f"[Orchestrator] Running stress test: {rounds} rounds")

        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_path),
                timeout=rounds * duration + 120,  # Extra buffer
                capture_output=True,
                text=True
            )

            # Find the latest run JSON
            run_files = sorted(self.agent_dir.glob("run_*.json"), reverse=True)
            if run_files:
                latest = run_files[0]
                with open(latest, 'r', encoding='utf-8') as f:
                    return json.load(f)
            else:
                return {"status": "error", "error": "No run files found"}

        except Exception as e:
            return {"status": "error", "error": str(e)}


def main():
    """CLI entry point for testing."""
    import argparse

    parser = argparse.ArgumentParser(description="BattleDebug Agent Orchestrator")
    parser.add_argument(
        "--project", "-p",
        default=r"C:\Users\caleb\BP_RTS_Dark_Shadows",
        help="Path to Godot project"
    )
    parser.add_argument(
        "--godot", "-g",
        default="godot",
        help="Godot executable"
    )
    parser.add_argument(
        "--stress-test",
        action="store_true",
        help="Run stress test instead of experiment"
    )
    parser.add_argument(
        "--rounds", "-r",
        type=int,
        default=5,
        help="Number of stress test rounds"
    )

    args = parser.parse_args()

    orchestrator = AgentOrchestrator(
        project_path=args.project,
        godot_executable=args.godot
    )

    if args.stress_test:
        result = orchestrator.run_stress_test(rounds=args.rounds)
    else:
        # Example experiment spec
        spec = {
            "experiment_name": "test_experiment",
            "hypothesis": "Test hypothesis",
            "battles": [
                {
                    "label": "grtsword_vs_orcboyz",
                    "player": [{"unit": "grtsword", "soldiers": 30}],
                    "enemy": [{"unit": "orcboyz", "soldiers": 30}],
                    "duration_sec": 30.0,
                    "repeats": 5
                }
            ]
        }
        result = orchestrator.run_experiment(spec)

    print("\n" + "=" * 60)
    print("RESULT:")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
