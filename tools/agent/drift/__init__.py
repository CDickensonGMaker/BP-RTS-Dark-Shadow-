"""
Drift Detection System for Combat Watchdog

Tracks metrics over time and detects statistical anomalies.
Layer 1 (Historian) appends data, Layer 2 (Detector) analyzes trends.
"""

from .metrics_historian import MetricsHistorian
from .drift_detector import DriftDetector

__all__ = ["MetricsHistorian", "DriftDetector"]
