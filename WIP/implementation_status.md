# Dark Shadows — Implementation Status

Comparing the Game Bible (§1-19) against current codebase.

**Last Updated:** Session with sprite system fixes

---

## Milestone Progress Overview

| Milestone | Bible Status | Current Status |
|-----------|--------------|----------------|
| M1: Two units can fight | ✅ Complete | ✅ **DONE** |
| M2: Formations and selection | ✅ Complete | 🟡 **PARTIAL** |
| M3: Real morale and AI | In Progress | 🟡 **PARTIAL** |
| M4: Deployment and full battle loop | Not Started | 🟡 **PARTIAL** |
| M5: Meta layer skeleton | Not Started | 📋 **PLANNED** |
| M6: Sieges | Not Started | ❌ **NOT STARTED** |
| M7: Special units, polish | Not Started | 🟡 **PARTIAL** |
| M8: Content and balance | Not Started | ❌ **NOT STARTED** |

---

## Detailed Section Status

### §1. Game Pillars and Scope
| Item | Status | Notes |
|------|--------|-------|
| Pillar 1: Tactical positioning | ✅ | Core design in place |
| Pillar 2: Battles tell stories | 🟡 | Need veterancy persistence, casualty tracking |
| Pillar 3: 90s readability | 🟡 | Sprite system WIP, need cleaner silhouettes |

### §2. Core Battle Loop
| Item | Status | Files |
|------|--------|-------|
| Pre-battle briefing | ❌ | Not implemented |
| Deployment phase | ✅ | `deployment_manager.gd` |
| Battle proper | ✅ | `battle_manager.gd` |
| Win conditions | 🟡 | Basic check exists |
| Post-battle resolution | ❌ | Not implemented |
| Casualty calculation | ❌ | Not implemented |

### §3. Unit System
| Item | Status | Files |
|------|--------|-------|
| Regiment node | ✅ | `regiment.gd` |
| Unit categories | ✅ | `unit_type.gd` |
| Unit stats | ✅ | `regiment_data.gd` |
| Soldier count tracking | ✅ | `regiment.gd` |
| Veterancy system | ✅ | `veterancy_system.gd` |
| Stamina system | ✅ | `stamina_system.gd` |
| Visual soldiers (3D blocks) | ✅ | `soldier_formation.gd`, `soldier_block.gd` |
| Visual soldiers (2D sprites) | ✅ | `sprite_formation.gd` - atlas loading fixed |

### §4. Selection and Control
| Item | Status | Files |
|------|--------|-------|
| Single-click select | 🟡 | `selection_manager.gd` - raycast issues |
| Drag-select box | ✅ | `selection_manager.gd`, `selection_box_overlay.gd` |
| Double-click same type | ✅ | `selection_manager.gd` |
| Shift+click add | ✅ | `selection_manager.gd` |
| Ctrl+click toggle | ✅ | `selection_manager.gd` |
| Right-click move | ✅ | `formation_drag_handler.gd` - FIXED |
| Right-click attack | 🟡 | Basic, needs polish |

### §5. Formations
| Item | Status | Files |
|------|--------|-------|
| Line formation | ✅ | `formation_type.gd`, `soldier_formation.gd` |
| Column formation | ✅ | `formation_type.gd` |
| Square formation | ✅ | `formation_type.gd` |
| Wedge formation | ✅ | `formation_type.gd` |
| Drag-to-stretch | ✅ | `formation_drag_handler.gd` |
| Formation transitions | 🟡 | Basic, no transition penalty |
| Shield Wall | ❌ | Not implemented |
| Schiltron | ❌ | Not implemented |

### §6. Pathfinding and Movement
| Item | Status | Files |
|------|--------|-------|
| Two-tier pathfinding | ✅ | `regiment_leader.gd` (anchor) + `soldier_formation.gd` (slots) |
| NavigationServer3D | ✅ | `daggerfall_terrain.gd` bakes nav mesh |
| Walk/Run/Charge speeds | 🟡 | Basic implementation |
| Stamina drain | ✅ | `stamina_system.gd` |
| Direct movement fallback | ✅ | `regiment_leader.gd` - FIXED |
| Terrain height following | ✅ | `regiment_leader.gd`, `regiment.gd` |

