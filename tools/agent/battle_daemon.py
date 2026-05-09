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

# Load .env file if present (for API key persistence)
def load_env_file():
    """Load environment variables from .env file in agent directory."""
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip().strip('"').strip("'")
                    os.environ.setdefault(key.strip(), value)

load_env_file()


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

# Unit Zoo stress test settings (must match unit_zoo_controller.gd exports)
# These are the ACTUAL values used by the Unit Zoo, not the daemon's parameters
UNIT_ZOO_STRESS_ROUNDS = 5
UNIT_ZOO_STRESS_DURATION = 60.0  # 1 min per battle (faster iteration)
UNIT_ZOO_TIMEOUT_BUFFER = 120  # Extra buffer for startup/shutdown

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

        # Use ACTUAL Unit Zoo settings for timeout, not daemon parameters
        # The Unit Zoo has its own hardcoded stress test settings
        timeout = int(UNIT_ZOO_STRESS_ROUNDS * UNIT_ZOO_STRESS_DURATION + UNIT_ZOO_TIMEOUT_BUFFER)
        self._log(f"Timeout set to {timeout}s based on Unit Zoo settings ({UNIT_ZOO_STRESS_ROUNDS} rounds x {UNIT_ZOO_STRESS_DURATION}s)")

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
        """
        Analyze stress test results for issues.

        Drop-in replacement for the original analyze_results. Same return shape
        (list of dicts) but with structured fields and 11 new checks.
        """
        findings = []

        # ------------------------------------------------------------------
        # SECTION 1: Original checks (preserved)
        # ------------------------------------------------------------------

        errors = results.get("errors", [])
        if errors:
            for error in errors[:5]:
                findings.append(self._mk_finding(
                    category="error",
                    severity="critical",
                    title=f"Error logged: {error.get('error', 'Unknown')}",
                    evidence={"round": error.get("round", "?"), "raw": str(error)[:200]},
                    code_hints=["Check the most recent file edit; errors usually trace to that"],
                ))

        # ------------------------------------------------------------------
        # SECTION 2: Sample-size sanity (NEW)
        # ------------------------------------------------------------------

        totals = results.get("totals", {})
        battles_run = totals.get("battles_run", 0)

        if battles_run < 10:
            findings.append(self._mk_finding(
                category="meta",
                severity="low",
                title=f"Sample size is small ({battles_run} battles)",
                evidence={"battles_run": battles_run},
                code_hints=["Consider --rounds 20+ for more reliable balance signals"],
            ))

        # If sample size is tiny, suppress balance-claim findings later
        sample_size_reliable = battles_run >= 10

        # ------------------------------------------------------------------
        # SECTION 3: Faction balance (UPGRADED — only emit if sample size is OK)
        # ------------------------------------------------------------------

        by_faction = results.get("by_faction", {})
        if sample_size_reliable:
            for faction, stats in by_faction.items():
                wins = stats.get("wins", 0)
                losses = stats.get("losses", 0)
                n = wins + losses
                if n < 4:
                    continue  # individual faction sample too small
                win_rate = wins / n if n > 0 else 0.5
                if win_rate > 0.80:
                    findings.append(self._mk_finding(
                        category="balance",
                        severity="high" if win_rate > 0.90 else "medium",
                        title=f"{faction} has {win_rate*100:.0f}% win rate ({wins}/{n})",
                        evidence={"faction": faction, "wins": wins, "losses": losses, "win_rate": win_rate},
                        code_hints=[
                            f"Check unit stats for {faction} faction in battle_system/data/regiments/",
                            "Look for matchup multipliers in matchup_calculator.gd",
                            "Verify faction-specific traits aren't double-applying",
                        ],
                    ))
                elif win_rate < 0.20:
                    findings.append(self._mk_finding(
                        category="balance",
                        severity="high" if win_rate < 0.10 else "medium",
                        title=f"{faction} only wins {win_rate*100:.0f}% ({wins}/{n})",
                        evidence={"faction": faction, "wins": wins, "losses": losses, "win_rate": win_rate},
                        code_hints=[
                            f"Check unit stats for {faction} faction",
                            "Cross-reference: do its units have lower base stats than peers?",
                        ],
                    ))

        # ------------------------------------------------------------------
        # SECTION 4: Per-battle event-level checks (NEW — the real upgrade)
        # ------------------------------------------------------------------

        battles = results.get("battles", [])

        # Aggregates rolled up across battles, used for system-wide sanity checks
        total_flank_events = 0
        total_rear_events = 0
        total_charge_impacts = 0
        total_routs_from_events = 0
        cavalry_battles = 0  # battles where at least one side had cavalry units
        cavalry_battles_with_charges = 0

        for battle in battles:
            events = battle.get("events", [])
            ai_plays = battle.get("ai_plays", [])
            battle_idx = battle.get("battle_idx", "?")
            duration = battle.get("duration_sec", 0.0)
            player_cas = battle.get("player_casualties", 0)
            enemy_cas = battle.get("enemy_casualties", 0)

            # Categorize events
            first_contacts = [e for e in events if e.get("type") == "first_contact"]
            charge_impacts = [e for e in events if e.get("type") == "charge_impact"]
            flank_events = [e for e in events if e.get("type") == "flank"]
            rear_events = [e for e in events if e.get("type") == "rear"]
            rout_events = [e for e in events if e.get("type") == "rout"]

            total_flank_events += len(flank_events)
            total_rear_events += len(rear_events)
            total_charge_impacts += len(charge_impacts)
            total_routs_from_events += len(rout_events)

            # === Check 4.1: Battles that ended too fast (UPGRADED — now event-aware) ===
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
                        "weather": battle.get("weather"),
                        "factions": f"{battle.get('player_faction')} vs {battle.get('enemy_faction')}",
                        "first_contact_t": first_contacts[0]["t"] if first_contacts else None,
                    },
                    code_hints=[
                        "Likely a one-shot kill or instant rout",
                        "Check melee_resolver.gd damage scaling at high charge bonuses",
                        "Check morale_system.gd for unbounded morale damage on first hit",
                    ],
                ))

            # === Check 4.2: Battles with zero casualties (UPGRADED — distinguish causes) ===
            if player_cas == 0 and enemy_cas == 0:
                if len(first_contacts) == 0:
                    # No contact happened — pathfinding or AI never engaged
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"Battle {battle_idx}: no contact ever made ({duration:.1f}s)",
                        evidence={
                            "battle_idx": battle_idx,
                            "duration_sec": duration,
                            "ai_plays_count": len(ai_plays),
                        },
                        code_hints=[
                            "Pathfinding may not be routing units to enemies",
                            "AI may not be issuing march/charge orders — check general_ai.gd",
                            "Deployment positions may be too far apart",
                        ],
                    ))
                else:
                    # Contact happened but no damage — combat math broken
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="critical",
                        title=f"Battle {battle_idx}: contact made but ZERO damage dealt",
                        evidence={
                            "battle_idx": battle_idx,
                            "duration_sec": duration,
                            "first_contact_t": first_contacts[0]["t"],
                            "charge_impacts": len(charge_impacts),
                        },
                        code_hints=[
                            "Combat resolution may be silently returning 0 casualties",
                            "Check melee_resolver.gd resolve_bidirectional_melee return path",
                            "Check _apply_difficulty_damage — multiplier might be 0",
                        ],
                    ))

            # === Check 4.3: Charge fired but defender took no follow-up damage ===
            # If charge_impact fired and defender was NOT braced, casualties should follow.
            # If they don't, the impact damage is being silently dropped.
            for ci in charge_impacts:
                if ci.get("braced"):
                    continue  # braced charges may legitimately deal no damage
                target = ci.get("target", "")
                ci_t = ci.get("t", 0.0)
                # Look for any rout/flank/rear of the target in next 1.5s
                # OR for a noticeable casualty pulse (we don't have per-event casualties,
                # so we use battle totals as a proxy)
                target_routed = any(
                    e for e in rout_events
                    if e.get("regiment") == target and e["t"] >= ci_t and e["t"] - ci_t < 5.0
                )
                target_in_flank = any(
                    e for e in flank_events + rear_events
                    if e.get("flanked") == target and e["t"] >= ci_t and e["t"] - ci_t < 1.5
                )
                # Only flag if there's BOTH no rout AND no flank in window
                # AND the battle had near-zero casualties to that side overall
                # (otherwise it's just one charge of many, can't tell)
                if not target_routed and not target_in_flank:
                    # Crude: if total casualties to target's side is <= 1, charge probably did nothing
                    # We don't know which side `target` is on without unit lookup, so use global heuristic
                    if (player_cas + enemy_cas) < len(charge_impacts) * 2:
                        findings.append(self._mk_finding(
                            category="bug",
                            severity="high",
                            title=f"Battle {battle_idx}: charge_impact fired but no measurable damage to {target}",
                            evidence={
                                "battle_idx": battle_idx,
                                "target": target,
                                "charge_impact_t": ci_t,
                                "total_charges_in_battle": len(charge_impacts),
                                "total_casualties": player_cas + enemy_cas,
                            },
                            code_hints=[
                                "combat_manager.gd begin_melee may be eating the impact",
                                "Check that impact_casualties is actually applied via take_casualties",
                                "Verify the defender wasn't somehow braced post-hoc",
                            ],
                        ))
                        break  # only flag once per battle to avoid spam

            # === Check 4.4: Routing in totals vs routing events ===
            # The unit_zoo controller tracks routs both via signal AND via the event stream.
            # If they disagree, signal wiring is broken somewhere.
            if "routing_count" in battle:  # if available
                signal_routs = battle.get("routing_count", 0)
                event_routs = len(rout_events)
                if abs(signal_routs - event_routs) > 1:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="medium",
                        title=f"Battle {battle_idx}: rout count desync (signal={signal_routs}, events={event_routs})",
                        evidence={
                            "battle_idx": battle_idx,
                            "signal_routs": signal_routs,
                            "event_routs": event_routs,
                        },
                        code_hints=[
                            "BattleSignals.regiment_routing may have multiple listeners getting different counts",
                            "Or _agent_battle_events may be cleared mid-battle",
                        ],
                    ))

            # === Check 4.5: AI play count sanity ===
            if len(ai_plays) == 0 and duration > 10.0:
                findings.append(self._mk_finding(
                    category="ai",
                    severity="medium",
                    title=f"Battle {battle_idx}: AI never picked any play in {duration:.1f}s",
                    evidence={
                        "battle_idx": battle_idx,
                        "duration_sec": duration,
                    },
                    code_hints=[
                        "GeneralAI may not be ticking — check _physics_process or _process",
                        "AI registration may have failed at battle start",
                        "Check battle_manager.gd _setup_enemy_general was called",
                    ],
                ))
            elif len(ai_plays) > 0 and duration > 5.0:
                plays_per_sec = len(ai_plays) / duration
                if plays_per_sec > 1.0:
                    # AI flip-flopping — hysteresis is broken
                    findings.append(self._mk_finding(
                        category="ai",
                        severity="medium",
                        title=f"Battle {battle_idx}: AI changed plays {len(ai_plays)} times in {duration:.1f}s",
                        evidence={
                            "battle_idx": battle_idx,
                            "ai_plays_count": len(ai_plays),
                            "plays_per_sec": plays_per_sec,
                            "play_sequence": [p.get("play") for p in ai_plays[:10]],
                        },
                        code_hints=[
                            "Hysteresis in general_ai.gd _evaluate_plays may be broken",
                            "Check that play scores aren't oscillating around the threshold",
                        ],
                    ))

            # === Check 4.6: Decisive loss with no routs (morale broken) ===
            outcome = battle.get("outcome", "")
            if "decisive" in outcome.lower() or "decisive" in str(outcome):
                if len(rout_events) == 0 and (player_cas > 50 or enemy_cas > 50):
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"Battle {battle_idx}: decisive outcome but no routs",
                        evidence={
                            "battle_idx": battle_idx,
                            "outcome": outcome,
                            "player_cas": player_cas,
                            "enemy_cas": enemy_cas,
                        },
                        code_hints=[
                            "Units are dying without routing — morale damage may be too low",
                            "MELEE_MORALE_PER_CASUALTY in combat_manager.gd may need raising",
                            "OR rout threshold may be too low",
                        ],
                    ))

            # Cavalry presence tracking for Check 5.3 below
            for unit_stat in battle.get("player_units", []) + battle.get("enemy_units", []):
                unit_id = unit_stat.get("unit_id", "")
                if any(c in unit_id.lower() for c in ["knight", "cav", "horse", "rider"]):
                    cavalry_battles += 1
                    if len(charge_impacts) > 0:
                        cavalry_battles_with_charges += 1
                    break  # count battle once

        # ------------------------------------------------------------------
        # SECTION 5: System-wide patterns (NEW)
        # ------------------------------------------------------------------

        if battles_run > 0:
            # === Check 5.1: Flanks happen at all? ===
            if total_flank_events == 0 and total_rear_events == 0 and battles_run >= 5:
                findings.append(self._mk_finding(
                    category="bug",
                    severity="critical",
                    title=f"NO flank or rear events across {battles_run} battles",
                    evidence={
                        "battles_run": battles_run,
                        "total_flank_events": 0,
                        "total_rear_events": 0,
                        "total_first_contacts": sum(
                            len([e for e in b.get("events", []) if e.get("type") == "first_contact"])
                            for b in battles
                        ),
                    },
                    code_hints=[
                        "Flanking detection is fundamentally broken",
                        "Check flanking_calculator.gd is_flank/is_rear thresholds",
                        "Check _facing_direction is being set on units (Phase 1 of flanking plan)",
                        "Likely the BattleSignals.unit_flanked is not being emitted",
                    ],
                ))

            # === Check 5.2: Flank/rear ratio sanity ===
            # In real combat, flanks should outnumber rears 2-3x (rears are harder to achieve)
            # If rears > flanks, facing math is inverted somewhere
            if total_flank_events + total_rear_events >= 10:
                if total_rear_events > total_flank_events * 1.2:
                    findings.append(self._mk_finding(
                        category="bug",
                        severity="high",
                        title=f"More rear hits ({total_rear_events}) than flank hits ({total_flank_events})",
                        evidence={
                            "total_flank_events": total_flank_events,
                            "total_rear_events": total_rear_events,
                            "ratio": total_rear_events / max(1, total_flank_events),
                        },
                        code_hints=[
                            "Facing math may be inverted — units appearing to face away when they shouldn't",
                            "Check _compute_initial_facing_from_deployment in regiment.gd",
                            "Verify deployment markers point the right direction on test maps",
                        ],
                    ))

            # === Check 5.3: Cavalry never charging ===
            if cavalry_battles >= 5 and cavalry_battles_with_charges < cavalry_battles * 0.5:
                findings.append(self._mk_finding(
                    category="ai",
                    severity="medium",
                    title=f"Cavalry rarely charges ({cavalry_battles_with_charges}/{cavalry_battles} cav-battles had impact)",
                    evidence={
                        "cavalry_battles": cavalry_battles,
                        "cavalry_battles_with_charges": cavalry_battles_with_charges,
                    },
                    code_hints=[
                        "AI may not be issuing charge orders for cavalry",
                        "PlayPinAndFlank or PlayAllOutAssault may not include charge ordering",
                        "Or charge_speed_distance threshold may be unreachable on these maps",
                    ],
                ))

        # ------------------------------------------------------------------
        # SECTION 6: Per-unit reliability (NEW)
        # ------------------------------------------------------------------

        # Track per-unit win/loss across battles to find unit-level balance bugs
        unit_outcomes: Dict[str, Dict[str, int]] = {}
        for battle in battles:
            outcome = battle.get("outcome", "")
            player_won = "player" in str(outcome).lower() and "win" in str(outcome).lower()
            enemy_won = "enemy" in str(outcome).lower() and "win" in str(outcome).lower()
            for unit_stat in battle.get("player_units", []):
                uid = unit_stat.get("unit_id", "")
                if not uid: continue
                unit_outcomes.setdefault(uid, {"wins": 0, "losses": 0})
                if player_won: unit_outcomes[uid]["wins"] += 1
                elif enemy_won: unit_outcomes[uid]["losses"] += 1
            for unit_stat in battle.get("enemy_units", []):
                uid = unit_stat.get("unit_id", "")
                if not uid: continue
                unit_outcomes.setdefault(uid, {"wins": 0, "losses": 0})
                if enemy_won: unit_outcomes[uid]["wins"] += 1
                elif player_won: unit_outcomes[uid]["losses"] += 1

        if sample_size_reliable:
            for unit_id, record in unit_outcomes.items():
                n = record["wins"] + record["losses"]
                if n < 5:
                    continue
                wr = record["wins"] / n
                if wr < 0.15 and record["losses"] >= 4:
                    findings.append(self._mk_finding(
                        category="balance",
                        severity="medium",
                        title=f"Unit '{unit_id}' lost {record['losses']}/{n} battles ({wr*100:.0f}% win rate)",
                        evidence={
                            "unit_id": unit_id,
                            "wins": record["wins"],
                            "losses": record["losses"],
                        },
                        code_hints=[
                            f"Check {unit_id}.tres for under-tuned stats",
                            f"Look for missing matchup bonus where {unit_id} should have one",
                        ],
                    ))

        # ------------------------------------------------------------------
        # Done
        # ------------------------------------------------------------------

        self._log(f"analyze_results: {len(findings)} findings across {battles_run} battles")

        # Sort by severity (critical first)
        sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
        findings.sort(key=lambda f: sev_order.get(f.get("severity", "low"), 99))

        return findings

    def _mk_finding(self, category: str, severity: str, title: str,
                    evidence: Dict, code_hints: List[str]) -> Dict:
        """
        Construct a structured finding dict.

        Standard schema, consumable by both findings_viewer.html and the
        Claude diagnose_with_claude prompt:

            category:   "bug" | "balance" | "ai" | "error" | "meta"
            severity:   "critical" | "high" | "medium" | "low"
            title:      short human-readable headline
            evidence:   dict of facts that support the finding
            code_hints: list of likely code paths to investigate
        """
        return {
            "category": category,
            "severity": severity,
            "title": title,
            "evidence": evidence,
            "code_hints": code_hints,
            # Backward-compat fields that the old daemon code expects:
            "type": category,
            "description": title,
            "context": " | ".join(f"{k}={v}" for k, v in list(evidence.items())[:3]),
        }

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
