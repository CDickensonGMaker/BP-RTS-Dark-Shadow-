# BP RTS Dark Shadows

Total War-style RTS battle system in Godot 4.5+

**Project Location:** `C:\Users\caleb\BP_RTS_Dark_Shadows`

## Agent Guidelines

When working on this project:
- **Be conservative** - Don't make changes without explicit instruction
- **Reference the game bible** at `WIP/dark_shadows_bible.md` for design decisions
- **Use signal-based architecture** - No direct node references between systems
- **Follow battalion-based patterns** - Units are regiments, not individual soldiers

## Project Structure

```
battle_system/
├── nodes/           # Core gameplay nodes (Regiment, RegimentLeader)
├── systems/         # Managers (SelectionManager, CombatManager, DeploymentManager)
├── ai/              # AI systems (CommanderAI, GeneralAI, behavior trees)
├── terrain/         # Procedural terrain (DaggerfallTerrain, BattleTerrain)
├── units/           # Soldier visuals (SoldierFormation, SpriteFormation)
├── ui/              # HUD and overlays
└── signals/         # BattleSignals autoload
```

## Key Autoloads

- `BattleSignals` - Central signal bus
- `AIAutoload` - AI coordination and spatial queries
- `SelectionManager` - Unit selection via click/drag
- `DeploymentManager` - Pre-battle unit placement
- `FormationDragHandler` - Right-click move orders with formation drag

## Skills

- `/rts-unit-movement` - Fixes for unit movement, navigation, AI, selection issues

## Common Tasks

### Unit Movement Issues
See skill: `/rts-unit-movement`

Key fixes:
1. Terrain snapping after 0.6s delay
2. Direct movement fallback when nav mesh stuck
3. AI registration with AIAutoload
4. Area3D raycast with `collide_with_areas = true`

### Adding New Unit Types
1. Create RegimentData resource in `battle_system/data/`
2. Set unit stats, sprite atlas, abilities
3. Add to scene with Regiment script

### Sprite System
- Uses MultiMesh for batched rendering (SpriteFormation)
- Atlas textures in `assets/sprites/`
- Shader handles billboarding and animation

## Collision Layers
- Layer 1: Terrain
- Layer 2: Units (MeleeArea)

## UI/UX Rules

### Camera Behavior
- **Unit Card Click**: Clicking a unit card in the HUD centers the camera on that regiment
- Camera uses `center_on_regiment()` method in `battle_camera.gd`
- Camera is in the "battle_camera" group for easy lookup

### Unit Cards
- Display regiment stats, morale, ammo, veterancy
- Flash red when taking damage
- Pulse yellow when morale is wavering
- Gray out when routing or dead

## Spell System

Based on Catacombs of Gore patterns. Located in `battle_system/data/spell_data.gd` and `battle_system/systems/spell_caster.gd`.

### Target Types
- `PROJECTILE` - Fires projectile at target (can be homing)
- `AOE_POINT` - Area damage at target location
- `AOE_SELF` - Self-centered area (buffs/auras)
- `CONE` - Frontal cone attack
- `BEAM` - Continuous beam to target

### Damage Types
- `FIRE`, `ICE`, `LIGHTNING`, `HOLY`, `DARK`, `PHYSICAL`

### Key Files
- `spell_data.gd` - SpellData resource class
- `spell_caster.gd` - Handles spell execution
- `spell_manager.gd` - Per-regiment spell cooldowns
- `hazard_zone.gd` - Persistent AOE damage
- `spell_projectile.gd` - Spell projectile visuals
- `spell_beam.gd` - Beam effect with jitter
- `spell_effects.gd` - Visual effects by damage type

### Sample Spells
Located in `battle_system/data/spells/`:
- `fireball.tres` - AOE projectile
- `artillery_barrage.tres` - AOE_POINT with hazard
- `cavalry_charge_aura.tres` - AOE_SELF buff
- `ice_storm.tres` - AOE with slow hazard
- `lightning_bolt.tres` - Single-target beam
- `dragon_breath.tres` - Cone attack
- `healing_light.tres` - Healing aura

### Usage
```gdscript
# Add spell to regiment
var fireball = preload("res://battle_system/data/spells/fireball.tres")
regiment.add_spell(fireball)

# Cast spell at target
regiment.cast_spell(fireball, target_position)
# Or by ID
regiment.cast_spell_by_id("fireball", target_position)

# Check if ready
if regiment.can_cast_spell(fireball, target_position):
    regiment.cast_spell(fireball, target_position)
```

## Combat System (TotalWarSimulator-style)

### Hit Chance Formula
```
hit_chance = clamp(35 + (attack - defense), 8, 90)
```

### Fatigue States
| State | Stamina | Attack | Defense | Speed |
|-------|---------|--------|---------|-------|
| Fresh | >70% | 100% | 100% | 100% |
| Winded | 40-70% | 95% | 95% | 95% |
| Tired | 10-40% | 90% | 90% | 85% |
| Exhausted | <10% | 80% | 85% | 50% |

### Charge Mechanics
- Requires minimum 10 units distance to apply charge bonus
- Impact damage = mass × speed × 2
- 70% of impact damage is armor-piercing
- Bracing only negates **frontal** charges
- Charge bonus decays linearly over 10 seconds

### Flanking
- Frontal: 1.0x damage
- Flank (45-135°): 1.5x damage
- Rear (135-180°): 2.0x damage

## Formation System

### Formations Available
| Formation | Speed | Attack | Defense | Notes |
|-----------|-------|--------|---------|-------|
| Line | 1.0x | 1.0x | 1.0x | Default |
| Column | 1.2x | 0.6x | 0.7x | Fast march |
| Wedge | 1.1x | 1.3x | 0.8x | Cavalry only |
| Square | 0.7x | 0.8x | 1.3x | Anti-cavalry |
| Loose | 1.15x | 0.7x | 0.6x | Archers |
| Shield Wall | 0.5x | 0.8x | 1.5x | Heavy infantry |
| Schiltron | 0.0x | 0.6x | 1.4x | Pikemen only |

### Formation Transitions
- Transitioning reduces combat effectiveness (50% attack, 60% defense)
- Transition time varies by formation complexity and unit type
- Cavalry reforms 40% faster than infantry

## Key Documentation

- `WIP/dark_shadows_bible.md` - Complete game design (1000+ lines)
- `WIP/implementation_status.md` - Progress tracking
- `WIP/grand_campaign_map_plan.md` - Campaign roadmap

## Research References

These open-source projects inform the architecture:
- **TotalWarSimulator** - Combat formulas, HTN AI
- **Recoil Engine** - Large-scale RTS architecture
- **Beyond All Reason** - Unit definitions, command systems
- **RTSNavigationLib** - Flow fields, formation slots

## Test Scene

Run `scenes/battle_scene.tscn` for the main battle test.

**Controls:**
- WASD/Arrows: Pan camera
- Mouse Wheel: Zoom
- Middle Mouse: Rotate
- Left Click: Select regiment
- Right Click Terrain: Move
- Right Click Enemy: Attack move
- Spacebar: Pause
- +/-: Speed control
- Ctrl+1-9: Save group
- 1-9: Recall group
- F1-F4: Formation hotkeys
- Z/X/C/V: Stance hotkeys