### §7. Combat and Morale
| Item | Status | Files |
|------|--------|-------|
| Melee combat | ✅ | `combat_manager.gd` |
| Ranged combat | ✅ | `combat_manager.gd`, `projectile.gd` |
| Per-soldier morale | ✅ | `morale_component.gd`, `unit_morale.gd` |
| Unit morale states | ✅ | Steady/Wavering/Shaken/Broken |
| Routing | ✅ | `regiment.gd` State.ROUTING |
| Rallying | ✅ | `regiment.gd` State.RALLYING |
| Morale events | ✅ | `morale_event.gd`, `morale_constants.gd` |
| Combat effectiveness multiplier | 🟡 | Basic |

### §8. Enemy AI
| Item | Status | Files |
|------|--------|-------|
| General AI (strategic) | ✅ | `general_ai.gd`, `battlefield_analysis.gd` |
| Strategic plays | ✅ | `play_all_out_assault.gd`, `play_defensive_line.gd`, `play_pin_and_flank.gd` |
| Commander AI (tactical) | ✅ | `commander_ai.gd` |
| Behavior tree | ✅ | `bt_node.gd`, `bt_selector.gd`, `bt_sequence.gd`, `bt_condition.gd` |
| Target selector | ✅ | `target_selector.gd` |
| AI tasks | ✅ | `task_acquire_target.gd`, `task_move_to_position.gd`, `task_engage_melee.gd`, `task_fire_ranged.gd` |
| Spatial hash queries | ✅ | `spatial_hash.gd` |
| AI personalities | ✅ | `ai_personality.gd` |
| Difficulty scaling | ❌ | Not implemented |

### §9. Deployment Phase
| Item | Status | Files |
|------|--------|-------|
| Deployment manager | ✅ | `deployment_manager.gd` |
| Deployment zones | 🟡 | Basic |
| Unit dragging | ✅ | `deployment_manager.gd` |
| Begin Battle button | 🟡 | In HUD |
| AI pre-deployment | ❌ | Not implemented |

### §10. Sieges
| Item | Status | Files |
|------|--------|-------|
| Siege manager | 🟡 | `siege_manager.gd` - skeleton only |
| Walls with HP | ❌ | Not implemented |
| Siege equipment | ❌ | Not implemented |
| Multi-layer navmesh | ❌ | Not implemented |
| Siege win conditions | ❌ | Not implemented |

### §11. Special Units and Abilities
| Item | Status | Files |
|------|--------|-------|
| Ability system | ✅ | `ability_manager.gd`, `ability_type.gd` |
| Volley fire | ✅ | In ability_type.gd |
| Brace | ✅ | In ability_type.gd |
| War cry | ✅ | In ability_type.gd |
| Charge ability | ✅ | In ability_type.gd |
| General/Hero system | 🟡 | `general.gd` - basic |

### §12. Stances
| Item | Status | Files |
|------|--------|-------|
| Aggressive stance | ✅ | `stance_type.gd` |
| Defensive stance | ✅ | `stance_type.gd` |
| Hold Ground stance | ✅ | `stance_type.gd` |
| Skirmish stance | ✅ | `stance_type.gd` |
| Guard mode | ✅ | `selection_manager.gd`, `regiment.gd` |
| Hotkeys (Z/X/C/V) | ✅ | `selection_manager.gd` |

### §13. Control Groups
| Item | Status | Files |
|------|--------|-------|
| Save groups (Ctrl+0-9) | ✅ | `selection_manager.gd` |
| Recall groups (0-9) | ✅ | `selection_manager.gd` |
| Add to selection (Shift+0-9) | ✅ | `selection_manager.gd` |
| Group UI bar | ✅ | `control_group_bar.gd` |
| Double-tap to center | ❌ | Not implemented |

### §14. Meta Layer
| Item | Status | Files |
|------|--------|-------|
| Campaign map | 📋 | `grand_campaign_map_plan.md` - PLANNED |
| Economy system | ❌ | Not implemented |
| Recruitment | ❌ | Not implemented |
| Army movement | ❌ | Not implemented |
| Save/Load | ❌ | Not implemented |

