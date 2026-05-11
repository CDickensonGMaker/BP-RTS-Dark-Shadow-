#!/usr/bin/env python3
"""
Briefing Generator for Combat Referee Agent

Generates morning briefing markdown files from overnight test results.
The briefing is a 3-minute coffee read summarizing:
- Regressions (highest priority)
- New findings (variant fuzzing discoveries)
- Holding steady (passing scenarios)
- Stats (time, LLM costs)

Usage:
    from briefing.briefing_generator import BriefingGenerator

    generator = BriefingGenerator()
    briefing = generator.generate(shift_results)
    generator.save(briefing, "briefings/2026-05-08.md")
"""

import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field

try:
    from jinja2 import Environment, FileSystemLoader, select_autoescape
    JINJA_AVAILABLE = True
except ImportError:
    JINJA_AVAILABLE = False


@dataclass
class ScenarioResult:
    """Result summary for a single scenario."""
    scenario_id: str
    passed: bool
    variant_count: int = 1
    failures: List[Dict[str, Any]] = field(default_factory=list)
    pass_count: int = 0
    fail_count: int = 0
    last_passing_date: Optional[str] = None
    is_regression: bool = False


@dataclass
class Finding:
    """A notable finding from the test run."""
    finding_id: str
    scenario_id: str
    severity: str  # critical, high, medium, low
    title: str
    description: str
    likely_culprit: str = ""
    reproducible: bool = True
    finding_file: str = ""


@dataclass
class ShiftResults:
    """Aggregate results from a test shift."""
    start_time: datetime
    end_time: datetime
    scenarios_run: int = 0
    variants_run: int = 0
    passes: int = 0
    failures: int = 0
    regressions: List[ScenarioResult] = field(default_factory=list)
    new_findings: List[Finding] = field(default_factory=list)
    holding_steady: List[ScenarioResult] = field(default_factory=list)
    llm_calls: int = 0
    llm_cost: float = 0.0
    errors: List[str] = field(default_factory=list)


