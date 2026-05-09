# UI System Audit - BP RTS Dark Shadows

## Signal Connections

### BattleHUD (battle_system/ui/battle_hud.gd)

#### Connects TO:
| Signal | Source | Line | Handler |
|--------|--------|------|---------|
| `regiment_selected` | BattleSignals | 999-1000 | `_on_regiment_selected` |
| `regiment_dead` | BattleSignals | 1001-1002 | `_on_regiment_dead` |
| `deployment_ended` | BattleSignals | 1003-1004 | `_on_deployment_ended` |
| `battle_started` | BattleSignals | 1005-1006 | `_on_battle_started` |
| `unit_disengage_failed` | BattleSignals | 1007-1008 | `_on_unit_disengage_failed` |
| `unit_disengage_success` | BattleSignals | 1009-1010 | `_on_unit_disengage_success` |
| `regiment_hover_entered` | BattleSignals | 1012-1013 | `_on_regiment_hover_entered` |
| `regiment_hover_exited` | BattleSignals | 1014-1015 | `_on_regiment_hover_exited` |
| `regiment_routing` | BattleSignals | 1017-1018 | `_on_regiment_routing_autopause` |
| `battle_ended` | BattleSignals | 1019-1020 | `_on_battle_ended_autopause` |
| `battle_paused` | BattleSignals | 299-300 | `_on_battle_paused` |
| `tide_changed` | BattleTide | 279-280 | `_on_tide_changed` |
| `pressed` | deployment_panel | 388 | `_on_start_battle_pressed` |
| `pressed` | trait_panel_header | 713 | `_on_trait_panel_toggle` |
| `pressed` | speed buttons | 636 | lambda `_set_game_speed` |
| `pressed` | stance buttons | 1245 | `_on_stance_button_pressed` |
| `pressed` | formation buttons | 1268 | `_on_formation_button_pressed` |
| `pressed` | ability buttons | 1364 | `_on_ability_button_pressed` |
| `pressed` | continue_btn | 931 | `_on_after_action_continue` |

#### Emits: None directly (uses BattleSignals)

---

### UnitCard (battle_system/ui/unit_card.gd)

#### Signals Defined:
| Signal | Parameters |
|--------|------------|
| `card_clicked` | `regiment: Regiment` |
| `card_right_clicked` | `regiment: Regiment` |
| `card_shift_clicked` | `regiment: Regiment` |
| `card_ctrl_clicked` | `regiment: Regiment` |

#### Connects TO:
| Signal | Source | Line | Handler |
|--------|--------|------|---------|
| `mouse_entered` | self | 149 | `_on_mouse_entered` |
| `mouse_exited` | self | 150 | `_on_mouse_exited` |
| `regiment_attacked` | BattleSignals | 154 | `_on_regiment_attacked` |
| `regiment_routing` | BattleSignals | 155 | `_on_regiment_routing` |
| `regiment_rallied` | BattleSignals | 156 | `_on_regiment_rallied` |
| `stance_changed` | BattleSignals | 157 | `_on_stance_changed` |
| `formation_type_changed` | BattleSignals | 158 | `_on_formation_changed` |
| `ability_ready` | BattleSignals | 159 | `_on_ability_ready` |

#### Emits:
| Signal | Location | Trigger |
|--------|----------|---------|
| `card_clicked` | 1051 | Left-click (no modifier) |
| `card_ctrl_clicked` | 1047 | Ctrl+left-click |
| `card_shift_clicked` | 1049 | Shift+left-click |
| `card_right_clicked` | 1055 | Right-click |

---

### ControlGroupBar (battle_system/ui/control_group_bar.gd)

#### Connects TO:
| Signal | Source | Line | Handler |
|--------|--------|------|---------|
| `group_saved` | BattleSignals | 120 | `_on_group_saved` |
| `group_recalled` | BattleSignals | 121 | `_on_group_recalled` |
| `mouse_entered` | panel | 62 | lambda `_on_panel_hover` |
| `mouse_exited` | panel | 63 | lambda `_on_panel_hover` |
| `gui_input` | panel | 113 | `_on_panel_input` |

