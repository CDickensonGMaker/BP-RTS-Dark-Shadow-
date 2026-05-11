#!/usr/bin/env python3
"""
Briefing Aggregator - Layer 5 of the Combat Watchdog

Merges findings from all three perception systems:
- Drift detector (Layer 2): Statistical anomalies over time
- Snapshot analyzer (Layer 3): In-the-moment bugs from tonight
- Scenario referee (Layer 4): Named regression checks

Deduplicates overlapping findings, ranks by severity, writes one morning markdown.

Usage:
    from briefing.aggregator import BriefingAggregator

    aggregator = BriefingAggregator(output_dir)
    briefing = aggregator.aggregate_and_write(
        drift_findings, snapshot_findings, regression_findings, run_stats
    )
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Set, Tuple
from dataclasses import dataclass, field


@dataclass
class UnifiedFinding:
    """A finding in the unified schema used by all layers."""
    id: str
    source: str  # "drift", "snapshot", "regression"
    sources: List[str] = field(default_factory=list)  # When merged, lists all sources
    category: str = "bug"  # "bug", "balance", "ai", "drift", "regression"
    severity: str = "medium"  # "critical", "high", "medium", "low"
    title: str = ""
    evidence: Dict[str, Any] = field(default_factory=dict)
    code_hints: List[str] = field(default_factory=list)
    first_seen: str = ""
    git_context: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "source": self.source,
            "sources": self.sources or [self.source],
            "category": self.category,
            "severity": self.severity,
            "title": self.title,
            "evidence": self.evidence,
            "code_hints": self.code_hints,
            "first_seen": self.first_seen,
            "git_context": self.git_context,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "UnifiedFinding":
        return cls(
            id=data.get("id", ""),
            source=data.get("source", "unknown"),
            sources=data.get("sources", []),
            category=data.get("category", "bug"),
            severity=data.get("severity", "medium"),
            title=data.get("title", ""),
            evidence=data.get("evidence", {}),
            code_hints=data.get("code_hints", []),
            first_seen=data.get("first_seen", ""),
            git_context=data.get("git_context", {}),
        )


@dataclass
class RunStats:
    """Statistics from tonight's run."""
    start_time: datetime
    end_time: datetime
    battles_run: int = 0
    scenarios_run: int = 0
    variants_run: int = 0
    stress_battles: int = 0
    commit_sha: str = ""
    difficulty_profile: str = "normal"


