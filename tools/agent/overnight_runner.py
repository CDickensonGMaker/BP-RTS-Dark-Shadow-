#!/usr/bin/env python3
"""
Overnight Runner - Complete overnight analysis suite

Runs both the code auditor and battle daemon overnight, then generates
a comprehensive morning report with:
1. Code health analysis (unused code, spaghetti, performance)
2. Battle test results (if enabled)
3. Prioritized cleanup/fix plan

Usage:
    # Run overnight (8 hours) - code audit only
    python overnight_runner.py --hours 8

    # Run with battle tests
    python overnight_runner.py --hours 8 --with-battles

    # Quick test run
    python overnight_runner.py --hours 0.5 --quick
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Import our auditors
sys.path.insert(0, str(Path(__file__).parent))
from code_auditor import CodeAuditor, PROJECT_PATH, AGENT_DIR

# =============================================================================
# OVERNIGHT RUNNER
# =============================================================================

class OvernightRunner:
    """Runs comprehensive overnight analysis."""

    def __init__(self, project_path: Path = PROJECT_PATH):
        self.project_path = project_path
        self.start_time = datetime.now()
        self.results = {
            "start_time": self.start_time.isoformat(),
            "end_time": None,
            "code_audit": None,
            "battle_tests": None,
            "morning_plan": None,
        }

    def log(self, msg: str, level: str = "info"):
        """Print log message."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        prefix = {"info": "[*]", "warn": "[!]", "error": "[X]", "ok": "[+]", "plan": "[>]"}.get(level, "[*]")
        print(f"[{timestamp}] {prefix} {msg}")

    def run_code_audit(self) -> dict:
        """Run comprehensive code audit."""
        self.log("="*60)
        self.log("PHASE 1: CODE AUDIT")
        self.log("="*60)

        auditor = CodeAuditor(self.project_path)
        report = auditor.run()

        self.results["code_audit"] = {
            "total_findings": len(report["findings"]),
            "summary": report["summary"],
            "cleanup_plan": report["proposed_cleanup"],
            "top_issues": self._get_top_issues(report["findings"]),
        }

        return report

    def _get_top_issues(self, findings: list, limit: int = 20) -> list:
        """Get top issues by severity."""
        severity_order = {"high": 0, "medium": 1, "low": 2}
        sorted_findings = sorted(findings, key=lambda f: severity_order.get(f["severity"], 99))
        return [
            {
                "title": f["title"],
                "file": f["file"],
                "category": f["category"],
                "severity": f["severity"],
                "proposed_action": f["proposed_action"],
            }
            for f in sorted_findings[:limit]
        ]

    def run_battle_tests(self, cycles: int = 5) -> dict:
        """Run battle stress tests if available."""
        self.log("="*60)
        self.log("PHASE 2: BATTLE TESTS")
        self.log("="*60)

        try:
            from battle_daemon import BattleDaemon
            daemon = BattleDaemon(self.project_path, dry_run=True, verbose=True)

            results = daemon.run_stress_test(rounds=cycles)
            if results:
                issues = daemon.analyze_results(results)
                self.results["battle_tests"] = {
                    "battles_run": results.get("totals", {}).get("battles_run", 0),
                    "issues_found": len(issues),
                    "top_issues": issues[:10],
                }
                return results
        except Exception as e:
            self.log(f"Battle tests skipped: {e}", "warn")
            self.results["battle_tests"] = {"error": str(e)}

        return {}

    def generate_morning_plan(self):
        """Generate prioritized plan for morning review."""
        self.log("="*60)
        self.log("GENERATING MORNING PLAN")
        self.log("="*60)

        plan = {
            "generated_at": datetime.now().isoformat(),
            "runtime_hours": (datetime.now() - self.start_time).total_seconds() / 3600,
            "sections": [],
        }

        # Section 1: Critical Issues (must fix)
        critical = []
        if self.results.get("code_audit"):
            for issue in self.results["code_audit"].get("top_issues", []):
                if issue["severity"] == "high":
                    critical.append(issue)

        if critical:
            plan["sections"].append({
                "priority": 1,
                "title": "CRITICAL ISSUES - Fix Today",
                "description": "These issues may cause runtime errors or major bugs",
                "count": len(critical),
                "items": [f"{i['title']} ({i['file']})" for i in critical[:10]],
            })

        # Section 2: Performance Optimizations
        if self.results.get("code_audit"):
            perf_count = self.results["code_audit"]["summary"].get("performance", {}).get("count", 0)
            if perf_count > 0:
                plan["sections"].append({
                    "priority": 2,
                    "title": "PERFORMANCE OPTIMIZATIONS",
                    "description": f"{perf_count} potential performance improvements found",
                    "count": perf_count,
                    "items": self.results["code_audit"]["summary"].get("performance", {}).get("items", [])[:5],
                })

        # Section 3: Code Quality (spaghetti)
        if self.results.get("code_audit"):
            spaghetti_count = self.results["code_audit"]["summary"].get("spaghetti", {}).get("count", 0)
            if spaghetti_count > 0:
                plan["sections"].append({
                    "priority": 3,
                    "title": "CODE QUALITY - Reduce Complexity",
                    "description": f"{spaghetti_count} complexity issues found (long functions, deep nesting, etc.)",
                    "count": spaghetti_count,
                    "items": self.results["code_audit"]["summary"].get("spaghetti", {}).get("items", [])[:5],
                })

        # Section 4: Dead Code Cleanup
        if self.results.get("code_audit"):
            unused_count = (
                self.results["code_audit"]["summary"].get("unused_function", {}).get("count", 0) +
                self.results["code_audit"]["summary"].get("unused_signal", {}).get("count", 0) +
                self.results["code_audit"]["summary"].get("unused_class", {}).get("count", 0)
            )
            if unused_count > 0:
                plan["sections"].append({
                    "priority": 4,
                    "title": "DEAD CODE CLEANUP",
                    "description": f"{unused_count} unused functions/signals/classes can be removed",
                    "count": unused_count,
                    "items": (
                        self.results["code_audit"]["summary"].get("unused_function", {}).get("items", [])[:3] +
                        self.results["code_audit"]["summary"].get("unused_signal", {}).get("items", [])[:2]
                    ),
                })

        # Section 5: TODOs to address
        if self.results.get("code_audit"):
            todo_count = self.results["code_audit"]["summary"].get("todo", {}).get("count", 0)
            if todo_count > 0:
                plan["sections"].append({
                    "priority": 5,
                    "title": "TODOS TO ADDRESS",
                    "description": f"{todo_count} TODO/FIXME/HACK comments found",
                    "count": todo_count,
                    "items": self.results["code_audit"]["summary"].get("todo", {}).get("items", [])[:5],
                })

        self.results["morning_plan"] = plan
        return plan

    def print_morning_summary(self):
        """Print the morning summary to console."""
        plan = self.results.get("morning_plan", {})

        print("\n" + "="*70)
        print("   GOOD MORNING! Here's your overnight analysis report")
        print("="*70)

        print(f"\nAnalysis ran for {plan.get('runtime_hours', 0):.1f} hours")

        if self.results.get("code_audit"):
            audit = self.results["code_audit"]
            print(f"Code audit found {audit['total_findings']} items to review")

        if self.results.get("battle_tests") and not self.results["battle_tests"].get("error"):
            tests = self.results["battle_tests"]
            print(f"Battle tests ran {tests['battles_run']} battles, found {tests['issues_found']} issues")

        print("\n" + "-"*70)
        print("PRIORITIZED ACTION PLAN")
        print("-"*70)

        for section in plan.get("sections", []):
            print(f"\n[Priority {section['priority']}] {section['title']}")
            print(f"   {section['description']}")
            print(f"   Total items: {section['count']}")
            for item in section.get("items", [])[:3]:
                print(f"   - {item}")
            if section["count"] > 3:
                print(f"   ... and {section['count'] - 3} more")

        print("\n" + "="*70)
        print("Full report saved to: overnight_report.json")
        print("="*70)

    def save_report(self, filename: str = "overnight_report.json"):
        """Save the full report."""
        self.results["end_time"] = datetime.now().isoformat()
        output_path = AGENT_DIR / filename
        output_path.write_text(json.dumps(self.results, indent=2))
        return output_path

    def run(self, hours: float = 8.0, with_battles: bool = False, quick: bool = False):
        """Run the full overnight analysis."""
        end_time = self.start_time + timedelta(hours=hours)

        self.log("="*70)
        self.log("OVERNIGHT RUNNER - Starting comprehensive analysis")
        self.log("="*70)
        self.log(f"Project: {self.project_path}")
        self.log(f"Duration: {hours} hours (until {end_time.strftime('%H:%M')})")
        self.log(f"Battle tests: {'enabled' if with_battles else 'disabled'}")

        # Phase 1: Code Audit
        self.run_code_audit()

        # Phase 2: Battle Tests (optional)
        if with_battles and datetime.now() < end_time:
            cycles = 3 if quick else 10
            self.run_battle_tests(cycles=cycles)

        # Generate morning plan
        self.generate_morning_plan()

        # Save and print
        report_path = self.save_report()
        self.print_morning_summary()

        return self.results


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Overnight Runner - Complete overnight analysis suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--hours", type=float, default=8.0,
                        help="Maximum runtime in hours (default: 8)")
    parser.add_argument("--with-battles", action="store_true",
                        help="Include battle stress tests")
    parser.add_argument("--quick", action="store_true",
                        help="Quick mode (fewer test cycles)")

    args = parser.parse_args()

    runner = OvernightRunner()
    runner.run(
        hours=args.hours,
        with_battles=args.with_battles,
        quick=args.quick
    )


if __name__ == "__main__":
    main()
