"""
Combat Referee Expectation Checker

Validates recorded battle events against scenario expectations.
Pure Python, deterministic - no LLM calls.
"""

from .expectation_checker import ExpectationChecker

__all__ = ["ExpectationChecker"]