#### Emits: None (calls SelectionManager directly)

---

### SelectionManager (battle_system/systems/selection_manager.gd)

#### Emits:
| Signal | Location | Trigger |
|--------|----------|---------|
| `regiment_selected` | 215 | Unit added to selection |
| `regiment_deselected` | 223, 356 | Unit removed from selection |
| `selection_cleared` | 225 | Selection cleared |
| `group_saved` | 228 | Ctrl+0-9 pressed |
| `group_recalled` | 235 | 0-9 pressed |
| `move_mode_changed` | 511 | R key toggles run/walk |
| `regiment_hover_entered` | 654 | Mouse enters regiment |
| `regiment_hover_exited` | 651 | Mouse exits regiment |
| `battle_paused` | 620 | P key pressed |

---

### BattleSignals (battle_system/signals/battle_signals.gd)

#### All Signals Defined:
```
# Selection
regiment_selected(regiment: Regiment)
regiment_deselected(regiment: Regiment)
selection_cleared()
group_saved(group_id: int, regiments: Array)
group_recalled(group_id: int)

# Orders
order_given(regiment: Regiment, order: OrderType.Type, target: Variant)

# Combat
regiment_attacked(attacker: Regiment, defender: Regiment, damage: int)
projectile_fired(from: Regiment, target: Regiment)
unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool)
charge_impact(charger: Regiment, target: Regiment, was_braced: bool)

# Morale
morale_changed(regiment: Regiment, new_value: float, delta: float)
regiment_routing(regiment: Regiment)
regiment_rallied(regiment: Regiment)

# State
regiment_dead(regiment: Regiment)
general_died(general: General)
combat_state_changed(regiment: Regiment, flag: int, value: bool)

# Battle
battle_started()
battle_ended(result: Dictionary)

# Deployment Phase
deployment_started()
deployment_ended()
unit_repositioned(regiment: Regiment, new_position: Vector3)

# Formation
formation_preview_started(regiment: Regiment, start_pos: Vector3)
formation_preview_updated(regiment: Regiment, start_pos: Vector3, end_pos: Vector3)
formation_applied(regiment: Regiment, position: Vector3, facing: Vector3, width: float)

# AI System
ai_play_started(general_ai, play_name: String)
ai_play_completed(general_ai, play_name: String, success: bool)
ai_target_acquired(regiment: Regiment, target: Regiment)
ai_order_issued(regiment: Regiment, order_type: String, target)

# Per-Soldier Morale
unit_morale_changed(regiment: Regiment, average_morale: float)

# Stance and Formation
stance_changed(regiment: Regiment, old_stance: int, new_stance: int)
formation_type_changed(regiment: Regiment, old_formation: int, new_formation: int)
formation_reform_started(regiment: Regiment, duration: float)
formation_reform_completed(regiment: Regiment)
formation_cohesion_changed(regiment: Regiment, cohesion: float)

# Stamina
unit_exhausted(regiment: Regiment)
unit_recovered(regiment: Regiment)

# Veterancy
unit_leveled_up(regiment: Regiment, old_level: int, new_level: int)

# Abilities
ability_used(regiment: Regiment, ability: int)
ability_ready(regiment: Regiment, ability: int)

# Spells
spell_cast(caster: Regiment, spell_id: String, target_pos: Vector3)
spell_hit(spell_id: String, target: Regiment, damage: int)

# Reinforcements
reinforcements_available(wave: int, count: int)
reinforcements_arrived(wave: int)
reinforcements_requested()
spawn_reinforcement(spawn_info: Dictionary)

# Supply System
unit_resupplied(regiment: Regiment, resource_type: String, amount: int)
entered_supply_range(regiment: Regiment, wagon: Node)
left_supply_range(regiment: Regiment, wagon: Node)

# Casualty Tracker
unit_entered_caution(regiment: Regiment)
unit_withdrawing(regiment: Regiment)
unit_disengage_success(regiment: Regiment)
unit_disengage_failed(regiment: Regiment)

# Rally System
rally_used(general: Node, units_rallied: int)

# Ammo Type
round_type_changed(regiment: Regiment, old_type: int, new_type: int)

# Movement Mode
move_mode_changed(new_mode: int)

# Pause
battle_paused(is_paused: bool)

# Hover Preview
regiment_hover_entered(regiment: Regiment)
regiment_hover_exited(regiment: Regiment)
```

