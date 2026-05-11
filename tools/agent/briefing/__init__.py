"""
Combat Referee Briefing Generator

Generates morning briefing markdown from overnight test results.
3-minute coffee read format with regressions, findings, and stats.
"""

from .briefing_generator import BriefingGenerator, ShiftResults, ScenarioResult, Finding

__all__ = ["BriefingGenerator", "ShiftResults", "ScenarioResult", "Finding"]
