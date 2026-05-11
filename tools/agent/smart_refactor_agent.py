#!/usr/bin/env python3
"""
Smart Refactor Agent - AAA Game Designer + Senior Engineer

An intelligent agent that reads audit results and makes careful,
game-design-aware decisions about each change. Thinks like a
Total War veteran developer who understands:

- Battle system mechanics (morale, flanking, charges, formations)
- RTS performance requirements (60fps with 1000+ units)
- Signal-based architecture patterns
- The difference between "unused" and "reserved for future use"

For each potential change, the agent:
1. Analyzes the context and dependencies
2. Considers game design implications
3. Assesses risk of breaking existing functionality
4. Only applies changes it's confident about
5. Documents reasoning for human review

Usage:
    # Analyze and propose (no changes)
    python smart_refactor_agent.py --dry-run

    # Apply safe changes only
    python smart_refactor_agent.py --apply-safe

    # Full analysis with Claude reasoning
    python smart_refactor_agent.py --with-ai --hours 4
"""

import argparse
import json
import os
import re
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

# =============================================================================
# CONFIGURATION
# =============================================================================

PROJECT_PATH = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows")
AGENT_DIR = PROJECT_PATH / "tools" / "agent"
AUDIT_FILE = AGENT_DIR / "overnight_audit.json"
BACKUP_DIR = AGENT_DIR / "refactor_backups"
CHANGES_LOG = AGENT_DIR / "refactor_changes.json"

# Game design context - things the agent should understand
GAME_CONTEXT = """
This is a Total War-style RTS battle system in Godot 4.5+ called "Dark Shadows".

KEY SYSTEMS:
- Regiment-based combat (battalions of soldiers, not individual units)
- Morale system (wavering, shaken, broken, routing, rallying)
- Flanking and facing (8 directions, rear/flank damage bonuses)
- Charge mechanics (impact damage, momentum, bracing)
- Formation system (line, column, wedge, square, shield wall)
- Ranged combat with ammunition and reload times
- Artillery with firing states (IDLE, AIMING, RELOADING)
- AI General with strategic "plays" (pin and flank, all-out assault, etc.)
- Commander AI with behavior trees for individual regiments

ARCHITECTURE:
- Signal-based communication via BattleSignals autoload
- AIAutoload for spatial queries and AI coordination
- Regiment nodes with leader CharacterBody3D for movement
- SpriteFormation for billboarded soldier rendering (MultiMesh)
- ArtilleryFormation for 3D cannon models

CRITICAL CONSTRAINTS:
- Must maintain 60fps with 500+ soldiers on screen
- Signals may be connected in .tscn files (not visible in GDScript)
- Some functions are called dynamically via behavior trees
- "Unused" AI functions may be reserved for future plays
- Combat math is carefully tuned - don't change multipliers
"""

# =============================================================================
# DECISION ENGINE
# =============================================================================

class RefactorDecision:
    """Represents a decision about a potential refactor."""

    SAFE = "SAFE"           # Can apply automatically
    RISKY = "RISKY"         # Needs human review
    SKIP = "SKIP"           # Should not change
    APPLIED = "APPLIED"     # Already applied

    def __init__(self, finding: Dict):
        self.finding = finding
        self.verdict = self.SKIP
        self.confidence = 0.0
        self.reasoning = ""
        self.game_design_notes = ""
        self.dependencies_checked = []
        self.proposed_change = None
        self.applied = False