class BriefingGenerator:
    """
    Generates morning briefing markdown from shift results.
    """

    def __init__(self, templates_dir: Optional[Path] = None):
        """
        Initialize the generator.

        Args:
            templates_dir: Path to Jinja2 templates directory
        """
        if templates_dir is None:
            templates_dir = Path(__file__).parent / "templates"

        self.templates_dir = templates_dir

        if JINJA_AVAILABLE and templates_dir.exists():
            self.env = Environment(
                loader=FileSystemLoader(str(templates_dir)),
                autoescape=select_autoescape(['html', 'xml']),
                trim_blocks=True,
                lstrip_blocks=True
            )
        else:
            self.env = None

    def generate(self, results: ShiftResults) -> str:
        """
        Generate briefing markdown from shift results.

        Args:
            results: Aggregate results from the test shift

        Returns:
            Formatted markdown string
        """
        if self.env and (self.templates_dir / "briefing.md.j2").exists():
            return self._generate_from_template(results)
        else:
            return self._generate_inline(results)

    def _generate_from_template(self, results: ShiftResults) -> str:
        """Generate briefing using Jinja2 template."""
        template = self.env.get_template("briefing.md.j2")
        return template.render(
            results=results,
            date=results.end_time.strftime("%Y-%m-%d"),
            shift_start=results.start_time.strftime("%I:%M %p"),
            shift_end=results.end_time.strftime("%I:%M %p"),
            duration=self._format_duration(results.end_time - results.start_time),
        )

    def _generate_inline(self, results: ShiftResults) -> str:
        """Generate briefing without template (fallback)."""
        date_str = results.end_time.strftime("%Y-%m-%d")
        start_str = results.start_time.strftime("%I:%M %p")
        end_str = results.end_time.strftime("%I:%M %p")
        duration = self._format_duration(results.end_time - results.start_time)

        lines = []
        lines.append(f"# Combat Referee Briefing - {date_str}")
        lines.append("")
        lines.append(f"**Shift:** {start_str} -> {end_str} ({duration})")
        lines.append(f"**Scenarios run:** {results.scenarios_run} base + {results.variants_run} variants ({results.scenarios_run + results.variants_run} total)")

        # Status summary
        if results.regressions:
            lines.append(f"**Status:** :warning: {len(results.regressions)} regressions, {len(results.new_findings)} new findings, {results.passes} pass")
        elif results.new_findings:
            lines.append(f"**Status:** :information_source: {len(results.new_findings)} new findings, {results.passes} pass")
        else:
            lines.append(f"**Status:** :white_check_mark: All {results.passes} scenarios pass")

        lines.append("")
        lines.append("---")
        lines.append("")

        # Regressions section
        if results.regressions:
            lines.append("## :red_circle: Regressions (highest priority)")
            lines.append("")

            for reg in results.regressions:
                lines.append(f"### {reg.scenario_id} - failing in {reg.fail_count}/{reg.variant_count} runs")
                lines.append("")

                for failure in reg.failures[:2]:  # Show max 2 failures
                    lines.append(f"**Expected:** {failure.get('expectation_id', 'unknown')}")
                    lines.append(f"**Actual:** {failure.get('reason', 'Unknown failure')}")

                    if failure.get('near_misses'):
                        lines.append(f"**Near misses:** {len(failure['near_misses'])} events close to matching")

                    lines.append("")

                if reg.last_passing_date:
                    lines.append(f"**Last passing run:** {reg.last_passing_date}")

                lines.append(f"**Reproducible:** {'yes' if reg.fail_count > 1 else 'intermittent'}")
                lines.append("")
                lines.append("---")
                lines.append("")

        # New findings section
        if results.new_findings:
            lines.append("## :warning: New findings (variant fuzzing surfaced these)")
            lines.append("")

            for finding in results.new_findings:
                lines.append(f"### {finding.title}")
                lines.append("")
                lines.append(finding.description)
                lines.append("")

                if finding.likely_culprit:
                    lines.append(f"**Likely culprit:** {finding.likely_culprit}")

                if finding.finding_file:
                    lines.append(f"**Finding file:** [{finding.finding_file}]({finding.finding_file})")

                lines.append("")
                lines.append("---")
                lines.append("")

        # Holding steady section
        if results.holding_steady:
            lines.append("## :white_check_mark: Holding steady (FYI)")
            lines.append("")

            for scenario in results.holding_steady[:5]:  # Show max 5
                lines.append(f"- {scenario.scenario_id}: {scenario.pass_count}/{scenario.variant_count} variants pass")

            if len(results.holding_steady) > 5:
                lines.append(f"- ... and {len(results.holding_steady) - 5} more")

            lines.append("")
            lines.append("---")
            lines.append("")

        # Stats section
        lines.append("## Stats")
        lines.append("")
        lines.append(f"- Wall-clock: {duration}")
        lines.append(f"- Scenarios: {results.scenarios_run}")
        lines.append(f"- Variants: {results.variants_run}")
        lines.append(f"- Total runs: {results.scenarios_run + results.variants_run}")

        if results.llm_calls > 0:
            lines.append(f"- LLM calls: {results.llm_calls} (${results.llm_cost:.2f})")

        if results.errors:
            lines.append("")
            lines.append("### Errors")
            for error in results.errors[:5]:
                lines.append(f"- {error}")

        lines.append("")
        lines.append("---")
        lines.append("*Report generated by Combat Referee Agent*")

        return "\n".join(lines)

    def _format_duration(self, delta) -> str:
        """Format timedelta as human-readable string."""
        total_seconds = int(delta.total_seconds())
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60

        if hours > 0:
            return f"{hours}h {minutes:02d}m"
        else:
            return f"{minutes}m"

    def save(self, content: str, filepath: Path) -> None:
        """
        Save briefing to file.

        Args:
            content: Briefing markdown content
            filepath: Output file path
        """
        filepath = Path(filepath)
        filepath.parent.mkdir(parents=True, exist_ok=True)

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

        print(f"[BriefingGenerator] Saved briefing to {filepath}")

    @staticmethod
    def from_raw_results(
        raw_results: List[Dict[str, Any]],
        start_time: datetime,
        end_time: datetime
    ) -> ShiftResults:
        """
        Convert raw test results to ShiftResults.

        Args:
            raw_results: List of per-scenario check results
            start_time: When shift started
            end_time: When shift ended

        Returns:
            Aggregated ShiftResults
        """
        shift = ShiftResults(start_time=start_time, end_time=end_time)

        for result in raw_results:
            scenario_id = result.get("scenario_id", "unknown")
            passed = result.get("passed", False)
            failures = result.get("failures", [])

            scenario_result = ScenarioResult(
                scenario_id=scenario_id,
                passed=passed,
                failures=failures,
                pass_count=len(result.get("passes", [])),
                fail_count=len(failures)
            )

            shift.scenarios_run += 1

            if passed:
                shift.passes += 1
                shift.holding_steady.append(scenario_result)
            else:
                shift.failures += 1
                scenario_result.is_regression = True
                shift.regressions.append(scenario_result)

        return shift


def main():
    """CLI for testing the briefing generator."""
    from datetime import timedelta

    # Create sample results
    results = ShiftResults(
        start_time=datetime(2026, 5, 8, 23, 30),
        end_time=datetime(2026, 5, 9, 4, 32),
        scenarios_run=23,
        variants_run=142,
        passes=158,
        failures=4,
        llm_calls=7,
        llm_cost=0.34
    )

    # Add sample regression
    results.regressions.append(ScenarioResult(
        scenario_id="cavalry_charge_deals_impact_damage",
        passed=False,
        variant_count=5,
        fail_count=2,
        failures=[{
            "expectation_id": "charge_impact_fires",
            "reason": "No 'charge_impact' event matching filters within 5.0s of anchor",
            "near_misses": [{"type": "charge_impact", "t": 5.3}]
        }],
        last_passing_date="3 days ago"
    ))

    # Add sample finding
    results.new_findings.append(Finding(
        finding_id="F-001",
        scenario_id="charge_into_1_soldier",
        severity="low",
        title="Charge into 1-soldier defender produces non-deterministic event order",
        description="When defender has exactly 1 soldier remaining and is charged, charge_impact and regiment_dead fire same frame, in different orders across runs.",
        finding_file="findings/2026-05-09/F-001.json"
    ))

    # Add sample holding steady
    results.holding_steady.append(ScenarioResult(
        scenario_id="flanking_disorder_penalty",
        passed=True,
        variant_count=23,
        pass_count=23
    ))

    # Generate briefing
    generator = BriefingGenerator()
    briefing = generator.generate(results)

    print(briefing)

    return 0


if __name__ == "__main__":
    exit(main())
