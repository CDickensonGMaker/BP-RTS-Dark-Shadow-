# BP RTS Dark Shadows

A 2.5D isometric RTS game in the spirit of Warhammer: Shadow of the Horned Rat, built with Godot 4.5.

## Features

- Total War-style regiment-based combat
- 2.5D isometric camera with free pan/zoom/rotate
- Morale system with routing and rallying
- Control group management
- Battle speed controls with pause
- Modular, reusable battle_system folder

## Quick Start

1. Open `project.godot` in Godot 4.5+
2. Run `battle_scene.tscn` to test
3. Use WASD or arrow keys to pan camera
4. Mouse wheel to zoom
5. Left-click to select, drag to select multiple

## Project Structure

```
battle_system/    # Reusable battle system (drop into any project)
  data/           # Resources (RegimentData, UnitType, OrderType)
  nodes/          # Node scripts (Regiment, General, Projectile)
  systems/        # Autoloads (SelectionManager, MoraleSystem, etc.)
  signals/        # BattleSignals autoload
ui/              # User interface
camera/          # RTS camera
scenes/          # Game scenes
assets/          # Game assets (sprites, textures, models, audio)
tools/           # External tools (darkomen Rust library)
addons/          # Godot plugins
```

## Controls

| Action | Key |
|--------|-----|
| Pan Camera | WASD / Arrow Keys / Edge Scroll |
| Zoom | Mouse Wheel |
| Rotate | Middle Mouse + Drag |
| Select | Left Click |
| Drag Select | Left Click + Drag |
| Move Order | Right Click (terrain) |
| Attack Order | Right Click (enemy) |
| Save Group | Ctrl + 0-9 |
| Recall Group | 0-9 |
| Pause | Spacebar |
| Speed Up | + |
| Speed Down | - |

## Battle System Architecture

All systems communicate via `BattleSignals` autoload. No direct node references.

### Core Concepts

- **Regiment**: A group of soldiers (infantry, cavalry, ranged)
- **General**: Hero unit with morale aura
- **Order**: Command given to a regiment (Move, Attack, Hold, etc.)
- **Morale**: Affects routing and combat effectiveness

### Data Flow

```
SelectionManager -> Regiment (via signals)
MoraleSystem -> Regiment (via signals)  
CombatManager -> Regiment (via signals)
BattleManager -> All (via signals)
```

## Requirements

- Godot 4.5+
- Optional: Rust + darkomen library for Dark Omen asset import

## License

MIT License - Feel free to use this in your own projects.
