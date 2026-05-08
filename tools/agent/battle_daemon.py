#!/usr/bin/env python3
"""
BattleDebug Daemon - Autonomous Game Testing and Fixing

An omnipotent daemon that runs overnight to:
1. Execute stress tests in Godot
2. Analyze results for issues
3. Call Claude API to diagnose and propose fixes
4. Apply fixes to the codebase
5. Re-run tests to verify
6. Repeat until morning or issues resolved

Usage:
    # Set your API key first (get from https://console.anthropic.com/)
    set ANTHROPIC_API_KEY=your-api-key-here

    # Run the daemon
    python battle_daemon.py --hours 8 --max-fixes 10

    # Dry run (analyze only, no fixes)
    python battle_daemon.py --dry-run --cycles 3

Requirements:
    pip install anthropic
"""

import anthropic
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any, List, Tuple


# =============================================================================
# CONFIGURATION
# =============================================================================

PROJECT_PATH = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows")
GODOT_EXECUTABLE = r"C:\Users\caleb\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
CLAUDE_MODEL = "claude-sonnet-4-20250514"  # Fast and capable

# Safety limits
MAX_FIXES_PER_SESSION = 20
MAX_LINES_CHANGED_PER_FIX = 50
BACKUP_BEFORE_FIX = True

# Paths
AGENT_DIR = PROJECT_PATH / "tools" / "agent"
DAEMON_LOG = AGENT_DIR / "daemon_log.json"
BACKUP_DIR = AGENT_DIR / "backups"
FIXES_DIR = AGENT_DIR / "fixes"


# =============================================================================
# DAEMON CLASS
# =============================================================================

