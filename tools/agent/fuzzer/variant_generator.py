#!/usr/bin/env python3
"""
Variant Generator for Combat Referee Agent

Generates test variants from scenario variant_ranges.
Two modes:
1. Deterministic permutation - Cartesian product of ranges (no LLM, free, fast)
2. LLM-proposed weirdness - Optional, rate-limited, costs money

Usage:
    from fuzzer.variant_generator import VariantGenerator

    generator = VariantGenerator()
    variants = generator.generate_variants(scenario)

    for variant in variants:
        # variant is a modified copy of the scenario with specific values
        run_scenario(variant)
"""

import copy
import itertools
from typing import Dict, Any, List, Optional, Tuple, Iterator
from dataclasses import dataclass


@dataclass
class VariantRange:
    """A single parameter range to vary."""
    name: str
    values: List[Any]
    original_value: Any = None


class VariantGenerator:
    """
    Generates scenario variants from variant_ranges.

    Deterministic: same scenario always produces same variants.
    """

    MAX_VARIANTS_PER_SCENARIO: int = 50  # Cap to prevent explosion

    def __init__(self, max_variants: int = None):
        """
        Initialize the generator.

        Args:
            max_variants: Maximum variants to generate (default 50)
        """
        self.max_variants = max_variants or self.MAX_VARIANTS_PER_SCENARIO

    def generate_variants(self, scenario: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Generate all variants for a scenario.

        Args:
            scenario: Parsed scenario YAML with variant_ranges

        Returns:
            List of scenario variants (copies with specific values)
        """
        ranges = self._parse_variant_ranges(scenario)

        if not ranges:
            return []  # No variants defined

        # Generate all combinations
        all_values = [r.values for r in ranges]
        all_names = [r.name for r in ranges]

        variants = []
        for combo in itertools.product(*all_values):
            if len(variants) >= self.max_variants:
                break

            variant = self._apply_variant(scenario, dict(zip(all_names, combo)))
            variants.append(variant)

        return variants

    def generate_variants_lazy(self, scenario: Dict[str, Any]) -> Iterator[Dict[str, Any]]:
        """
        Generate variants lazily (memory-efficient for large ranges).

        Yields:
            Scenario variants one at a time
        """
        ranges = self._parse_variant_ranges(scenario)

        if not ranges:
            return

        all_values = [r.values for r in ranges]
        all_names = [r.name for r in ranges]

        count = 0
        for combo in itertools.product(*all_values):
            if count >= self.max_variants:
                break

            variant = self._apply_variant(scenario, dict(zip(all_names, combo)))
            yield variant
            count += 1

    def _parse_variant_ranges(self, scenario: Dict[str, Any]) -> List[VariantRange]:
        """
        Parse variant_ranges section into VariantRange objects.

        Supports formats:
            - [10, 50, step: 10] -> [10, 20, 30, 40, 50]
            - [10, 20, 30] -> [10, 20, 30]
            - ["hold", "march", "routing"] -> as-is
        """
        ranges_def = scenario.get("variant_ranges", {})
        ranges = []

        for name, value_spec in ranges_def.items():
            values = self._expand_range(value_spec)
            if values:
                ranges.append(VariantRange(name=name, values=values))

        return ranges

    def _expand_range(self, value_spec: Any) -> List[Any]:
        """
        Expand a range specification into actual values.

        Handles:
            - List with step: [10, 50, {"step": 10}] or [10, 50, step: 10]
            - Simple list: [10, 20, 30]
            - String list: ["hold", "march"]
        """
        if not isinstance(value_spec, list):
            return [value_spec]

        if len(value_spec) == 0:
            return []

        # Check for step specification (last element is dict with "step")
        if len(value_spec) >= 3 and isinstance(value_spec[-1], dict) and "step" in value_spec[-1]:
            start = value_spec[0]
            end = value_spec[1]
            step = value_spec[-1]["step"]

            if isinstance(start, (int, float)) and isinstance(end, (int, float)):
                return self._numeric_range(start, end, step)

        # Check for inline step notation: [10, 50, "step", 10] or similar
        if len(value_spec) >= 4 and value_spec[2] == "step":
            start = value_spec[0]
            end = value_spec[1]
            step = value_spec[3]

            if isinstance(start, (int, float)) and isinstance(end, (int, float)):
                return self._numeric_range(start, end, step)

        # Simple list - return as-is
        return list(value_spec)

    def _numeric_range(self, start: float, end: float, step: float) -> List[float]:
        """Generate numeric range including both endpoints."""
        values = []
        current = start

        while current <= end:
            # Use int if all values are whole numbers
            if float(current).is_integer():
                values.append(int(current))
            else:
                values.append(current)
            current += step

        return values

    def _apply_variant(
        self,
        scenario: Dict[str, Any],
        variant_values: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Create a variant by applying specific values to a scenario copy.

        Args:
            scenario: Original scenario
            variant_values: Dict of parameter_name -> value

        Returns:
            Deep copy of scenario with variant values applied
        """
        variant = copy.deepcopy(scenario)

        # Generate deterministic variant ID
        variant_id_parts = [scenario.get("id", "scenario")]
        for name, value in sorted(variant_values.items()):
            variant_id_parts.append(f"{name}={value}")

        variant["variant_id"] = "__".join(variant_id_parts)
        variant["variant_values"] = variant_values

        # Apply values to setup
        setup = variant.get("setup", {})

        for name, value in variant_values.items():
            self._apply_single_value(setup, name, value)

        return variant

    def _apply_single_value(
        self,
        setup: Dict[str, Any],
        param_name: str,
        value: Any
    ) -> None:
        """
        Apply a single variant value to the setup.

        Handles special parameter names:
            - player_count: Set count for all player units
            - enemy_count: Set count for all enemy units
            - player_unit: Set unit type for first player unit
            - enemy_unit: Set unit type for first enemy unit
            - player_facing_angle: Rotate player facing by angle
            - duration_sec: Battle duration
            - difficulty: Difficulty setting
            - weather: Weather setting
        """
        if param_name == "player_count":
            for unit in setup.get("player", []):
                unit["count"] = value

        elif param_name == "enemy_count":
            for unit in setup.get("enemy", []):
                unit["count"] = value

        elif param_name == "player_unit":
            if setup.get("player"):
                setup["player"][0]["unit"] = value

        elif param_name == "enemy_unit":
            if setup.get("enemy"):
                setup["enemy"][0]["unit"] = value

        elif param_name == "player_facing_angle":
            # Rotate player facing by angle (degrees)
            import math
            angle_rad = math.radians(value)
            for unit in setup.get("player", []):
                facing = unit.get("facing", [1, 0, 0])
                if len(facing) >= 2:
                    # Rotate in XZ plane
                    x, z = facing[0], facing[2] if len(facing) > 2 else 0
                    new_x = x * math.cos(angle_rad) - z * math.sin(angle_rad)
                    new_z = x * math.sin(angle_rad) + z * math.cos(angle_rad)
                    unit["facing"] = [new_x, facing[1] if len(facing) > 1 else 0, new_z]

        elif param_name == "duration_sec":
            setup["duration_sec"] = value

        elif param_name == "difficulty":
            setup["difficulty"] = value

        elif param_name == "weather":
            setup["weather"] = value

        elif param_name == "enemy_state_pre_charge":
            # Apply order to enemy units
            for unit in setup.get("enemy", []):
                unit["order"] = value

        elif param_name.startswith("player_"):
            # Generic player unit property
            prop = param_name[len("player_"):]
            if setup.get("player"):
                setup["player"][0][prop] = value

        elif param_name.startswith("enemy_"):
            # Generic enemy unit property
            prop = param_name[len("enemy_"):]
            if setup.get("enemy"):
                setup["enemy"][0][prop] = value

    def estimate_variant_count(self, scenario: Dict[str, Any]) -> int:
        """Estimate how many variants will be generated (before cap)."""
        ranges = self._parse_variant_ranges(scenario)
        if not ranges:
            return 0

        count = 1
        for r in ranges:
            count *= len(r.values)

        return min(count, self.max_variants)


class LLMVariantProposer:
    """
    Proposes unusual variants using LLM consultation.

    Rate-limited and budget-constrained. Only runs when:
    1. LLM budget allows
    2. Scenario has had recent failures
    3. Not run in the last N hours for this scenario
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "claude-3-haiku-20240307",
        max_proposals_per_run: int = 5
    ):
        self.api_key = api_key
        self.model = model
        self.max_proposals = max_proposals_per_run

    def propose_variants(
        self,
        scenario: Dict[str, Any],
        recent_failures: List[Dict[str, Any]] = None
    ) -> List[Dict[str, Any]]:
        """
        Use LLM to propose unusual but valid variants.

        Args:
            scenario: Base scenario
            recent_failures: Recent failure info to guide proposals

        Returns:
            List of proposed variant value dicts
        """
        if not self.api_key:
            return []

        # Build prompt
        ranges = scenario.get("variant_ranges", {})
        if not ranges:
            return []

        prompt = self._build_proposal_prompt(scenario, ranges, recent_failures)

        # Call LLM (placeholder - implement with actual API)
        try:
            proposals = self._call_llm(prompt)
            return self._validate_proposals(proposals, ranges)
        except Exception as e:
            print(f"[LLMVariantProposer] Error: {e}")
            return []

    def _build_proposal_prompt(
        self,
        scenario: Dict[str, Any],
        ranges: Dict[str, Any],
        failures: List[Dict[str, Any]]
    ) -> str:
        """Build the prompt for LLM variant proposal."""
        prompt = f"""You are a game QA expert. Propose {self.max_proposals} unusual but valid test variants for this combat scenario.

Scenario: {scenario.get('id', 'unknown')}
Description: {scenario.get('description', 'No description')}

Valid parameter ranges:
"""
        for name, spec in ranges.items():
            prompt += f"  - {name}: {spec}\n"

        if failures:
            prompt += "\nRecent failures to investigate:\n"
            for f in failures[:3]:
                prompt += f"  - {f.get('expectation_id', 'unknown')}: {f.get('reason', '')}\n"

        prompt += """
Propose unusual combinations that might reveal edge cases. Stay within the specified ranges.
Return as JSON array of objects with parameter names and values.
"""
        return prompt

    def _call_llm(self, prompt: str) -> List[Dict[str, Any]]:
        """Call LLM API and parse response. Placeholder implementation."""
        # TODO: Implement actual API call
        return []

    def _validate_proposals(
        self,
        proposals: List[Dict[str, Any]],
        ranges: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """Validate that proposals stay within ranges."""
        valid = []
        for proposal in proposals:
            if self._is_valid_proposal(proposal, ranges):
                valid.append(proposal)
        return valid

    def _is_valid_proposal(
        self,
        proposal: Dict[str, Any],
        ranges: Dict[str, Any]
    ) -> bool:
        """Check if a proposal stays within defined ranges."""
        for name, value in proposal.items():
            if name not in ranges:
                return False

            range_spec = ranges[name]
            if isinstance(range_spec, list):
                # For numeric ranges, check bounds
                if len(range_spec) >= 2:
                    if isinstance(range_spec[0], (int, float)):
                        if not (range_spec[0] <= value <= range_spec[1]):
                            return False
                    else:
                        # String/enum list - must be in list
                        if value not in range_spec:
                            return False

        return True


def main():
    """CLI for testing the variant generator."""
    import argparse
    import json

    try:
        import yaml
    except ImportError:
        print("Error: PyYAML not installed. Run: pip install pyyaml")
        return 1

    parser = argparse.ArgumentParser(description="Variant Generator")
    parser.add_argument("scenario", help="Path to scenario YAML")
    parser.add_argument("--max", type=int, default=50, help="Max variants")
    args = parser.parse_args()

    with open(args.scenario, 'r') as f:
        scenario = yaml.safe_load(f)

    generator = VariantGenerator(max_variants=args.max)
    variants = generator.generate_variants(scenario)

    print(f"Scenario: {scenario.get('id', 'unknown')}")
    print(f"Generated {len(variants)} variants:")
    print()

    for v in variants:
        print(f"  {v['variant_id']}")
        for name, value in v.get('variant_values', {}).items():
            print(f"    {name}: {value}")
        print()

    return 0


if __name__ == "__main__":
    exit(main())
