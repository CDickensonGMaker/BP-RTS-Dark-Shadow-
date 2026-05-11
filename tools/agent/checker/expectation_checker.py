#!/usr/bin/env python3
"""
Expectation Checker for Combat Referee Agent

Pure Python, deterministic checker that validates event logs against scenario expectations.
Same input produces same output - no LLM, no randomness.

Usage:
    from checker.expectation_checker import ExpectationChecker

    checker = ExpectationChecker()
    result = checker.check(scenario, recorded_results)

    if result["passed"]:
        print("All expectations met!")
    else:
        for failure in result["failures"]:
            print(f"FAIL: {failure['expectation_id']} - {failure['reason']}")
"""

from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field


@dataclass
class CheckResult:
    """Result of checking a single expectation."""
    expectation_id: str
    passed: bool
    matched_event: Optional[Dict[str, Any]] = None
    reason: str = ""
    near_misses: List[Dict[str, Any]] = field(default_factory=list)


class ExpectationChecker:
    """
    Validates recorded battle events against scenario expectations.

    Expectations are rules that describe what events MUST happen (positive)
    or must NOT happen (negative) during a battle. The checker scans the
    event log and reports pass/fail for each expectation.
    """

    def check(self, scenario: Dict[str, Any], recorded: Dict[str, Any]) -> Dict[str, Any]:
        """
        Check all expectations against recorded events.

        Args:
            scenario: Parsed scenario YAML with expectations
            recorded: Results dict from agent_test_runner, must have "events" key

        Returns:
            Dictionary with:
                - scenario_id: str
                - passed: bool (True if all expectations met)
                - passes: List[str] (IDs of passed expectations)
                - failures: List[Dict] (details of failed expectations)
                - events_seen: int
        """
        events = self._extract_events(recorded)
        resolutions: Dict[str, Dict[str, Any]] = {}  # exp_id -> matched event
        passes: List[str] = []
        failures: List[Dict[str, Any]] = []

        # Check positive expectations (events that MUST happen)
        for exp in scenario.get("expectations", []):
            result = self._check_positive(exp, events, resolutions)

            if result.passed:
                resolutions[exp["id"]] = result.matched_event
                passes.append(exp["id"])
            else:
                failures.append({
                    "expectation_id": exp["id"],
                    "type": "positive",
                    "reason": result.reason,
                    "near_misses": result.near_misses[:3],  # Limit to 3
                })

        # Check negative expectations (events that must NOT happen)
        for neg in scenario.get("negative_expectations", []):
            violation = self._check_negative(neg, events)

            if violation:
                failures.append({
                    "expectation_id": neg["id"],
                    "type": "negative",
                    "reason": f"Forbidden event occurred at t={violation['t']:.2f}s",
                    "violating_event": violation,
                })
            else:
                passes.append(neg["id"])

        return {
            "scenario_id": scenario.get("id", "unknown"),
            "passed": len(failures) == 0,
            "passes": passes,
            "failures": failures,
            "events_seen": len(events),
        }

    def _extract_events(self, recorded: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract events from recorded results, handling nested structure."""
        # Direct events key
        if "events" in recorded:
            return recorded["events"]

        # Nested in battles[0].runs[0].events
        battles = recorded.get("battles", [])
        if battles:
            runs = battles[0].get("runs", [])
            if runs:
                return runs[0].get("events", [])

        return []

    def _check_positive(
        self,
        exp: Dict[str, Any],
        events: List[Dict[str, Any]],
        resolutions: Dict[str, Dict[str, Any]]
    ) -> CheckResult:
        """
        Check a positive expectation (event that MUST happen).

        Args:
            exp: Expectation definition with id, event, within_sec, after
            events: List of recorded events
            resolutions: Previously matched expectations (for "after" anchoring)

        Returns:
            CheckResult with pass/fail status
        """
        exp_id = exp.get("id", "unknown")

        # Determine time anchor
        anchor_t = 0.0
        if "after" in exp:
            anchor_id = exp["after"]
            if anchor_id in resolutions and resolutions[anchor_id]:
                anchor_t = resolutions[anchor_id].get("t", 0.0)
            else:
                return CheckResult(
                    expectation_id=exp_id,
                    passed=False,
                    reason=f"Anchor expectation '{anchor_id}' not yet resolved"
                )

        # Time window
        within = exp.get("within_sec", 9999.0)

        # Target event type and filters
        event_def = exp.get("event", {})
        target_type = event_def.get("type", "")
        filters = event_def.get("filter", {})

        near_misses: List[Dict[str, Any]] = []

        # Scan events for match
        for e in events:
            event_t = e.get("t", 0.0)

            # Must be after anchor time
            if event_t < anchor_t:
                continue

            # Must be within time window
            if event_t - anchor_t > within:
                # Past the window - stop searching
                break

            # Type must match
            if e.get("type") != target_type:
                continue

            # Check filters
            if self._matches_filter(e, filters):
                return CheckResult(
                    expectation_id=exp_id,
                    passed=True,
                    matched_event=e
                )
            else:
                # Close but didn't match filters - record as near miss
                near_misses.append(e)

        return CheckResult(
            expectation_id=exp_id,
            passed=False,
            reason=f"No '{target_type}' event matching filters within {within}s of anchor",
            near_misses=near_misses
        )

    def _check_negative(
        self,
        neg: Dict[str, Any],
        events: List[Dict[str, Any]]
    ) -> Optional[Dict[str, Any]]:
        """
        Check a negative expectation (event that must NOT happen).

        Args:
            neg: Negative expectation with "never" containing type and filter
            events: List of recorded events

        Returns:
            The violating event if found, None if no violation
        """
        never = neg.get("never", {})
        target_type = never.get("type", "")
        filters = never.get("filter", {})

        for e in events:
            if e.get("type") != target_type:
                continue

            if self._matches_filter(e, filters):
                return e

        return None

    def _matches_filter(self, event: Dict[str, Any], filters: Dict[str, Any]) -> bool:
        """
        Check if an event matches all filter criteria.

        Filter syntax:
            - field: value          - Exact match
            - field_contains: str   - Case-insensitive substring
            - field_min: num        - Minimum value (inclusive)
            - field_max: num        - Maximum value (inclusive)

        All filters are AND'd together.
        """
        if not filters:
            return True

        data = event.get("data", [])

        for key, expected in filters.items():
            if not self._field_matches(data, key, expected):
                return False

        return True

    def _field_matches(self, data: List[Any], key: str, expected: Any) -> bool:
        """
        Check if a field in event data matches the expected value.

        Handles various filter suffixes:
            - _contains: substring match
            - _min: minimum value
            - _max: maximum value
            - (no suffix): exact match
        """
        # Handle _contains suffix
        if key.endswith("_contains"):
            actual_field = key[:-len("_contains")]
            return self._check_contains(data, actual_field, str(expected))

        # Handle _min suffix
        if key.endswith("_min"):
            actual_field = key[:-len("_min")]
            return self._check_min(data, actual_field, expected)

        # Handle _max suffix
        if key.endswith("_max"):
            actual_field = key[:-len("_max")]
            return self._check_max(data, actual_field, expected)

        # Exact match
        return self._check_exact(data, key, expected)

    def _check_contains(self, data: List[Any], field: str, substring: str) -> bool:
        """Check if any data item has field containing substring (case-insensitive)."""
        substring_lower = substring.lower()

        for item in data:
            if isinstance(item, dict):
                val = item.get(field)
                if val is not None:
                    if substring_lower in str(val).lower():
                        return True

        return False

    def _check_min(self, data: List[Any], field: str, min_val: float) -> bool:
        """Check if any data item has field >= min_val."""
        for item in data:
            if isinstance(item, dict):
                val = item.get(field)
                if isinstance(val, (int, float)) and val >= min_val:
                    return True

        return False

    def _check_max(self, data: List[Any], field: str, max_val: float) -> bool:
        """Check if any data item has field <= max_val."""
        for item in data:
            if isinstance(item, dict):
                val = item.get(field)
                if isinstance(val, (int, float)) and val <= max_val:
                    return True

        return False

    def _check_exact(self, data: List[Any], field: str, expected: Any) -> bool:
        """Check if any data item has field exactly matching expected."""
        for item in data:
            if isinstance(item, dict):
                val = item.get(field)
                if val == expected:
                    return True

        # Also check top-level fields in data items that aren't dicts
        # This handles cases where data is [value1, value2, ...] instead of [{}, {}]
        if field == "damage" and data:
            # Special case: damage is often the 3rd element in regiment_attacked
            for item in data:
                if isinstance(item, (int, float)) and item == expected:
                    return True

        return False


def main():
    """CLI for testing the checker."""
    import json
    import argparse

    parser = argparse.ArgumentParser(description="Expectation Checker")
    parser.add_argument("scenario", help="Path to scenario YAML")
    parser.add_argument("results", help="Path to results JSON")
    args = parser.parse_args()

    try:
        import yaml
    except ImportError:
        print("Error: PyYAML not installed. Run: pip install pyyaml")
        return 1

    with open(args.scenario, 'r') as f:
        scenario = yaml.safe_load(f)

    with open(args.results, 'r') as f:
        results = json.load(f)

    checker = ExpectationChecker()
    result = checker.check(scenario, results)

    print(f"\nScenario: {result['scenario_id']}")
    print(f"Events seen: {result['events_seen']}")
    print(f"Result: {'PASS' if result['passed'] else 'FAIL'}")
    print()

    if result['passes']:
        print("Passed expectations:")
        for exp_id in result['passes']:
            print(f"  [+] {exp_id}")

    if result['failures']:
        print("\nFailed expectations:")
        for failure in result['failures']:
            print(f"  [-] {failure['expectation_id']}: {failure['reason']}")
            if failure.get('near_misses'):
                print(f"      Near misses: {len(failure['near_misses'])}")

    return 0 if result['passed'] else 1


if __name__ == "__main__":
    exit(main())