class BattleDaemon:
    """Autonomous game testing and fixing daemon."""

    def __init__(
        self,
        project_path: Path = PROJECT_PATH,
        dry_run: bool = False,
        verbose: bool = True,
    ):
        self.project_path = project_path
        self.dry_run = dry_run
        self.verbose = verbose
        self.client: Optional[anthropic.Anthropic] = None

        # Session state
        self.session_start = datetime.now()
        self.cycles_run = 0
        self.fixes_applied = 0
        self.findings: List[Dict] = []
        self.log_entries: List[Dict] = []

        # Ensure directories exist
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        FIXES_DIR.mkdir(parents=True, exist_ok=True)

        # Initialize Claude client
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if api_key:
            self.client = anthropic.Anthropic(api_key=api_key)
            self._log("Claude API initialized")
        else:
            self._log("WARNING: No ANTHROPIC_API_KEY - will run in analysis-only mode")

    def _log(self, message: str, level: str = "info") -> None:
        """Log a message."""
        timestamp = datetime.now().isoformat()
        entry = {"timestamp": timestamp, "level": level, "message": message}
        self.log_entries.append(entry)

        if self.verbose:
            prefix = {"info": "[INFO]", "success": "[OK]", "warning": "[WARN]", "error": "[ERR]", "fix": "[FIX]"}.get(level, "[*]")
            print(f"[{timestamp[11:19]}] {prefix} {message}")

    def _save_log(self) -> None:
        """Save daemon log to file."""
        log_data = {
            "session_start": self.session_start.isoformat(),
            "cycles_run": self.cycles_run,
            "fixes_applied": self.fixes_applied,
            "findings_count": len(self.findings),
            "entries": self.log_entries[-500:]  # Keep last 500 entries
        }
        DAEMON_LOG.write_text(json.dumps(log_data, indent=2))

    # =========================================================================
    # GODOT INTERACTION
    # =========================================================================

    def run_stress_test(self, rounds: int = 10, duration: float = 60.0) -> Optional[Dict]:
        """Run Godot stress test and return results."""
        self._log(f"Running stress test: {rounds} rounds, {duration}s each")

        # Find user data path
        user_data = self._get_user_data_path()
        agent_dir = user_data / "agent"

        # Clear old results
        for f in agent_dir.glob("run_*.json"):
            f.unlink()

        # Run Godot headless
        cmd = [
            GODOT_EXECUTABLE,
            "--headless",
            "--path", str(self.project_path),
            "res://scenes/unit_zoo.tscn"
        ]

        timeout = int(rounds * duration + 120)  # Buffer time

        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_path),
                timeout=timeout,
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                self._log(f"Godot exited with code {result.returncode}", "warning")

            # Find the newest run file
            run_files = sorted(agent_dir.glob("run_*.json"), reverse=True)
            if run_files:
                data = json.loads(run_files[0].read_text())
                self._log(f"Stress test complete: {data.get('totals', {}).get('battles_run', 0)} battles")
                return data
            else:
                self._log("No results file generated", "error")
                return None

        except subprocess.TimeoutExpired:
            self._log(f"Stress test timed out after {timeout}s", "error")
            return None
        except Exception as e:
            self._log(f"Error running stress test: {e}", "error")
            return None

    def _get_user_data_path(self) -> Path:
        """Get Godot user:// directory path."""
        project_name = self.project_path.name
        if os.name == 'nt':
            appdata = os.environ.get('APPDATA', '')
            return Path(appdata) / 'Godot' / 'app_userdata' / project_name
        else:
            return Path.home() / '.local' / 'share' / 'godot' / 'app_userdata' / project_name

    # =========================================================================
    # ISSUE DETECTION
    # =========================================================================

    def analyze_results(self, results: Dict) -> List[Dict]:
        """Analyze stress test results for issues."""
        issues = []

        # Check for errors
        errors = results.get("errors", [])
        if errors:
            for error in errors[:5]:
                issues.append({
                    "type": "error",
                    "severity": "high",
                    "description": error.get("error", "Unknown error"),
                    "context": f"Round {error.get('round', '?')}"
                })

        # Check faction balance
        by_faction = results.get("by_faction", {})
        for faction, stats in by_faction.items():
            win_rate = stats.get("win_rate", 0.5)
            if win_rate > 0.75:
                issues.append({
                    "type": "balance",
                    "severity": "medium",
                    "description": f"{faction} has {win_rate*100:.0f}% win rate - overpowered",
                    "context": f"Wins: {stats.get('wins', 0)}, Losses: {stats.get('losses', 0)}"
                })
            elif win_rate < 0.25:
                issues.append({
                    "type": "balance",
                    "severity": "medium",
                    "description": f"{faction} has {win_rate*100:.0f}% win rate - underpowered",
                    "context": f"Wins: {stats.get('wins', 0)}, Losses: {stats.get('losses', 0)}"
                })

        # Check for anomalies in battles
        battles = results.get("battles", [])
        for battle in battles:
            # Very short battles might indicate one-shot kills or instant routs
            if battle.get("duration_sec", 60) < 5:
                issues.append({
                    "type": "bug",
                    "severity": "high",
                    "description": f"Battle {battle.get('battle_idx')} ended in {battle.get('duration_sec'):.1f}s - suspiciously fast",
                    "context": f"{battle.get('player_faction')} vs {battle.get('enemy_faction')}"
                })

            # Check for no casualties (units not fighting)
            if battle.get("player_casualties", 0) == 0 and battle.get("enemy_casualties", 0) == 0:
                issues.append({
                    "type": "bug",
                    "severity": "high",
                    "description": f"Battle {battle.get('battle_idx')} had zero casualties - units may not be fighting",
                    "context": f"Duration: {battle.get('duration_sec'):.1f}s"
                })

        self._log(f"Found {len(issues)} potential issues")
        return issues

    # =========================================================================
    # CLAUDE INTEGRATION
    # =========================================================================

    def diagnose_with_claude(self, issues: List[Dict], results: Dict) -> Optional[Dict]:
        """Ask Claude to diagnose issues and propose fixes."""
        if not self.client:
            self._log("Claude API not available - skipping diagnosis", "warning")
            return None

        if not issues:
            self._log("No issues to diagnose")
            return None

        # Build context
        issues_text = "\n".join([
            f"- [{i['severity'].upper()}] {i['type']}: {i['description']} ({i['context']})"
            for i in issues[:10]  # Limit to top 10
        ])

        totals = results.get("totals", {})
        summary = f"""
Stress Test Summary:
- Battles run: {totals.get('battles_run', 0)}
- Decisive battles: {totals.get('battles_decisive', 0)}
- Total routs: {totals.get('total_routs', 0)}
- Flank events: {totals.get('total_flank_events', 0)}
"""

        prompt = f"""You are analyzing combat system test results for a Total War-style RTS game in Godot.

{summary}

Issues Detected:
{issues_text}

Based on these issues, provide:
1. A diagnosis of the most likely root cause
2. The specific file(s) and function(s) likely responsible
3. A concrete code fix (if applicable)

Key files in the project:
- battle_system/systems/combat_manager.gd - Main combat orchestration
- battle_system/systems/combat/melee_resolver.gd - Melee damage calculations
- battle_system/ai/general/general_ai.gd - AI strategy
- scenes/unit_zoo_controller.gd - Test harness

Respond in JSON format:
{{
    "diagnosis": "Brief explanation of the root cause",
    "confidence": 0.0-1.0,
    "file_path": "path/to/file.gd",
    "function_name": "function_to_fix",
    "fix_description": "What the fix does",
    "code_before": "exact code to find",
    "code_after": "replacement code",
    "skip_fix": true/false (true if no code fix needed, just config/balance)
}}

If multiple fixes needed, return an array of these objects.
Only propose fixes you're confident about (>0.7).
"""

        try:
            self._log("Calling Claude for diagnosis...")
            response = self.client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=4096,
                messages=[{"role": "user", "content": prompt}]
            )

            # Extract JSON from response
            text = response.content[0].text

            # Try to parse JSON
            json_match = re.search(r'\{[\s\S]*\}|\[[\s\S]*\]', text)
            if json_match:
                fix_data = json.loads(json_match.group())
                self._log(f"Claude proposed fix with {fix_data.get('confidence', 0)*100:.0f}% confidence")
                return fix_data
            else:
                self._log("Could not parse Claude response as JSON", "warning")
                return None

        except Exception as e:
            self._log(f"Claude API error: {e}", "error")
            return None

    # =========================================================================
    # CODE MODIFICATION
    # =========================================================================

    def apply_fix(self, fix: Dict) -> bool:
        """Apply a code fix to the project."""
        if fix.get("skip_fix"):
            self._log(f"Fix marked as skip: {fix.get('fix_description', 'N/A')}")
            return False

        if fix.get("confidence", 0) < 0.7:
            self._log(f"Fix confidence too low ({fix.get('confidence', 0)*100:.0f}%) - skipping", "warning")
            return False

        file_path = self.project_path / fix.get("file_path", "")
        if not file_path.exists():
            self._log(f"File not found: {file_path}", "error")
            return False

        code_before = fix.get("code_before", "")
        code_after = fix.get("code_after", "")

        if not code_before or not code_after:
            self._log("Fix missing code_before or code_after", "error")
            return False

        # Read current file
        content = file_path.read_text(encoding='utf-8')

        # Check if the code exists
        if code_before not in content:
            self._log(f"Could not find code to replace in {file_path.name}", "warning")
            return False

        # Safety check: don't change too many lines
        before_lines = len(code_before.split('\n'))
        after_lines = len(code_after.split('\n'))
        if max(before_lines, after_lines) > MAX_LINES_CHANGED_PER_FIX:
            self._log(f"Fix too large ({max(before_lines, after_lines)} lines) - skipping", "warning")
            return False

        # Dry run check
        if self.dry_run:
            self._log(f"[DRY RUN] Would fix {file_path.name}: {fix.get('fix_description', 'N/A')}", "fix")
            return False

        # Backup the file
        if BACKUP_BEFORE_FIX:
            backup_name = f"{file_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{file_path.suffix}"
            backup_path = BACKUP_DIR / backup_name
            shutil.copy(file_path, backup_path)
            self._log(f"Backed up to {backup_name}")

        # Apply the fix
        new_content = content.replace(code_before, code_after, 1)
        file_path.write_text(new_content, encoding='utf-8')

        self.fixes_applied += 1
        self._log(f"Applied fix to {file_path.name}: {fix.get('fix_description', 'N/A')}", "fix")

        # Save fix record
        fix_record = {
            "timestamp": datetime.now().isoformat(),
            "file": str(file_path.relative_to(self.project_path)),
            "description": fix.get("fix_description"),
            "confidence": fix.get("confidence"),
            "code_before": code_before,
            "code_after": code_after
        }
        fix_file = FIXES_DIR / f"fix_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        fix_file.write_text(json.dumps(fix_record, indent=2))

        return True

    # =========================================================================
    # MAIN LOOP
    # =========================================================================

    def run(
        self,
        max_hours: float = 8.0,
        max_cycles: Optional[int] = None,
        stress_rounds: int = 10,
    ) -> None:
        """Run the daemon loop."""
        end_time = self.session_start + timedelta(hours=max_hours)

        self._log(f"BattleDaemon starting")
        self._log(f"   Project: {self.project_path}")
        self._log(f"   Max runtime: {max_hours} hours (until {end_time.strftime('%H:%M')})")
        self._log(f"   Dry run: {self.dry_run}")
        self._log(f"   Claude API: {'enabled' if self.client else 'disabled'}")

        try:
            while datetime.now() < end_time:
                if max_cycles and self.cycles_run >= max_cycles:
                    self._log(f"Reached max cycles ({max_cycles})")
                    break

                if self.fixes_applied >= MAX_FIXES_PER_SESSION:
                    self._log(f"Reached max fixes ({MAX_FIXES_PER_SESSION}) - stopping for safety")
                    break

                self.cycles_run += 1
                self._log(f"\n{'='*50}")
                self._log(f"CYCLE {self.cycles_run}")
                self._log(f"{'='*50}")

                # 1. Run stress test
                results = self.run_stress_test(rounds=stress_rounds)
                if not results:
                    self._log("Stress test failed - waiting 60s before retry")
                    time.sleep(60)
                    continue

                # 2. Analyze for issues
                issues = self.analyze_results(results)
                self.findings.extend(issues)

                if not issues:
                    self._log("No issues found - system healthy!", "success")
                    # Wait before next cycle
                    wait_time = 300  # 5 minutes
                    self._log(f"Waiting {wait_time}s before next cycle...")
                    time.sleep(wait_time)
                    continue

                # 3. Get Claude's diagnosis
                fix_proposal = self.diagnose_with_claude(issues, results)

                if fix_proposal:
                    # Handle array of fixes
                    fixes = fix_proposal if isinstance(fix_proposal, list) else [fix_proposal]

                    for fix in fixes:
                        if self.apply_fix(fix):
                            # 4. Verify fix by running quick test
                            self._log("Verifying fix with quick test...")
                            verify_results = self.run_stress_test(rounds=3, duration=30)

                            if verify_results:
                                verify_issues = self.analyze_results(verify_results)
                                if len(verify_issues) < len(issues):
                                    self._log("Fix appears to have helped!", "success")
                                else:
                                    self._log("Fix may not have resolved the issue", "warning")

                # Save state
                self._save_log()

                # Brief pause between cycles
                time.sleep(30)

        except KeyboardInterrupt:
            self._log("\nDaemon interrupted by user")
        except Exception as e:
            self._log(f"Daemon error: {e}", "error")
        finally:
            self._save_log()
            self._print_summary()

    def _print_summary(self) -> None:
        """Print session summary."""
        duration = datetime.now() - self.session_start

        print("\n" + "="*60)
        print("BATTLEDAEMON SESSION COMPLETE")
        print("="*60)
        print(f"Duration: {duration}")
        print(f"Cycles run: {self.cycles_run}")
        print(f"Issues found: {len(self.findings)}")
        print(f"Fixes applied: {self.fixes_applied}")
        print(f"Log saved to: {DAEMON_LOG}")
        if self.fixes_applied > 0:
            print(f"Backups in: {BACKUP_DIR}")
            print(f"Fix records in: {FIXES_DIR}")
        print("="*60)


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="BattleDebug Daemon - Autonomous game testing and fixing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Run for 8 hours overnight
    python battle_daemon.py --hours 8

    # Dry run (analyze only, don't apply fixes)
    python battle_daemon.py --dry-run --cycles 5

    # Quick test with 3 cycles
    python battle_daemon.py --cycles 3 --rounds 5

Environment:
    ANTHROPIC_API_KEY - Required for Claude-powered diagnosis and fixes
        """
    )

    parser.add_argument("--hours", type=float, default=8.0, help="Maximum runtime in hours")
    parser.add_argument("--cycles", type=int, help="Maximum number of test cycles")
    parser.add_argument("--rounds", type=int, default=10, help="Stress test rounds per cycle")
    parser.add_argument("--dry-run", action="store_true", help="Analyze only, don't apply fixes")
    parser.add_argument("--quiet", action="store_true", help="Reduce output verbosity")

    args = parser.parse_args()

    daemon = BattleDaemon(
        project_path=PROJECT_PATH,
        dry_run=args.dry_run,
        verbose=not args.quiet
    )

    daemon.run(
        max_hours=args.hours,
        max_cycles=args.cycles,
        stress_rounds=args.rounds
    )


if __name__ == "__main__":
    main()