---

## Input Actions / Hotkeys

### SelectionManager Hotkeys

| Key | Modifier | Action | Handler | Line |
|-----|----------|--------|---------|------|
| Z | None | Aggressive stance | `_set_stance_for_selected` | 97 |
| X | None | Defensive stance | `_set_stance_for_selected` | 99 |
| C | None | Hold Ground stance | `_set_stance_for_selected` | 101 |
| V | None | Skirmish stance | `_set_stance_for_selected` | 103 |
| G | None | Guard mode | `_enter_guard_mode` | 105 |
| G | Ctrl | Create next group | `_create_next_group` | 77-79 |
| F1 | None | Line formation | `_set_formation_for_selected` | 111 |
| F2 | None | Column formation | `_set_formation_for_selected` | 113 |
| F3 | None | Wedge formation | `_set_formation_for_selected` | 115 |
| F4 | None | Square formation | `_set_formation_for_selected` | 117 |
| Q | None | Ability slot 0 | `_use_ability_hotkey(0)` | 124 |
| E | None | Ability slot 1 | `_use_ability_hotkey(1)` | 126 |
| F | None | Ability slot 2 | `_use_ability_hotkey(2)` | 128 |
| R | None | Run/Walk toggle | `_toggle_run_for_selected` | 131-132 |
| H | None | Hold position | `give_order(HOLD_POSITION)` | 135-137 |
| SPACE | None | Focus selected | `_camera_focus_selected` | 142-144 |
| HOME | None | Focus general | `_camera_focus_general` | 147-149 |
| END | None | Focus battle center | `_camera_focus_battle_center` | 152-154 |
| P | None | Toggle pause | `_toggle_pause` | 157-159 |
| F5-F8 | None | Save camera bookmark | `_camera_save_bookmark` | 166 |
| F5-F8 | Shift | Recall camera bookmark | `_camera_recall_bookmark` | 168 |
| 0-9 | None | Recall group | `_recall_group` | 90 |
| 0-9 | Ctrl | Save group | `_save_group` | 86 |
| 0-9 | Shift | Add group to selection | `_add_group_to_selection` | 88 |
| ALT | Hold | Show spell ranges | `_update_spell_range_display` | 29-32 |

### Mouse Actions

| Button | Modifier | Action | Handler | Line |
|--------|----------|--------|---------|------|
| Left Click | None | Select unit | `_single_select` | 58 |
| Left Click | Shift | Add to selection | `_single_select` | 187-189 |
| Left Click | Ctrl | Toggle selection | `_single_select` | 190-195 |
| Left Drag | None | Box select | `_finish_drag_select` | 56-57 |
| Left Drag | Shift/Ctrl | Add box to selection | `_finish_drag_select` | 201-208 |
| Double-Click | None | Select all of type | `_select_all_of_type` | 175-179 |

### BattleHUD Button Hotkeys (shown in UI)

| Button | Displayed | Action |
|--------|-----------|--------|
| Stance buttons | Z/X/C/V in tooltip | Change stance |
| Formation buttons | F1-F4 in tooltip | Change formation |
| Ability buttons | [Q]/[E]/[R] prefix | Use ability |
| Speed << | None | 0.5x speed |
| Speed \|\| | None | Pause (0.001x) |
| Speed > | None | 1.0x speed |
| Speed >> | None | 2.0x speed |

---

## UI Element Hierarchy