class SmartRefactorAgent:
    """Intelligent refactoring agent with game design awareness."""

    def __init__(self, project_path: Path = PROJECT_PATH):
        self.project_path = project_path
        self.decisions: List[RefactorDecision] = []
        self.changes_made: List[Dict] = []
        self.files_modified: set = set()

        # Load audit results
        self.audit_data = self._load_audit()

        # Build code index for dependency checking
        self.code_index = self._build_code_index()

        # Ensure backup directory exists
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    def log(self, msg: str, level: str = "info"):
        """Print log message."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        icons = {
            "info": "[*]", "ok": "[+]", "warn": "[!]",
            "skip": "[-]", "think": "[?]", "apply": "[>]"
        }
        print(f"[{timestamp}] {icons.get(level, '[*]')} {msg}")

    def _load_audit(self) -> Dict:
        """Load audit results."""
        if not AUDIT_FILE.exists():
            self.log("No audit file found - run code_auditor.py first", "warn")
            return {"findings": []}
        return json.loads(AUDIT_FILE.read_text())

    def _build_code_index(self) -> Dict:
        """Build index of all code for dependency checking."""
        index = {
            "functions": defaultdict(list),  # func_name -> [files that define it]
            "callers": defaultdict(set),      # func_name -> [files that call it]
            "signals": defaultdict(list),     # signal_name -> [files that define it]
            "emitters": defaultdict(set),     # signal_name -> [files that emit it]
            "connectors": defaultdict(set),   # signal_name -> [files that connect it]
            "file_contents": {},              # file_path -> content
        }

        self.log("Building code index for dependency analysis...")

        for gd_file in self.project_path.rglob("*.gd"):
            if ".import" in str(gd_file) or "__pycache__" in str(gd_file):
                continue

            try:
                content = gd_file.read_text(encoding='utf-8', errors='ignore')
                rel_path = str(gd_file.relative_to(self.project_path))
                index["file_contents"][rel_path] = content

                # Index function definitions
                for match in re.finditer(r'^func\s+(\w+)', content, re.MULTILINE):
                    index["functions"][match.group(1)].append(rel_path)

                # Index function calls
                for match in re.finditer(r'\.(\w+)\s*\(|(?<![.\w])(\w+)\s*\(', content):
                    func_name = match.group(1) or match.group(2)
                    if func_name:
                        index["callers"][func_name].add(rel_path)

                # Index signal definitions
                for match in re.finditer(r'^signal\s+(\w+)', content, re.MULTILINE):
                    index["signals"][match.group(1)].append(rel_path)

                # Index signal emits
                for match in re.finditer(r'(\w+)\.emit\(|emit_signal\(["\'](\w+)', content):
                    sig = match.group(1) or match.group(2)
                    if sig:
                        index["emitters"][sig].add(rel_path)

                # Index signal connects
                for match in re.finditer(r'(\w+)\.connect\(|connect\(["\'](\w+)', content):
                    sig = match.group(1) or match.group(2)
                    if sig:
                        index["connectors"][sig].add(rel_path)

            except Exception as e:
                pass

        # Also check .tscn files for signal connections
        for tscn_file in self.project_path.rglob("*.tscn"):
            try:
                content = tscn_file.read_text(encoding='utf-8', errors='ignore')
                # Look for signal connections in scene files
                for match in re.finditer(r'signal="(\w+)"', content):
                    index["connectors"][match.group(1)].add(str(tscn_file.relative_to(self.project_path)))
            except:
                pass

        self.log(f"Indexed {len(index['file_contents'])} files")
        return index

    # =========================================================================
    # DECISION MAKING
    # =========================================================================

    def analyze_finding(self, finding: Dict) -> RefactorDecision:
        """Analyze a finding and decide what to do."""
        decision = RefactorDecision(finding)
        category = finding.get("category", "")

        # Route to specific analyzer
        if category == "unused_function":
            self._analyze_unused_function(decision)
        elif category == "unused_signal":
            self._analyze_unused_signal(decision)
        elif category == "orphan_signal":
            self._analyze_orphan_signal(decision)
        elif category == "performance":
            self._analyze_performance(decision)
        elif category == "code_smell":
            self._analyze_code_smell(decision)
        elif category == "spaghetti":
            self._analyze_spaghetti(decision)
        elif category == "magic_numbers":
            self._analyze_magic_numbers(decision)
        elif category == "todo":
            self._analyze_todo(decision)
        else:
            decision.verdict = RefactorDecision.SKIP
            decision.reasoning = f"No analyzer for category: {category}"

        return decision

    def _analyze_unused_function(self, decision: RefactorDecision):
        """Analyze an unused function finding."""
        func_name = decision.finding.get("details", {}).get("function", "")
        file_path = decision.finding.get("file", "")

        # Check for dynamic calls that auditor might miss
        dynamic_call_patterns = [
            rf'call\s*\(\s*["\']?{func_name}',
            rf'Callable\s*\([^)]*["\']?{func_name}',
            rf'has_method\s*\(\s*["\']?{func_name}',
            rf'"{func_name}"',  # String reference
        ]

        found_dynamic = False
        for pattern in dynamic_call_patterns:
            for content in self.code_index["file_contents"].values():
                if re.search(pattern, content):
                    found_dynamic = True
                    break

        if found_dynamic:
            decision.verdict = RefactorDecision.SKIP
            decision.reasoning = f"Function '{func_name}' may be called dynamically"
            decision.game_design_notes = "Behavior trees and AI systems use string-based function calls"
            return

        # Check if it's a callback pattern (_on_*)
        if func_name.startswith("_on_"):
            # Check scene files for connections
            connected_in_scene = False
            for tscn_path, content in [(p, c) for p, c in self.code_index["file_contents"].items() if p.endswith(".tscn")]:
                if func_name in content:
                    connected_in_scene = True
                    break

            if connected_in_scene:
                decision.verdict = RefactorDecision.SKIP
                decision.reasoning = f"Callback '{func_name}' is connected in a scene file"
                return

        # Check if it's an AI-related function (reserved for future plays)
        ai_keywords = ["ai", "commander", "general", "play", "strategy", "tactic"]
        if any(kw in file_path.lower() or kw in func_name.lower() for kw in ai_keywords):
            decision.verdict = RefactorDecision.RISKY
            decision.reasoning = f"AI function '{func_name}' may be reserved for future strategies"
            decision.game_design_notes = "Total War AI uses many conditional plays - don't remove prematurely"
            return

        # Check if it's in a critical combat file
        critical_files = ["combat_manager", "melee_resolver", "regiment", "morale"]
        if any(cf in file_path.lower() for cf in critical_files):
            decision.verdict = RefactorDecision.RISKY
            decision.reasoning = f"Function in critical combat file - needs manual review"
            decision.game_design_notes = "Combat systems are interconnected - changes can cascade"
            return

        # Seems safe to flag for removal
        decision.verdict = RefactorDecision.RISKY  # Still risky, but flagged
        decision.confidence = 0.6
        decision.reasoning = f"Function '{func_name}' appears unused but should be verified"

    def _analyze_unused_signal(self, decision: RefactorDecision):
        """Analyze an unused signal finding."""
        signal_name = decision.finding.get("details", {}).get("signal", "")

        # Check scene files
        for path, content in self.code_index["file_contents"].items():
            if path.endswith(".tscn") and signal_name in content:
                decision.verdict = RefactorDecision.SKIP
                decision.reasoning = f"Signal '{signal_name}' is referenced in scene files"
                return

        # If truly unused, still mark as risky for review
        decision.verdict = RefactorDecision.RISKY
        decision.reasoning = f"Signal '{signal_name}' appears unused - verify before removing"

    def _analyze_orphan_signal(self, decision: RefactorDecision):
        """Analyze a signal that's emitted but not connected."""
        signal_name = decision.finding.get("details", {}).get("signal", "")

        # Some signals are intentionally emitted for debugging/logging
        debug_signals = ["debug", "log", "trace", "tick"]
        if any(ds in signal_name.lower() for ds in debug_signals):
            decision.verdict = RefactorDecision.SKIP
            decision.reasoning = f"Signal '{signal_name}' appears to be for debugging/monitoring"
            return

        # Check if connected in scene files
        for path in self.code_index["connectors"].get(signal_name, []):
            if ".tscn" in path:
                decision.verdict = RefactorDecision.SKIP
                decision.reasoning = f"Signal '{signal_name}' is connected in scene: {path}"
                return

        decision.verdict = RefactorDecision.RISKY
        decision.reasoning = f"Signal '{signal_name}' emitted but never connected - may need handler"
        decision.game_design_notes = "Could be a missing feature - check if gameplay requires this signal"

    def _analyze_performance(self, decision: RefactorDecision):
        """Analyze a performance finding."""
        title = decision.finding.get("title", "")
        file_path = decision.finding.get("file", "")
        in_process = decision.finding.get("details", {}).get("in_process", False)

        # size() == 0 -> is_empty() is always safe
        if "size()" in title:
            decision.verdict = RefactorDecision.SAFE
            decision.confidence = 0.95
            decision.reasoning = "Replacing size() == 0 with is_empty() is always safe and faster"
            decision.proposed_change = {
                "type": "regex_replace",
                "pattern": r"\.size\(\)\s*==\s*0",
                "replacement": ".is_empty()",
            }
            return

        # get_nodes_in_group in _process is risky
        if "get_nodes_in_group" in title and in_process:
            decision.verdict = RefactorDecision.RISKY
            decision.reasoning = "get_nodes_in_group() in _process should be cached in _ready()"
            decision.game_design_notes = "Critical for 60fps with many regiments - but requires careful refactor"
            return

        # Object duplication needs context
        if "duplication" in title.lower():
            decision.verdict = RefactorDecision.SKIP
            decision.reasoning = "Object duplication may be intentional - needs manual review"
            return

        decision.verdict = RefactorDecision.RISKY
        decision.reasoning = "Performance issue - needs context-aware fix"

    def _analyze_code_smell(self, decision: RefactorDecision):
        """Analyze a code smell finding."""
        title = decision.finding.get("title", "")

        # Debug prints are safe to remove (but maybe keep for now)
        if "print statement" in title.lower():
            decision.verdict = RefactorDecision.RISKY
            decision.reasoning = "Debug prints can be removed, but may be useful during development"
            return

        # Boolean comparisons are safe to fix
        if "boolean comparison" in title.lower():
            decision.verdict = RefactorDecision.SAFE
            decision.confidence = 0.9
            decision.reasoning = "Redundant boolean comparison - safe to simplify"
            return

        # Self-modifying assignments are safe
        if "self-modifying" in title.lower():
            decision.verdict = RefactorDecision.SAFE
            decision.confidence = 0.9
            decision.reasoning = "Can use compound assignment (+=) instead"
            return

        decision.verdict = RefactorDecision.RISKY
        decision.reasoning = "Code smell needs manual review"

    def _analyze_spaghetti(self, decision: RefactorDecision):
        """Analyze spaghetti code finding."""
        title = decision.finding.get("title", "")

        # Magic numbers are safe to extract to constants (but manual work)
        if "magic number" in title.lower():
            decision.verdict = RefactorDecision.RISKY
            decision.reasoning = "Magic numbers should become constants, but requires naming decisions"
            decision.game_design_notes = "Combat multipliers need descriptive names (FLANK_DAMAGE_BONUS, etc.)"
            return

        # Deep nesting, long functions need manual refactor
        decision.verdict = RefactorDecision.SKIP
        decision.reasoning = "Structural refactoring needs human design decisions"
        decision.game_design_notes = "Don't auto-refactor combat logic - could break tuning"

    def _analyze_magic_numbers(self, decision: RefactorDecision):
        """Analyze magic number findings."""
        decision.verdict = RefactorDecision.RISKY
        decision.reasoning = "Magic numbers should be named constants"
        decision.game_design_notes = "Combat values need game-design-appropriate names"

    def _analyze_todo(self, decision: RefactorDecision):
        """Analyze TODO/FIXME findings."""
        title = decision.finding.get("title", "")

        # Check if it's a "BUG FIX" documentation (not an actual bug)
        if "fix" in title.lower() and "bug" in title.lower():
            decision.verdict = RefactorDecision.SKIP
            decision.reasoning = "This is fix documentation, not an open bug"
            return

        # Actual TODOs need human attention
        decision.verdict = RefactorDecision.SKIP
        decision.reasoning = "TODOs require human decision-making"

    # =========================================================================
    # APPLYING CHANGES
    # =========================================================================

    def apply_safe_changes(self, dry_run: bool = True) -> List[Dict]:
        """Apply all SAFE changes."""
        applied = []

        for decision in self.decisions:
            if decision.verdict != RefactorDecision.SAFE:
                continue

            if decision.proposed_change is None:
                continue

            file_path = self.project_path / decision.finding.get("file", "")
            if not file_path.exists():
                continue

            change_type = decision.proposed_change.get("type", "")

            if change_type == "regex_replace":
                result = self._apply_regex_replace(
                    file_path,
                    decision.proposed_change.get("pattern", ""),
                    decision.proposed_change.get("replacement", ""),
                    dry_run
                )
                if result:
                    applied.append({
                        "file": str(file_path.relative_to(self.project_path)),
                        "change": decision.proposed_change,
                        "finding": decision.finding.get("title", ""),
                        "dry_run": dry_run,
                    })
                    decision.applied = True

        return applied

    def _apply_regex_replace(self, file_path: Path, pattern: str,
                              replacement: str, dry_run: bool) -> bool:
        """Apply a regex replacement to a file."""
        try:
            content = file_path.read_text(encoding='utf-8')
            new_content = re.sub(pattern, replacement, content)

            if content == new_content:
                return False  # No changes

            if dry_run:
                self.log(f"[DRY RUN] Would replace in {file_path.name}: {pattern} -> {replacement}", "apply")
            else:
                # Backup first
                backup_path = BACKUP_DIR / f"{file_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{file_path.suffix}"
                shutil.copy(file_path, backup_path)

                # Apply change
                file_path.write_text(new_content, encoding='utf-8')
                self.log(f"Applied change to {file_path.name}", "apply")
                self.files_modified.add(str(file_path))

            return True

        except Exception as e:
            self.log(f"Error applying change to {file_path}: {e}", "warn")
            return False

    # =========================================================================
    # MAIN RUN
    # =========================================================================

    def run(self, apply_safe: bool = False, dry_run: bool = True) -> Dict:
        """Run the smart refactor analysis."""
        self.log("="*60)
        self.log("SMART REFACTOR AGENT - Total War Game Designer Mode")
        self.log("="*60)

        findings = self.audit_data.get("findings", [])
        self.log(f"Analyzing {len(findings)} audit findings...")

        # Analyze each finding
        stats = defaultdict(int)
        for finding in findings:
            decision = self.analyze_finding(finding)
            self.decisions.append(decision)
            stats[decision.verdict] += 1

        self.log(f"\nAnalysis complete:")
        self.log(f"  SAFE to apply: {stats[RefactorDecision.SAFE]}")
        self.log(f"  RISKY (needs review): {stats[RefactorDecision.RISKY]}")
        self.log(f"  SKIP (leave alone): {stats[RefactorDecision.SKIP]}")

        # Apply safe changes if requested
        if apply_safe:
            self.log("\n" + "-"*60)
            self.log("Applying SAFE changes...")
            applied = self.apply_safe_changes(dry_run=dry_run)
            self.log(f"Applied {len(applied)} changes" + (" (dry run)" if dry_run else ""))

        # Generate report
        report = self._generate_report(stats)

        # Save report
        report_path = AGENT_DIR / "refactor_report.json"
        report_path.write_text(json.dumps(report, indent=2))
        self.log(f"\nReport saved to: {report_path}")

        return report

    def _generate_report(self, stats: Dict) -> Dict:
        """Generate detailed report."""
        report = {
            "generated_at": datetime.now().isoformat(),
            "summary": {
                "total_findings": len(self.decisions),
                "safe": stats[RefactorDecision.SAFE],
                "risky": stats[RefactorDecision.RISKY],
                "skip": stats[RefactorDecision.SKIP],
                "applied": sum(1 for d in self.decisions if d.applied),
            },
            "safe_changes": [],
            "risky_items": [],
            "game_design_notes": [],
        }

        for decision in self.decisions:
            item = {
                "title": decision.finding.get("title", ""),
                "file": decision.finding.get("file", ""),
                "verdict": decision.verdict,
                "reasoning": decision.reasoning,
                "confidence": decision.confidence,
            }

            if decision.verdict == RefactorDecision.SAFE:
                item["proposed_change"] = decision.proposed_change
                item["applied"] = decision.applied
                report["safe_changes"].append(item)
            elif decision.verdict == RefactorDecision.RISKY:
                report["risky_items"].append(item)

            if decision.game_design_notes:
                report["game_design_notes"].append({
                    "finding": decision.finding.get("title", ""),
                    "note": decision.game_design_notes,
                })

        return report

    def print_summary(self):
        """Print human-readable summary."""
        print("\n" + "="*70)
        print("SMART REFACTOR SUMMARY")
        print("="*70)

        safe = [d for d in self.decisions if d.verdict == RefactorDecision.SAFE]
        risky = [d for d in self.decisions if d.verdict == RefactorDecision.RISKY]

        print(f"\n[SAFE TO APPLY] ({len(safe)} items)")
        for d in safe[:10]:
            status = "[APPLIED]" if d.applied else "[PENDING]"
            print(f"  {status} {d.finding.get('title', '')[:60]}")
        if len(safe) > 10:
            print(f"  ... and {len(safe) - 10} more")

        print(f"\n[NEEDS REVIEW] ({len(risky)} items)")
        for d in risky[:10]:
            print(f"  [?] {d.finding.get('title', '')[:50]}")
            print(f"      Reason: {d.reasoning[:60]}")
            if d.game_design_notes:
                print(f"      Game Design: {d.game_design_notes[:50]}")
        if len(risky) > 10:
            print(f"  ... and {len(risky) - 10} more")

        print("\n" + "="*70)


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Smart Refactor Agent - Game-design-aware code cleanup",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--apply-safe", action="store_true",
                        help="Apply all SAFE changes")
    parser.add_argument("--dry-run", action="store_true", default=True,
                        help="Don't actually modify files (default)")
    parser.add_argument("--no-dry-run", action="store_true",
                        help="Actually apply changes (use with --apply-safe)")

    args = parser.parse_args()

    agent = SmartRefactorAgent()
    agent.run(
        apply_safe=args.apply_safe,
        dry_run=not args.no_dry_run
    )
    agent.print_summary()


if __name__ == "__main__":
    main()
