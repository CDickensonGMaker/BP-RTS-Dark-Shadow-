"""
Combat Referee Variant Fuzzer

Generates test variants from scenario variant_ranges.
Deterministic permutation + optional LLM-proposed weirdness.
"""

from .variant_generator import VariantGenerator, LLMVariantProposer

__all__ = ["VariantGenerator", "LLMVariantProposer"]
