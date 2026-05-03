# Grand Campaign Map - Implementation Plan

## Overview
Add a mercenary campaign layer to Dark Shadows RTS inspired by Shadow of the Horned Rat and Total War. Features a 2D parchment-style world map with free-roaming battalions, contract-based missions, enemy armies, and persistent company management.

**Project:** `C:\Users\caleb\BP_RTS_Dark_Shadows`

---

## Core Design Decisions
- **Map Style:** 2D parchment map (flat illustrated)
- **Time System:** Free movement within turn, End Turn button pays upkeep and refreshes movement
- **Battle Triggers:** Contracts AND enemy armies moving on map (contact = battle)
- **Map Size:** 5-8 regions for MVP
- **Max Battalions:** Up to 5 player-controlled mercenary battalions

---

## New Folder Structure

```
campaign_system/
    signals/
        campaign_signals.gd           # Event bus for campaign
    data/
        region_data.gd                 # Region resource class
        contract_data.gd               # Contract/mission resource
        battalion_data.gd              # Persistent battalion state
        campaign_save_data.gd          # Full save game structure
        regions/                       # .tres files (5-8 regions)
        contracts/                     # .tres contract templates
    systems/
        campaign_manager.gd            # Core campaign state (autoload)
        economy_manager.gd             # Gold, upkeep (autoload)
        contract_manager.gd            # Available contracts
        battle_transition.gd           # Campaign <-> Battle bridge (autoload)
        enemy_army_ai.gd               # Simple enemy movement AI
    map/
        campaign_map.gd                # Main map controller
        campaign_camera.gd             # 2D camera with pan/zoom
        region_zone.gd                 # Clickable region (Area2D)
        map_battalion.gd               # Player battalion token
        enemy_army.gd                  # Enemy army token
    ui/
        campaign_hud.gd                # Top-level UI
        battalion_panel.gd             # Selected battalion info
        contract_list.gd               # Available contracts
        contract_details.gd            # Accept/decline panel
        economy_bar.gd                 # Gold/upkeep display
        battle_result_panel.gd         # Post-battle summary
scenes/
    campaign_map.tscn                  # Main campaign scene
```

---

## Data Resources

### RegionData
```gdscript
@export var region_id: String
@export var region_name: String
@export var map_position: Vector2
@export var polygon_points: PackedVector2Array  # Boundary for click detection
@export var terrain_type: TerrainType  # PLAINS, FOREST, HILLS, etc.
@export var threat_level: int  # 1-5, affects enemy strength
@export var is_safe_zone: bool  # Towns - no random battles
```

### ContractData
```gdscript
@export var contract_id: String
@export var title: String
@export var description: String
@export var required_region: String
@export var gold_reward: int
@export var difficulty: int  # 1-5 stars
@export var enemy_regiments: Array[RegimentData]
```

### BattalionData
```gdscript
@export var battalion_id: String
@export var battalion_name: String
@export var regiments: Array[RegimentData]  # Max 6 per battalion
@export var map_position: Vector2
@export var movement_points: float
@export var max_movement_points: float = 100.0
```

### CampaignSaveData
```gdscript
@export var company_name: String
@export var current_gold: int
@export var turn_number: int
@export var battalions: Array[BattalionData]  # 1-5 battalions
@export var completed_contracts: Array[String]
@export var enemy_armies: Array[Dictionary]  # Position + composition
```

---

## New Autoloads (add to project.godot)

| Autoload | Purpose |
|----------|---------|
| CampaignSignals | Signal bus for all campaign events |
| CampaignManager | Core state, turn management, save data |
| EconomyManager | Gold tracking, upkeep calculation |
| BattleTransition | Scene switching between campaign and battle |

---

## Scene Hierarchy: campaign_map.tscn

```
CampaignMap (Node2D)
├── CampaignCamera (Camera2D)
├── MapBackground (Sprite2D)          # Parchment texture
├── RegionsContainer (Node2D)
│   ├── RegionZone_Blackwood (Area2D + Polygon2D)
│   ├── RegionZone_Ironhold (Area2D + Polygon2D)
│   └── ... (5-8 total)
├── ArmiesContainer (Node2D)
│   ├── MapBattalion_1 (Node2D)       # Player token
│   ├── EnemyArmy_1 (Node2D)          # Enemy token
│   └── ...
├── PathPreview (Line2D)              # Movement path preview
└── CampaignHUD (CanvasLayer)
    ├── TopBar (HBoxContainer)        # Gold, upkeep, turn number
    ├── BattalionPanel (Panel)        # Selected battalion info
    ├── ContractList (Panel)          # Right side contracts
    └── EndTurnButton (Button)
```