### BattleHUD Children
```
BattleHUD (CanvasLayer)
├── control_group_bar (ControlGroupBar) - top-left
├── timer_container (Control) - top-center
│   ├── frame (Panel)
│   └── battle_timer_label (Label)
├── tide_bar_container (Control) - below timer
│   ├── bg (Panel)
│   ├── tide_bar_fill (ColorRect)
│   └── tide_bar_marker (ColorRect)
├── pause_label (Label) - center-top
├── minimap_panel (Panel) - top-right
│   └── minimap (BattleMinimap)
├── compass_container (Panel) - below minimap
│   └── compass (BattleCompass)
├── deployment_panel (Button) - top-left (during deployment)
├── selected_unit_panel (Panel) - bottom-left
│   ├── portrait_panel (Panel)
│   │   └── selected_unit_portrait (TextureRect)
│   ├── selected_unit_name (Label)
│   ├── selected_unit_stats (VBoxContainer)
│   ├── stance_label (Label)
│   ├── stance_container (HBoxContainer)
│   ├── formation_label (Label)
│   ├── formation_container (HBoxContainer)
│   ├── ability_label (Label)
│   └── ability_container (HBoxContainer)
├── bottom_panel (Panel) - bottom-center
│   └── scroll (ScrollContainer)
│       └── unit_card_container (HBoxContainer)
├── speed_panel (Panel) - bottom-right
│   ├── speed_label (Label)
│   └── button_container (HBoxContainer)
├── hover_preview_panel (Panel) - floating
│   ├── hover_preview_name (Label)
│   └── hover_preview_stats (Label)
├── trait_panel (Panel) - top-left below control groups
│   ├── trait_panel_header (Button)
│   └── trait_panel_content (VBoxContainer)
└── after_action_panel (Panel) - center (on battle end)
    └── scroll (ScrollContainer)
        └── after_action_content (VBoxContainer)
```

### UnitCard Children
```
UnitCard (PanelContainer)
└── vbox (VBoxContainer)
    ├── portrait_container (Control)
    │   ├── portrait_rect (TextureRect)
    │   ├── chevron_container (HBoxContainer) - top-left overlay
    │   ├── unit_type_badge (Panel) - top-right overlay
    │   │   └── unit_type_label (Label)
    ├── name_label (Label)
    ├── status_container (HBoxContainer)
    ├── soldier_count_label (Label)
    ├── health_bar (ProgressBar)
    ├── morale_bar_container (Control)
    │   ├── morale_bar (ProgressBar)
    │   ├── morale_threshold_markers (ColorRect[])
    │   ├── morale_cap_shade (ColorRect)
    │   └── morale_cap_marker (ColorRect)
    └── ammo_container (VBoxContainer)
        ├── ammo_bar (ProgressBar)
        ├── ammo_label (Label)
        └── ammo_warning_label (Label)
└── ability_cooldown_container (HBoxContainer) - bottom-right absolute
```

---

## Critical Dependencies

### DO NOT change simultaneously:
- `unit_card.gd` AND `battle_hud.gd` - They communicate via signals

### Signal flow for selection:
1. User clicks -> `SelectionManager._single_select()`
2. SelectionManager emits `BattleSignals.regiment_selected`
3. BattleHUD receives via `_on_regiment_selected()`
4. BattleHUD calls `unit_cards[reg].set_selected(true)`

### Signal flow for damage flash:
1. Combat system emits `BattleSignals.regiment_attacked`
2. UnitCard receives via `_on_regiment_attacked()`
3. UnitCard sets `_damage_flash_timer = DAMAGE_FLASH_DURATION`

### Throttled update pattern (KEEP):
- `_last_chevron_level` - only rebuild chevrons when level changes
- `_last_status_hash` - bitmask of status flags
- `_last_morale_band` - 0-3 for color bands
- `_last_health_band` - 0-2 for health colors
- `_last_ammo_band` - 0-2 for ammo colors
- `_last_card_state` - CardState enum
- `_last_ability_hash` - computed from cooldown states
- `SLOW_UPDATE_INTERVAL = 0.25` - 4Hz for non-critical updates
