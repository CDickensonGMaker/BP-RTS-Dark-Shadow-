# BP RTS Dark Shadows

Total War-style RTS battle system in Godot 4.

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