---

## Integration Points

### 1. Modify battle_scene.gd
Add check for campaign-provided regiments at start:
```gdscript
func _ready():
    if BattleTransition and BattleTransition.battle_data:
        _setup_from_campaign()  # Spawn regiments from campaign data
    else:
        # Existing standalone behavior
        _gather_regiments()
```

### 2. Modify battle_manager.gd
Return results to campaign after battle ends:
```gdscript
func _end_battle(winner: String):
    # ... existing code ...
    if BattleTransition and BattleTransition.battle_data:
        BattleTransition.return_to_campaign(result)
```

### 3. Extend RegimentData
Add campaign metadata (or use set_meta):
- `upkeep_cost: int` - gold per turn
- `veterancy_xp: int` - persisted between battles

---

## Phased Implementation

### Phase 1: MVP Loop (Start Here)
**Goal:** One battalion, one region, one contract, battle and back

1. Create `campaign_system/` folder structure
2. Create `CampaignSignals` autoload (copy pattern from BattleSignals)
3. Create `BattalionData` resource class
4. Create `CampaignManager` autoload with basic state
5. Create `BattleTransition` autoload for scene switching
6. Create simple `campaign_map.tscn` with:
   - Static parchment background (placeholder)
   - One draggable battalion token
   - Basic HUD with gold display and End Turn button
7. Modify `battle_scene.gd` to accept campaign regiments
8. Modify `battle_manager.gd` to call `BattleTransition.return_to_campaign()`
9. Create one hardcoded test contract

**Test:** Start campaign -> Move battalion -> Accept contract -> Fight battle -> Return with casualties applied

### Phase 2: Economy + Contracts
1. Create `EconomyManager` autoload
2. Create `ContractData` resource class
3. Create `ContractManager` with contract generation
4. Build contract list UI panel
5. Build contract details accept/decline panel
6. Implement upkeep deduction on End Turn
7. Add gold reward after battle victory
8. Create 5-8 contract templates

### Phase 3: Full Map + Enemy Armies
1. Create `RegionData` resource class
2. Create 5-8 region .tres files
3. Build `RegionZone` Area2D nodes with click detection
4. Add region highlighting and tooltips
5. Create `EnemyArmy` tokens on map
6. Implement simple enemy movement AI (patrol, seek player)
7. Battle triggers on army contact
8. Support multiple battalions (up to 5)

### Phase 4: Mercenary Management
1. Roster panel - view all regiments across battalions
2. Hire mercenaries from available pool
3. Dismiss regiments to reduce upkeep
4. Replenish casualties (gold cost)
5. Veterancy persistence between battles

### Phase 5: Polish
1. Proper parchment map art
2. Battalion tokens with banners
3. UI animations and sounds
4. Save/Load system
5. More contracts and story missions

---

## Key Files to Modify

| File | Change |
|------|--------|
| `scenes/battle_scene.gd` | Add `_setup_from_campaign()` path |
| `battle_system/systems/battle_manager.gd` | Call `BattleTransition.return_to_campaign()` |
| `project.godot` | Register 4 new autoloads |
| `battle_system/data/regiment_data.gd` | Add `upkeep_cost` export (optional) |

---

## Verification Plan

1. **Phase 1 Test:**
   - Run campaign_map.tscn
   - Drag battalion token around map
   - Click accept on hardcoded contract
   - Verify battle loads with correct regiments
   - Win/lose battle
   - Verify return to campaign with casualty count updated

2. **Economy Test:**
   - Start with 2000 gold
   - End turn, verify upkeep deducted
   - Complete contract, verify gold rewarded
   - Run out of gold, verify desertion warning

3. **Enemy Army Test:**
   - Enemy tokens patrol on map
   - Move player battalion into enemy
   - Battle triggers automatically
   - Victory removes enemy from map

---

## UI Color Scheme (Match Existing)

```gdscript
const COLOR_PANEL_BG = Color(0.08, 0.06, 0.05, 0.92)
const COLOR_BORDER = Color(0.6, 0.5, 0.3, 1.0)
const COLOR_GOLD = Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT = Color(0.95, 0.92, 0.85, 1.0)
```

---

## Estimated Scope

| Phase | New Files | Lines of Code (est.) |
|-------|-----------|---------------------|
| Phase 1 MVP | ~12 files | ~800 |
| Phase 2 Economy | ~6 files | ~500 |
| Phase 3 Full Map | ~8 files | ~600 |
| Phase 4 Management | ~4 files | ~400 |
| Phase 5 Polish | Variable | Variable |

**MVP is playable after Phase 1** - recommend implementing phases sequentially and testing after each.