### §15. Camera and UI
| Item | Status | Files |
|------|--------|-------|
| RTS camera | ✅ | `battle_camera.gd` |
| WASD pan | ✅ | Working |
| Mouse wheel zoom | ✅ | Working |
| Camera rotation | ✅ | Working |
| Battle HUD | ✅ | `battle_hud.gd` |
| Unit cards | ✅ | `unit_card.gd` |
| Minimap | ✅ | `battle_minimap.gd` |
| Ability panel | 🟡 | Basic |

### §16. Audio
| Item | Status | Files |
|------|--------|-------|
| Audio manager | ✅ | `audio_manager.gd` |
| Music layers | ❌ | Not implemented |
| Unit chatter | ❌ | Not implemented |
| Combat SFX | 🟡 | Basic |
| UI sounds | 🟡 | Basic |

### §17. Save System
| Item | Status | Notes |
|------|--------|-------|
| Save/Load | ❌ | Not implemented |
| Auto-save | ❌ | Not implemented |
| Versioned saves | ❌ | Not implemented |

### §18. Technical Architecture
| Item | Status | Notes |
|------|--------|-------|
| Godot 4.x | ✅ | Using Godot 4.5+ |
| GDScript | ✅ | All game logic |
| C# for perf | ❌ | Not needed yet |
| Spatial hash | ✅ | `spatial_hash.gd` |
| Tick rates | ✅ | AIAutoload handles staggered ticks |
| Two-tier pathfinding | ✅ | RegimentLeader + soldiers |

---

## Current Issues (from testing session)

### Fixed This Session ✅
1. **Unit movement not working** - Added direct movement fallback
2. **Enemy AI not moving** - Fixed AIAutoload registration, deployment phase check
3. **Terrain snapping** - Units now snap to terrain height
4. **Sprite atlas not loading** - Fixed UnitCatalog class_name/autoload conflict
5. **Atlas path incorrect** - Fixed path from `assets/sprites/` to `assets/sprites/units/`
6. **PNG import files missing** - Editor reimport generated .import files

### Still Needs Work 🔧
1. **Unit selection via clicking** - Raycast detection unreliable
   - Added screen-space fallback but click positions still far from unit positions
   - May need camera/projection investigation

2. **Navigation mesh** - Returns current position as next waypoint
   - Direct movement fallback masks this issue
   - Should investigate proper nav mesh baking

---

## Recommended Next Steps

### Immediate (fix current issues)
1. Fix unit click selection (investigate camera projection)
2. Test combat engagement when units meet
3. Verify sprite billboard orientation matches unit facing

### Short-term (complete M2-M3)
1. Formation transition penalties
2. Charge mechanics for cavalry
3. Difficulty scaling for AI
4. Pre-battle briefing screen

### Medium-term (M4-M5)
1. Post-battle resolution screen
2. Campaign map MVP (per `grand_campaign_map_plan.md`)
3. Save/Load system

---

## Total War Architecture Insights

From research on Total War AI systems:

1. **MCTS (Monte Carlo Tree Search)** - Used in Rome II for strategic decisions
   - Explores multiple possibilities, focuses on promising branches
   - Could enhance GeneralAI play selection

2. **Reactive Planning** - Behavior trees work well for tactical decisions
   - Current CommanderAI uses this correctly

3. **Army Composition Rules** - AI should follow soft rules:
   - 6-8 front line infantry
   - 6-8 ranged/artillery
   - 4-6 cavalry
   - 2-4 monsters/special

4. **Difficulty via Smarts, Not Stats** - Bible aligns with this
   - Reaction time differences
   - Play selection depth

Sources:
- [The Road To War | The AI of Total War (Part 1)](https://www.gamedeveloper.com/programming/the-road-to-war-the-ai-of-total-war-part-1-)
- [Revolutionary Warfare | The AI of Total War (Part 3)](https://www.gamedeveloper.com/design/revolutionary-warfare-the-ai-of-total-war-part-3-)
- [TWR2 Campaign AI: MCTS Algorithm](https://www.twcenter.net/threads/twr2-campaign-ai-mcts-algorythm.662751/)