class BriefingAggregator:
    """
    Aggregates findings from all layers and produces the morning briefing.
    """

    # Severity ordering for ranking
    SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}

    # Auto-archive findings older than this (days)
    STALE_THRESHOLD_DAYS = 30

    # Auto-collapse medium/low after this many
    COLLAPSE_THRESHOLD = 5

    def __init__(self, output_dir: Path, findings_dir: Path = None):
        """
        Initialize the aggregator.

        Args:
            output_dir: Directory for briefings/
            findings_dir: Directory for findings/ (individual JSON files)
        """
        self.output_dir = Path(output_dir)
        self.briefings_dir = self.output_dir / "briefings"
        self.findings_dir = findings_dir or (self.output_dir / "findings")

        self.briefings_dir.mkdir(parents=True, exist_ok=True)
        self.findings_dir.mkdir(parents=True, exist_ok=True)

    def aggregate_and_write(
        self,
        drift_findings: List[Dict[str, Any]],
        snapshot_findings: List[Dict[str, Any]],
        regression_findings: List[Dict[str, Any]],
        run_stats: RunStats
    ) -> str:
        """
        Aggregate all findings, dedupe, rank, and write briefing.

        Args:
            drift_findings: From Layer 2 drift detector
            snapshot_findings: From Layer 3 analyze_results
            regression_findings: From Layer 4 scenario checker
            run_stats: Statistics from tonight's run

        Returns:
            Path to the written briefing file
        """
        # Normalize all findings to unified schema
        all_findings = []

        for f in drift_findings:
            uf = self._normalize_finding(f, "drift")
            all_findings.append(uf)

        for f in snapshot_findings:
            uf = self._normalize_finding(f, "snapshot")
            all_findings.append(uf)

        for f in regression_findings:
            uf = self._normalize_finding(f, "regression")
            all_findings.append(uf)

        # Deduplicate overlapping findings
        deduped = self._deduplicate(all_findings)

        # Rank by severity
        ranked = sorted(deduped, key=lambda f: self.SEVERITY_ORDER.get(f.severity, 99))

        # Save individual finding files
        today = datetime.now().strftime("%Y-%m-%d")
        findings_subdir = self.findings_dir / today
        findings_subdir.mkdir(parents=True, exist_ok=True)

        for i, finding in enumerate(ranked):
            finding_path = findings_subdir / f"{finding.id}.json"
            with open(finding_path, 'w', encoding='utf-8') as f:
                json.dump(finding.to_dict(), f, indent=2, default=str)

        # Generate briefing markdown
        briefing_content = self._generate_briefing(ranked, run_stats)

        # Write briefing
        briefing_path = self.briefings_dir / f"{today}.md"
        with open(briefing_path, 'w', encoding='utf-8') as f:
            f.write(briefing_content)

        print(f"[BriefingAggregator] Wrote briefing to {briefing_path}")
        print(f"[BriefingAggregator] {len(ranked)} findings saved to {findings_subdir}")

        return str(briefing_path)

    def _normalize_finding(self, data: Dict[str, Any], source: str) -> UnifiedFinding:
        """Normalize a finding from any source to unified schema."""
        # Handle different source formats
        if source == "snapshot":
            # Snapshot findings from battle_daemon.py have different keys
            return UnifiedFinding(
                id=data.get("id", f"SNAP-{datetime.now().strftime('%Y%m%d%H%M%S')}"),
                source=source,
                sources=[source],
                category=data.get("category", data.get("type", "bug")),
                severity=data.get("severity", "medium"),
                title=data.get("title", data.get("description", "")),
                evidence=data.get("evidence", {}),
                code_hints=data.get("code_hints", []),
                first_seen=datetime.now().strftime("%Y-%m-%d"),
                git_context={},
            )
        elif source == "regression":
            # Regression findings from expectation checker
            return UnifiedFinding(
                id=data.get("id", data.get("expectation_id", "REG-unknown")),
                source=source,
                sources=[source],
                category="regression",
                severity=data.get("severity", "high"),  # Regressions are high by default
                title=data.get("title", data.get("reason", "Expectation failed")),
                evidence={
                    "expectation_id": data.get("expectation_id"),
                    "type": data.get("type"),
                    "near_misses": data.get("near_misses", []),
                },
                code_hints=data.get("code_hints", []),
                first_seen=datetime.now().strftime("%Y-%m-%d"),
                git_context={},
            )
        else:
            # Drift findings already in standard format
            return UnifiedFinding.from_dict(data)

    def _deduplicate(self, findings: List[UnifiedFinding]) -> List[UnifiedFinding]:
        """
        Deduplicate overlapping findings.

        Merge rule: if two findings have overlapping evidence keys
        (e.g., both reference faction: skaven plus metric: win_rate),
        merge into one finding listing both sources.
        The higher-severity source wins on rank.
        """
        if not findings:
            return []

        # Group by potential overlap keys
        merged = []
        seen_keys: Set[str] = set()

        for finding in findings:
            # Generate dedup key from evidence
            dedup_key = self._get_dedup_key(finding)

            if dedup_key in seen_keys:
                # Find existing and merge
                for existing in merged:
                    if self._get_dedup_key(existing) == dedup_key:
                        self._merge_into(existing, finding)
                        break
            else:
                seen_keys.add(dedup_key)
                merged.append(finding)

        return merged

    def _get_dedup_key(self, finding: UnifiedFinding) -> str:
        """Generate a key for deduplication based on evidence overlap."""
        parts = []

        evidence = finding.evidence

        # Key by faction if present
        if "faction" in evidence:
            parts.append(f"faction:{evidence['faction']}")

        # Key by unit if present
        if "unit_id" in evidence:
            parts.append(f"unit:{evidence['unit_id']}")

        # Key by metric if present
        if "metric" in evidence:
            parts.append(f"metric:{evidence['metric']}")

        # Key by battle index if present
        if "battle_idx" in evidence:
            parts.append(f"battle:{evidence['battle_idx']}")

        # Key by expectation ID for regressions
        if "expectation_id" in evidence:
            parts.append(f"exp:{evidence['expectation_id']}")

        # Fallback to title-based key
        if not parts:
            parts.append(f"title:{finding.title[:50]}")

        return "|".join(sorted(parts))

    def _merge_into(self, existing: UnifiedFinding, new: UnifiedFinding) -> None:
        """Merge a new finding into an existing one."""
        # Add source
        if new.source not in existing.sources:
            existing.sources.append(new.source)

        # Keep higher severity
        if self.SEVERITY_ORDER.get(new.severity, 99) < self.SEVERITY_ORDER.get(existing.severity, 99):
            existing.severity = new.severity

        # Merge evidence
        for key, value in new.evidence.items():
            if key not in existing.evidence:
                existing.evidence[key] = value

        # Merge code hints (dedupe)
        for hint in new.code_hints:
            if hint not in existing.code_hints:
                existing.code_hints.append(hint)

        # Update title if new one is more descriptive
        if len(new.title) > len(existing.title):
            existing.title = new.title

    def _generate_briefing(
        self,
        findings: List[UnifiedFinding],
        stats: RunStats
    ) -> str:
        """Generate the morning briefing markdown."""
        lines = []
        today = datetime.now().strftime("%Y-%m-%d")

        # Header
        lines.append(f"# Combat Watchdog Briefing - {today}")
        lines.append("")

        # Run summary
        duration = stats.end_time - stats.start_time
        duration_str = f"{int(duration.total_seconds() // 3600)}h {int((duration.total_seconds() % 3600) // 60):02d}m"

        lines.append(f"**Shift:** {stats.start_time.strftime('%I:%M %p')} -> {stats.end_time.strftime('%I:%M %p')} ({duration_str})")
        lines.append(f"**Commit:** `{stats.commit_sha}`")
        lines.append(f"**Difficulty:** {stats.difficulty_profile}")
        lines.append(f"**Battles:** {stats.battles_run} total ({stats.stress_battles} stress, {stats.scenarios_run} scenarios + {stats.variants_run} variants)")
        lines.append("")

        # Status badge
        critical = [f for f in findings if f.severity == "critical"]
        high = [f for f in findings if f.severity == "high"]
        medium = [f for f in findings if f.severity == "medium"]
        low = [f for f in findings if f.severity == "low"]

        if critical:
            lines.append(f"**Status:** :rotating_light: {len(critical)} CRITICAL, {len(high)} high, {len(medium)} medium")
        elif high:
            lines.append(f"**Status:** :warning: {len(high)} high priority, {len(medium)} medium")
        elif medium:
            lines.append(f"**Status:** :information_source: {len(medium)} findings to review")
        else:
            lines.append(f"**Status:** :white_check_mark: All systems nominal")

        lines.append("")
        lines.append("---")
        lines.append("")

        # Section 1: Drift alarms (highest priority)
        drift_findings = [f for f in findings if f.source == "drift" or "drift" in f.sources]
        if drift_findings:
            lines.append("## :chart_with_downwards_trend: Drift Alarms")
            lines.append("")
            lines.append("*These metrics changed significantly from the 7-day baseline.*")
            lines.append("")

            for f in drift_findings:
                lines.append(f"### [{f.severity.upper()}] {f.title}")
                lines.append("")

                if f.evidence.get("tonight_value") is not None:
                    lines.append(f"- Tonight: **{f.evidence['tonight_value']:.3f}**")
                    lines.append(f"- Baseline: {f.evidence.get('baseline_mean', 0):.3f} ± {f.evidence.get('baseline_stddev', 0):.3f}")

                if f.git_context.get("last_stable_date"):
                    lines.append(f"- Last stable: {f.git_context['last_stable_date']}")

                if f.git_context.get("commits_since_stable"):
                    lines.append(f"- Commits since: {len(f.git_context['commits_since_stable'])}")
                    for commit in f.git_context['commits_since_stable'][:3]:
                        lines.append(f"  - `{commit}`")

                if f.code_hints:
                    lines.append("")
                    lines.append("**Investigate:**")
                    for hint in f.code_hints[:3]:
                        lines.append(f"- {hint}")

                lines.append("")

            lines.append("---")
            lines.append("")

        # Section 2: Critical regressions
        regression_findings = [f for f in findings if f.category == "regression" and f.severity in ("critical", "high")]
        if regression_findings:
            lines.append("## :red_circle: Regressions")
            lines.append("")
            lines.append("*Named scenarios that broke since last passing run.*")
            lines.append("")

            for f in regression_findings:
                lines.append(f"### {f.evidence.get('expectation_id', f.id)}")
                lines.append("")
                lines.append(f"**{f.title}**")
                lines.append("")

                if f.evidence.get("near_misses"):
                    lines.append(f"Near misses: {len(f.evidence['near_misses'])} events close to matching")

                lines.append("")

            lines.append("---")
            lines.append("")

        # Section 3: High-severity snapshot findings
        snapshot_high = [f for f in findings if f.source == "snapshot" and f.severity in ("critical", "high")]
        if snapshot_high:
            lines.append("## :warning: Tonight's Issues")
            lines.append("")
            lines.append("*In-the-moment bugs from stress testing.*")
            lines.append("")

            for f in snapshot_high:
                lines.append(f"### [{f.severity.upper()}] {f.title}")
                lines.append("")

                # Show key evidence
                for key in ["battle_idx", "duration_sec", "player_casualties", "enemy_casualties"]:
                    if key in f.evidence:
                        lines.append(f"- {key}: {f.evidence[key]}")

                if f.code_hints:
                    lines.append("")
                    lines.append("**Investigate:**")
                    for hint in f.code_hints[:2]:
                        lines.append(f"- {hint}")

                lines.append("")

            lines.append("---")
            lines.append("")

        # Section 4: Medium/low collapsed
        medium_low = [f for f in findings if f.severity in ("medium", "low")]
        if medium_low:
            lines.append("## :information_source: Other Findings")
            lines.append("")

            if len(medium_low) <= self.COLLAPSE_THRESHOLD:
                for f in medium_low:
                    lines.append(f"- [{f.severity}] {f.title}")
            else:
                for f in medium_low[:self.COLLAPSE_THRESHOLD]:
                    lines.append(f"- [{f.severity}] {f.title}")
                lines.append(f"- ... and {len(medium_low) - self.COLLAPSE_THRESHOLD} more in `findings/{today}/`")

            lines.append("")
            lines.append("---")
            lines.append("")

        # Section 5: Stats
        lines.append("## Stats")
        lines.append("")
        lines.append(f"- Wall-clock: {duration_str}")
        lines.append(f"- Stress battles: {stats.stress_battles}")
        lines.append(f"- Scenario runs: {stats.scenarios_run} base + {stats.variants_run} variants")
        lines.append(f"- Total findings: {len(findings)}")
        lines.append(f"  - Critical: {len(critical)}")
        lines.append(f"  - High: {len(high)}")
        lines.append(f"  - Medium: {len(medium)}")
        lines.append(f"  - Low: {len(low)}")
        lines.append("")

        # Multi-source findings (higher authority)
        multi_source = [f for f in findings if len(f.sources) > 1]
        if multi_source:
            lines.append("### High-Authority Findings (multiple sources agree)")
            lines.append("")
            for f in multi_source:
                sources_str = " + ".join(f.sources)
                lines.append(f"- [{f.severity}] {f.title} *({sources_str})*")
            lines.append("")

        lines.append("---")
        lines.append("*Report generated by Combat Watchdog*")

        return "\n".join(lines)

    def load_historical_findings(self, days: int = 7) -> List[UnifiedFinding]:
        """Load findings from the last N days."""
        findings = []
        today = datetime.now()

        for i in range(days):
            date = today - timedelta(days=i)
            date_str = date.strftime("%Y-%m-%d")
            findings_subdir = self.findings_dir / date_str

            if not findings_subdir.exists():
                continue

            for finding_file in findings_subdir.glob("*.json"):
                try:
                    with open(finding_file, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        findings.append(UnifiedFinding.from_dict(data))
                except Exception:
                    pass

        return findings


from datetime import timedelta


def main():
    """Test the aggregator."""
    from datetime import datetime, timedelta

    aggregator = BriefingAggregator(
        output_dir=Path("C:/Users/caleb/BP_RTS_Dark_Shadows/tools/agent")
    )

    # Sample findings
    drift_findings = [
        {
            "id": "DRIFT-faction_skaven_win_rate-20260508",
            "source": "drift",
            "category": "drift",
            "severity": "high",
            "title": "faction_skaven_win_rate is lower than baseline (0.22 vs 0.50±0.08)",
            "evidence": {
                "metric": "faction_skaven_win_rate",
                "tonight_value": 0.22,
                "baseline_mean": 0.50,
                "baseline_stddev": 0.08,
                "direction": "lower",
            },
            "code_hints": ["Check skaven unit stats"],
            "first_seen": "2026-05-08",
            "git_context": {
                "last_stable_date": "2026-05-04",
                "commits_since_stable": ["abc123 Buff empire units"],
            },
        }
    ]

    snapshot_findings = [
        {
            "category": "bug",
            "severity": "high",
            "title": "Battle 5: charge_impact fired but no measurable damage",
            "evidence": {"battle_idx": 5, "total_casualties": 0},
            "code_hints": ["Check combat_manager.gd begin_melee"],
        }
    ]

    regression_findings = [
        {
            "expectation_id": "charge_impact_fires",
            "type": "positive",
            "severity": "high",
            "reason": "No 'charge_impact' event matching filters within 5.0s of anchor",
            "near_misses": [{"type": "charge_impact", "t": 5.3}],
        }
    ]

    stats = RunStats(
        start_time=datetime(2026, 5, 8, 23, 30),
        end_time=datetime(2026, 5, 9, 4, 30),
        battles_run=75,
        scenarios_run=10,
        variants_run=40,
        stress_battles=25,
        commit_sha="abc123f",
        difficulty_profile="normal",
    )

    briefing_path = aggregator.aggregate_and_write(
        drift_findings, snapshot_findings, regression_findings, stats
    )

    print(f"\nBriefing written to: {briefing_path}")


if __name__ == "__main__":
    main()
