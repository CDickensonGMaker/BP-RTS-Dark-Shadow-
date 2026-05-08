#!/usr/bin/env python3
"""
BattleDebug Agent Session Runner

Runs a hypothesis-experiment loop session with an LLM agent.
The agent forms hypotheses, designs experiments, interprets results,
and writes findings.

Usage:
    python run_session.py --budget 8 --focus balance
    python run_session.py --mode calibration
    python run_session.py --resume session_2026-05-07.json

Requires:
    - anthropic or openai package
    - agent_orchestrator.py in same directory
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List
import time

# Import the orchestrator
from agent_orchestrator import AgentOrchestrator


class BattleDebugSession:
    """Manages a BattleDebug agent session."""

    def __init__(
        self,
        project_path: str,
        budget: int = 8,
        focus: str = "general",
        godot_executable: str = "godot",
    ):
        """
        Initialize a session.

        Args:
            project_path: Path to Godot project
            budget: Maximum number of experiments to run
            focus: Focus area (general, balance, difficulty, ai, bugs)
            godot_executable: Path to Godot
        """
        self.project_path = Path(project_path)
        self.budget = budget
        self.focus = focus
        self.experiments_run = 0
        self.findings: List[Dict[str, Any]] = []
        self.session_log: List[Dict[str, Any]] = []

        self.orchestrator = AgentOrchestrator(
            project_path=project_path,
            godot_executable=godot_executable
        )

        # Paths
        self.findings_dir = self.orchestrator.agent_dir / "findings"
        self.findings_dir.mkdir(exist_ok=True)
        self.sessions_dir = self.orchestrator.agent_dir / "sessions"
        self.sessions_dir.mkdir(exist_ok=True)

        # Session file
        self.session_id = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.session_file = self.sessions_dir / f"session_{self.session_id}.json"

        # Load system prompt
        self.system_prompt = self._load_system_prompt()

    def _load_system_prompt(self) -> str:
        """Load the agent system prompt."""
        prompt_path = self.project_path / "tools" / "agent" / "battledebug_agent.md"
        if prompt_path.exists():
            return prompt_path.read_text(encoding='utf-8')
        return "You are a combat system investigator. Form hypotheses and run experiments."

    def load_recent_findings(self, days: int = 7) -> List[Dict[str, Any]]:
        """Load recent findings to avoid duplicates."""
        findings = []
        cutoff = datetime.now().timestamp() - (days * 24 * 60 * 60)

        for f in self.findings_dir.glob("*.json"):
            try:
                data = json.loads(f.read_text(encoding='utf-8'))
                if isinstance(data, list):
                    findings.extend(data)
                else:
                    findings.append(data)
            except Exception as e:
                print(f"Warning: Failed to load {f}: {e}")

        # Filter to recent
        recent = [f for f in findings if self._parse_finding_date(f) > cutoff]
        return recent

    def _parse_finding_date(self, finding: Dict) -> float:
        """Parse finding date to timestamp."""
        try:
            if 'created_at' in finding:
                return datetime.fromisoformat(finding['created_at'].replace('Z', '+00:00')).timestamp()
            if 'id' in finding:
                # Parse from ID: F-YYYY-MM-DD-NNN
                parts = finding['id'].split('-')
                if len(parts) >= 4:
                    date_str = f"{parts[1]}-{parts[2]}-{parts[3]}"
                    return datetime.strptime(date_str, "%Y-%m-%d").timestamp()
        except:
            pass
        return 0

    def load_recent_digests(self, count: int = 3) -> List[Dict[str, Any]]:
        """Load recent battle digests for context."""
        digests = []
        run_files = sorted(self.orchestrator.agent_dir.glob("run_*.json"), reverse=True)

        for f in run_files[:count]:
            try:
                data = json.loads(f.read_text(encoding='utf-8'))
                # Summarize - don't include full event data
                summary = {
                    "run_id": data.get("run_id"),
                    "totals": data.get("totals"),
                    "by_faction": data.get("by_faction"),
                    "battles_count": len(data.get("battles", [])),
                }
                digests.append(summary)
            except Exception as e:
                print(f"Warning: Failed to load {f}: {e}")

        return digests

    def run_experiment(self, spec: Dict[str, Any]) -> Dict[str, Any]:
        """Run an experiment and return the digest."""
        self.experiments_run += 1
        print(f"\n{'='*60}")
        print(f"[Session] Running experiment {self.experiments_run}/{self.budget}")
        print(f"[Session] Name: {spec.get('experiment_name', 'unnamed')}")
        print(f"[Session] Hypothesis: {spec.get('hypothesis', 'N/A')}")
        print('='*60)

        # Log the experiment
        self.session_log.append({
            "type": "experiment_started",
            "timestamp": datetime.now().isoformat(),
            "spec": spec
        })

        # Run via orchestrator
        result = self.orchestrator.run_experiment(spec)

        # Log the result
        self.session_log.append({
            "type": "experiment_completed",
            "timestamp": datetime.now().isoformat(),
            "result": result
        })

        self._save_session()
        return result

    def write_finding(self, finding: Dict[str, Any]) -> str:
        """Write a finding and return its ID."""
        # Generate ID
        date_str = datetime.now().strftime("%Y-%m-%d")
        existing_today = len([f for f in self.findings if f.get('id', '').startswith(f"F-{date_str}")])
        finding_id = f"F-{date_str}-{existing_today + 1:03d}"

        finding['id'] = finding_id
        finding['created_at'] = datetime.now().isoformat()
        finding['status'] = 'open'

        self.findings.append(finding)

        # Log
        self.session_log.append({
            "type": "finding_written",
            "timestamp": datetime.now().isoformat(),
            "finding_id": finding_id
        })

        # Save to file
        self._save_findings()
        self._save_session()

        print(f"\n[Session] Finding written: {finding_id}")
        print(f"[Session] Title: {finding.get('title', 'Untitled')}")
        print(f"[Session] Severity: {finding.get('severity', 'unknown')}")

        return finding_id

    def _save_findings(self) -> None:
        """Save findings to daily file."""
        date_str = datetime.now().strftime("%Y-%m-%d")
        findings_file = self.findings_dir / f"findings_{date_str}.json"

        # Load existing findings for today
        existing = []
        if findings_file.exists():
            try:
                existing = json.loads(findings_file.read_text(encoding='utf-8'))
            except:
                pass

        # Merge (avoid duplicates by ID)
        existing_ids = {f.get('id') for f in existing}
        for f in self.findings:
            if f.get('id') not in existing_ids:
                existing.append(f)

        findings_file.write_text(json.dumps(existing, indent=2), encoding='utf-8')

    def _save_session(self) -> None:
        """Save session state."""
        session_data = {
            "session_id": self.session_id,
            "budget": self.budget,
            "experiments_run": self.experiments_run,
            "focus": self.focus,
            "findings_count": len(self.findings),
            "log": self.session_log
        }
        self.session_file.write_text(json.dumps(session_data, indent=2), encoding='utf-8')

    def should_terminate(self) -> tuple[bool, str]:
        """Check if session should terminate."""
        if self.experiments_run >= self.budget:
            return True, "Budget exhausted"

        # Check for high-severity findings
        critical_findings = [f for f in self.findings if f.get('severity') in ['critical', 'high']]
        if critical_findings:
            return True, f"High-severity finding requires attention: {critical_findings[-1].get('id')}"

        # Check for consecutive low-confidence results (fishing)
        if len(self.session_log) >= 6:
            recent_experiments = [e for e in self.session_log[-6:] if e.get('type') == 'experiment_completed']
            if len(recent_experiments) >= 3:
                # If no findings written in last 3 experiments, might be fishing
                recent_findings = [e for e in self.session_log[-6:] if e.get('type') == 'finding_written']
                if not recent_findings:
                    return True, "No findings in recent experiments - consider new approach"

        return False, ""

    def generate_session_summary(self) -> str:
        """Generate a session summary."""
        summary = [
            f"# BattleDebug Session Summary",
            f"",
            f"**Session ID**: {self.session_id}",
            f"**Focus**: {self.focus}",
            f"**Experiments Run**: {self.experiments_run}/{self.budget}",
            f"**Findings Generated**: {len(self.findings)}",
            f"",
            "## Findings",
        ]

        for f in self.findings:
            summary.append(f"- [{f.get('severity', '?').upper()}] {f.get('id')}: {f.get('title', 'Untitled')}")

        summary.append("")
        summary.append("## Experiment Log")

        for entry in self.session_log:
            if entry.get('type') == 'experiment_completed':
                result = entry.get('result', {})
                summary.append(f"- {result.get('experiment_name', 'unknown')}: {result.get('status', 'unknown')}")

        return "\n".join(summary)


def run_calibration_session(session: BattleDebugSession) -> None:
    """Run a difficulty calibration session."""
    print("\n" + "="*60)
    print("DIFFICULTY CALIBRATION MODE")
    print("="*60)

    # Define calibration experiments
    difficulty_levels = ['easy', 'normal', 'hard', 'very_hard', 'iron_man']

    for level in difficulty_levels:
        if session.experiments_run >= session.budget:
            break

        spec = {
            "experiment_name": f"calibration_{level}",
            "hypothesis": f"Win rate at {level.upper()} matches calibration target",
            "difficulty": level,
            "battles": [
                {
                    "label": "mirror_infantry",
                    "player": [{"unit": "grtsword", "soldiers": 30}],
                    "enemy": [{"unit": "grtsword", "soldiers": 30}],
                    "duration_sec": 60.0,
                    "repeats": 20
                }
            ]
        }

        result = session.run_experiment(spec)

        # Check if calibration is off
        if result.get('status') == 'success':
            for battle in result.get('battles', []):
                win_rate = battle.get('player_win_rate', 0.5)
                # Check against calibration targets
                targets = {
                    'easy': (0.75, 0.95),
                    'normal': (0.45, 0.55),
                    'hard': (0.30, 0.45),
                    'very_hard': (0.18, 0.30),
                    'iron_man': (0.10, 0.22),
                }
                min_rate, max_rate = targets.get(level, (0.4, 0.6))
                if win_rate < min_rate or win_rate > max_rate:
                    session.write_finding({
                        "severity": "medium",
                        "category": "difficulty",
                        "title": f"{level.upper()} difficulty miscalibrated",
                        "summary": f"Win rate at {level.upper()} is {win_rate*100:.1f}%, expected {min_rate*100:.0f}%-{max_rate*100:.0f}%",
                        "evidence": {
                            "experiment": spec['experiment_name'],
                            "n_battles": battle.get('repeats', 0),
                            "key_stats": {
                                "actual_win_rate": win_rate,
                                "target_min": min_rate,
                                "target_max": max_rate
                            }
                        },
                        "hypothesis": f"Difficulty multipliers for {level.upper()} need adjustment",
                        "suggested_action": "Review difficulty_profile.gd multipliers",
                        "confidence": 0.85
                    })


def run_interactive_session(session: BattleDebugSession) -> None:
    """Run an interactive session (for manual hypothesis input)."""
    print("\n" + "="*60)
    print("INTERACTIVE MODE")
    print("Enter hypotheses and experiments manually")
    print("Commands: experiment, finding, status, quit")
    print("="*60)

    while True:
        should_stop, reason = session.should_terminate()
        if should_stop:
            print(f"\n[Session] Terminating: {reason}")
            break

        cmd = input("\n> ").strip().lower()

        if cmd == 'quit' or cmd == 'q':
            break
        elif cmd == 'status':
            print(f"Experiments: {session.experiments_run}/{session.budget}")
            print(f"Findings: {len(session.findings)}")
        elif cmd == 'experiment':
            print("Enter experiment spec as JSON (end with empty line):")
            lines = []
            while True:
                line = input()
                if not line:
                    break
                lines.append(line)
            try:
                spec = json.loads('\n'.join(lines))
                result = session.run_experiment(spec)
                print(json.dumps(result, indent=2))
            except json.JSONDecodeError as e:
                print(f"Invalid JSON: {e}")
        elif cmd == 'finding':
            print("Enter finding as JSON (end with empty line):")
            lines = []
            while True:
                line = input()
                if not line:
                    break
                lines.append(line)
            try:
                finding = json.loads('\n'.join(lines))
                finding_id = session.write_finding(finding)
                print(f"Created: {finding_id}")
            except json.JSONDecodeError as e:
                print(f"Invalid JSON: {e}")
        else:
            print("Unknown command. Use: experiment, finding, status, quit")

    # Print summary
    print("\n" + session.generate_session_summary())


def main():
    parser = argparse.ArgumentParser(
        description="BattleDebug Agent Session Runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_session.py --budget 8 --focus balance
  python run_session.py --mode calibration
  python run_session.py --mode interactive
        """
    )

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
        "--budget", "-b",
        type=int,
        default=8,
        help="Maximum experiments to run"
    )
    parser.add_argument(
        "--focus", "-f",
        choices=['general', 'balance', 'difficulty', 'ai', 'bugs'],
        default='general',
        help="Focus area for investigation"
    )
    parser.add_argument(
        "--mode", "-m",
        choices=['interactive', 'calibration', 'stress'],
        default='interactive',
        help="Session mode"
    )

    args = parser.parse_args()

    # Create session
    session = BattleDebugSession(
        project_path=args.project,
        budget=args.budget,
        focus=args.focus,
        godot_executable=args.godot
    )

    print(f"[Session] Starting session {session.session_id}")
    print(f"[Session] Project: {session.project_path}")
    print(f"[Session] Budget: {session.budget} experiments")
    print(f"[Session] Focus: {session.focus}")

    # Load context
    recent_findings = session.load_recent_findings()
    recent_digests = session.load_recent_digests()
    print(f"[Session] Loaded {len(recent_findings)} recent findings")
    print(f"[Session] Loaded {len(recent_digests)} recent digests")

    # Run based on mode
    if args.mode == 'calibration':
        run_calibration_session(session)
    elif args.mode == 'interactive':
        run_interactive_session(session)
    elif args.mode == 'stress':
        # Run a stress test and analyze
        print("[Session] Running stress test...")
        result = session.orchestrator.run_stress_test(
            rounds=10,
            duration=60.0,
            units_per_side=4
        )
        print(json.dumps(result.get('totals', {}), indent=2))

    # Save final state
    session._save_session()
    print(f"\n[Session] Session saved to: {session.session_file}")


if __name__ == "__main__":
    main()
