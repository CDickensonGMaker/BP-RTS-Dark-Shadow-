# Combat Watchdog

Unified combat testing system for BP RTS Dark Shadows.

Merges three perception systems into one:
- **Drift Detector** - Catches "small problems that develop over time"
- **Snapshot Analyzer** - Finds in-the-moment bugs from tonight's stress tests
- **Scenario Referee** - Named regression checks with explicit expectations

## Quick Start

```bash
# Run 25 stress battles (quick test)
python tools/agent/run_25_battles.py

# Full watchdog run (1 hour)
python tools/agent/combat_watchdog.py --hours 1 --battles 50

# Scenarios only
python tools/agent/combat_watchdog.py --scenarios-only

# Stress tests only
python tools/agent/combat_watchdog.py --stress-only --battles 100
```

## Architecture

### 5-Layer System

```
Layer 1: Metrics Historian
         └─> Appends one CSV row at end of every run
             Tracks: faction win rates, unit win rates, system metrics
             File: drift/metrics_history.csv

Layer 2: Drift Detector
         └─> Reads CSV, computes rolling 7-day baseline
             Flags metrics outside ±2σ
             Only activates with ≥7 historical rows

Layer 3: Snapshot Analyzer
         └─> 15+ checks on tonight's results
             Silent charges, missing flanks, AI flip-flopping, balance breaks
             Runs on stress test output

Layer 4: Scenario Referee
         └─> YAML scenarios with positive/negative expectations
             Deterministic Python checker (no LLM)
             Variant generation via Cartesian product

Layer 5: Briefing Aggregator
         └─> Merges all three finding streams
             Deduplicates overlapping findings
             Ranks by severity
             Writes one morning briefing
```

### Findings Schema

All findings use this unified schema:

```json
{
  "id": "F-2026-05-08-001",
  "source": "drift" | "snapshot" | "regression",
  "sources": ["drift", "snapshot"],  // When multiple sources agree
  "category": "bug" | "balance" | "ai" | "drift" | "regression",
  "severity": "critical" | "high" | "medium" | "low",
  "title": "<short headline>",
  "evidence": { ... source-specific structured data ... },
  "code_hints": [ ... likely files/methods to investigate ... ],
  "first_seen": "2026-05-08",
  "git_context": { "last_stable_date": "...", "commits_since_stable": [...] }
}
```

## Directory Structure

```
tools/agent/
├── combat_watchdog.py         # Main entry point (merged system)
├── run_25_battles.py          # Quick 25-battle stress test
├── battle_daemon.py           # Legacy daemon (still works, but use watchdog)
├── night_shift.py             # Legacy referee (still works, but use watchdog)
│
├── agent_orchestrator.py      # Launches Godot, reads results
├── agent_test_runner.gd       # GDScript test harness
│
├── scenarios/                 # YAML scenario definitions
│   ├── _template.yaml
│   ├── charge_deals_impact_damage.yaml
│   └── ...
│
├── checker/                   # Layer 4: Expectation validation
│   └── expectation_checker.py
│
├── fuzzer/                    # Variant generation
│   └── variant_generator.py
│
├── drift/                     # Layers 1-2: Historical tracking
│   ├── metrics_historian.py   # Layer 1: Append CSV rows
│   ├── drift_detector.py      # Layer 2: Detect anomalies
│   └── metrics_history.csv    # Accumulates over time
│
├── briefing/                  # Layers 5: Report generation
│   ├── aggregator.py          # Merges all finding streams
│   └── briefing_generator.py  # Legacy briefing generator
│
├── briefings/                 # Generated morning briefings
│   └── YYYY-MM-DD.md
│
├── findings/                  # Individual finding records
│   └── YYYY-MM-DD/
│       └── F-NNN.json
│
└── shift_orders/              # Daily configuration (optional)
    └── YYYY-MM-DD.md
```

## Morning Briefing Structure

The briefing is ruthlessly short - one screen, scannable in 3 minutes:

1. **Drift Alarms** (top) - New problems with timestamps and likely commits
2. **Critical Regressions** - Named scenarios that broke
3. **Tonight's Issues** - High-severity snapshot findings
4. **Other Findings** - Medium/low collapsed into a link
5. **Stats** - Runtime, battle counts, finding counts

## Writing Scenarios

See `scenarios/_template.yaml` for the full format.

```yaml
id: cavalry_charge_deals_damage
description: |
  Cavalry charging infantry should deal impact damage.
  This tests the charge_impact signal fires and damage applies.

setup:
  duration_sec: 10.0
  player:
    - unit: reik
      count: 15
      pos: [-20, 0, 0]
      facing: [1, 0, 0]
      order: charge
      target: enemy[0]
  enemy:
    - unit: orcboyz
      count: 20
      pos: [20, 0, 0]
      order: hold

expectations:
  - id: charge_impact_fires
    within_sec: 5.0
    event:
      type: charge_impact

  - id: damage_dealt
    after: charge_impact_fires
    within_sec: 1.0
    event:
      type: regiment_attacked
      filter:
        damage_min: 1

negative_expectations:
  - id: no_friendly_fire
    never:
      type: regiment_attacked
      filter:
        attacker_contains: reik
        defender_contains: reik

variant_ranges:
  enemy_count: [10, 50, {"step": 10}]
  enemy_state_pre_charge: ["hold", "march", "routing"]
```

## Dependencies

```bash
pip install pyyaml jinja2
```

Optional (for LLM-proposed variants):
```bash
pip install anthropic
```

## Troubleshooting

### "Godot executable not found"
The watchdog defaults to:
`C:\Users\caleb\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe`

Update `GODOT_EXECUTABLE` in `combat_watchdog.py` if your Godot is elsewhere.

### "No drift findings"
Drift detection requires ≥7 historical rows in `drift/metrics_history.csv`.
Run the watchdog daily and drift detection activates after a week.

### "No scenarios found"
Ensure `scenarios/` directory exists with `.yaml` files not starting with `_`.

### "Expectation always fails"
Debug with the CLI checker:
```bash
python -m checker.expectation_checker scenarios/my_scenario.yaml results.json
```
