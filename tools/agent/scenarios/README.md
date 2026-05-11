# Combat Referee Scenarios

This directory contains YAML scenario definitions for the Combat Referee Agent.
Each scenario defines a specific combat situation to test, along with expectations
about what events should (and shouldn't) occur.

## Quick Start

1. Copy `_template.yaml` to create a new scenario
2. Fill in the setup (units, positions, orders)
3. Define expectations (events that MUST happen)
4. Define negative expectations (events that must NOT happen)
5. Optionally add variant_ranges for fuzz testing

## Scenario Format

```yaml
id: unique_scenario_id
description: |
  What this scenario tests and why it matters.

tags: [charge, melee, regression]
severity_if_failing: high  # critical, high, medium, low
last_verified_pass: 2026-05-08

setup:
  duration_sec: 30.0
  difficulty: normal
  weather: clear
  player:
    - unit: unit_id
      count: 20
      pos: [x, y, z]
      facing: [x, y, z]
      order: charge|hold|march
      target: enemy[0]
  enemy:
    - unit: unit_id
      count: 20
      pos: [x, y, z]
      facing: [x, y, z]
      order: hold

expectations:
  - id: expectation_id
    within_sec: 5.0
    event:
      type: signal_name
      filter:
        field_name: value

negative_expectations:
  - id: no_bad_event
    never:
      type: signal_name
      filter:
        field: value

variant_ranges:
  enemy_count: [10, 50, step: 10]
```

## Available BattleSignals

These are the signal types you can filter for in expectations:

| Signal | Description | Key Fields |
|--------|-------------|------------|
| `battle_started` | Battle begins | - |
| `battle_ended` | Battle concludes | winner |
| `regiment_attacked` | Damage dealt | attacker, defender, damage |
| `regiment_dead` | Unit wiped out | regiment, is_player |
| `regiment_routing` | Unit breaks | regiment |
| `regiment_rallied` | Unit recovers | regiment |
| `charge_impact` | Charge connects | charger, target, was_braced |
| `unit_flanked` | Flank attack | flanked, flanker, is_rear |
| `morale_changed` | Morale shifts | regiment, old_value, new_value |
| `projectile_fired` | Ranged attack | attacker, target |
| `spell_cast` | Spell used | caster, spell_id, target_pos |

## Existing Scenarios

| Scenario | Tests | Severity |
|----------|-------|----------|
| `charge_deals_impact_damage` | Cavalry charge impact mechanics | high |
| `flank_persists_during_engagement` | Flanking morale penalties | high |
| `spear_vs_cavalry_brace` | Brace negates charge, spear bonus | high |

## Maintenance

- Update `last_verified_pass` when scenarios pass after code changes
- Review scenarios older than 30 days - they may be stale
- Keep scenario count manageable - 30 well-maintained > 100 stale
- Run `night_shift.py` to execute all scenarios overnight

## Filter Syntax

Filters in expectations support:
- `field: value` - Exact match
- `field_contains: substring` - Case-insensitive substring
- `field_min: N` - Minimum value (inclusive)
- `field_max: N` - Maximum value (inclusive)

All filters are AND'd together.

## Variant Ranges

Variant ranges generate test permutations automatically:
- `[10, 50, step: 10]` generates `[10, 20, 30, 40, 50]`
- `[hold, march, routing]` cycles through enum values
- Cartesian product of all ranges (capped at 50 variants)

Same expectations apply to all variants - if charge should work at
`enemy_count=10`, it should also work at `enemy_count=50`.
