# BP RTS Dark Shadows - Quick Start

## What's Been Created (Phases 0-2)

### Phase 0: Project Setup ✅
- `project.godot` - Godot 4.5 project file with autoloads configured
- `.gitignore` - Standard Godot gitignore
- `README.md` - Full project documentation
- Directory structure for battle_system, ui, camera, scenes, assets

### Phase 1: Core Regiment & Battlefield ✅
**Data Resources:**
- `battle_system/data/regiment_data.gd` - Regiment statistics and properties
- `battle_system/data/unit_type.gd` - Unit type enum (INFANTRY, CAVALRY, RANGED, etc.)
- `battle_system/data/order_type.gd` - Order enum (MOVE, ATTACK_MOVE, HOLD, etc.)

**Signals:**
- `battle_system/signals/battle_signals.gd` - All inter-system communication

**Nodes:**
- `battle_system/nodes/regiment_leader.gd` - Pathfinding anchor
- `battle_system/nodes/regiment.gd` - Core regiment with state machine
- `battle_system/nodes/regiment.tscn` - Regiment scene
- `battle_system/nodes/general.gd` - Hero unit with morale aura
- `battle_system/nodes/projectile.gd` - Ranged projectile
- `battle_system/nodes/projectile.tscn` - Projectile scene

**Camera:**
- `camera/rts_camera.gd` - RTS camera with pan, zoom, rotate
- `camera/rts_camera.tscn` - Camera scene

**Systems:**
- `battle_system/systems/selection_manager.gd` - Unit selection, drag select, control groups

**Test Scenes:**
- `scenes/test_battlefield.tscn` - Simple test terrain
- `scenes/battle_scene.tscn` - Full battle with player + enemy regiment

### Phase 2: Combat & Morale ✅
**Systems:**
- `battle_system/systems/morale_system.gd` - Morale calculations, routing, rallying
- `battle_system/systems/combat_manager.gd` - Melee and ranged combat resolution
- `battle_system/systems/battle_manager.gd` - Battle start/end conditions, win/loss detection

**Autoloads Configured in project.godot:**
- BattleSignals
- SelectionManager
- MoraleSystem
- CombatManager
- BattleManager

## How to Test

### In Godot Editor:
1. Open `project.godot` in Godot 4.5+
2. Open `scenes/battle_scene.tscn`
3. Click Play
4. **Controls:**
   - WASD / Arrow Keys: Pan camera
   - Mouse Wheel: Zoom
   - Middle Mouse + Drag: Rotate camera
   - Left Click: Select regiment
   - Right Click on terrain: Move selected regiment
   - Right Click on enemy: Attack move
   - Spacebar: Pause battle
   - + / -: Adjust battle speed

### Expected Behavior:
- Camera should pan, zoom, and rotate
- Player regiment (blue) and Enemy regiment (red) should appear
- Clicking on player regiment selects it
- Right-clicking on terrain moves the selected regiment
- When regiments touch, they should engage in combat
- Morale damage should cause routing at low morale

## Next Steps (Phase 3)

To complete the full battle system, add these UI components:

1. **Unit Card** (`ui/unit_card/unit_card.tscn` + `ui/unit_card/unit_card.gd`)
   - Shows regiment portrait, name, health, morale
   - Updates dynamically via BattleSignals

2. **Battle HUD** (`ui/battle_hud.tscn`)
   - Order buttons (Move, Attack, Hold, etc.)
   - Selected unit info panel
   - Battle speed controls

3. **Minimap** (`ui/minimap.tscn`)
   - Overview of battlefield
   - Show regiment positions

## Dark Omen Integration

The `tools/darkomen/` folder contains documentation for integrating the [darkomen](https://github.com/mgi388/darkomen) Rust library for extracting assets from Warhammer: Dark Omen.

**Use it if:** You have Dark Omen installed and want to use its 3D models, sprites, or other assets.

**Skip it if:** You're creating all new assets or using placeholder graphics for now.

## File Count

**Scripts Created: 14**
- 3 data resources
- 1 signals autoload
- 5 node scripts
- 4 system scripts
- 1 camera script
- 1 scene script

**Scenes Created: 4**
- 2 camera scenes
- 1 regiment scene
- 1 projectile scene
- 2 test scenes

**Total Files: 20+** (including config files)

## Reusability Note

The `battle_system/` folder is designed to be **completely reusable**. You can:
- Copy it to another Godot project
- Drop it in and it should work with no changes
- All dependencies are self-contained
- No hardcoded paths to this project
