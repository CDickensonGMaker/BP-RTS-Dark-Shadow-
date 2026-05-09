# BP RTS Dark Shadows - UI Overhaul: 9-Hour Implementation Plan

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Setup and Inventory | ✅ Complete |
| Phase 1 | Container Restructure | ✅ Complete |
| Phase 2 | Readability Pass & Command Bar | ✅ Complete |
| Phase 3 | Control Group Integration | ✅ Complete |

**Completed:** 2026-05-08

### Summary of Changes

**Phase 0:**
- Created `WIP/ui_audit.md` documenting all signal connections and hotkeys
- Created `WIP/ui_progress/` folder structure

**Phase 1:**
- Restructured `_create_selected_unit_panel()` to use VBoxContainer/HBoxContainer instead of manual offsets
- Created unified `_create_bottom_hud()` for bottom HUD layout
- Fixed unit_card.gd overlays to use proper anchoring (chevron_container, unit_type_badge)

**Phase 2:**
- Simplified unit card: replaced `STATE_BG_COLORS` with neutral background
- Replaced unit_type_badge with unit_type_edge (4px ColorRect on left edge)
- Hidden chevron_container (to be shown in selected panel)
- Created command bar with orders/stance/formation/ability sections
- Made selected_unit_panel info-only (commands moved to command bar)
- Added group ability support (`_abilities_for_selection()`, `_update_command_bar_abilities()`)
- Updated stance/formation/ability button handlers to apply to all selected units

**Phase 3:**
- Added `find_group_for(reg)` and `get_regiments_by_group()` to SelectionManager
- Modified `_populate_unit_cards()` to bucket cards by control group with visual dividers
- Connected `group_saved` signal to re-bucket cards when groups change

---

## AAA Game UI Design Research Summary

### Core Principles from Industry Analysis

**From RTS UI Best Practices (StarCraft, Total War, Company of Heroes):**

1. **Visual Hierarchy** - Critical info (health, ammo) at periphery; secondary details in expandable panels
2. **Information Density Balance** - Show only what the player needs at any given moment; use contextual HUDs
3. **Unified Command Zone** - Don't scatter commands; verbs belong together (SC2's command card pattern)
4. **State Feedback through Borders** - Reserve distinctive borders/colors for selected state; muted borders elsewhere
5. **Type-as-Color** - Unit type communicated via peripheral cues (edge colors), not competing badges
6. **Readability First** - Minimum 16pt text, high contrast, sans-serif fonts, 150%+ scaling options
7. **Hotkey Discovery** - Buttons display hotkeys; players learn through UI, not memorization
8. **Throttled Updates** - Non-critical UI updates at 2-4Hz; animations at 60Hz

**From Company of Heroes 2 UI Analysis:**
- Streamlined dashboard: hide menus until needed
- Limit initial choices to prevent cognitive overload
- Consistent 2D art style (no mixed styles)

**From Strategy Game Layout Evolution:**
- Top bar + bottom bar became standard post-StarCraft
- Minimap always top-right (conditioned player behavior)
- Selected unit details bottom-left, unit roster bottom-center

### Key Metrics
- **30%+ player churn** attributed to poor UI/UX (Game-Ace study)
- **2-3 click rule** for critical functions (navigation depth)
- **Universal icons** reduce learning time (gear=settings, trophy=achievements)

---

## Ground Rules (User-Specified)

1. **Branch per phase**: `ui-phase-1-containers`, `ui-phase-2-readability`, `ui-phase-3-groups`
2. **Merge to main** only after playing a full battle without regressions
3. **Screenshots before/after** each phase in `ui_progress/` folder (same battle, same selection, same window)
4. **Don't refactor `unit_card.gd` and `battle_hud.gd` simultaneously** - they communicate via signals
5. **Keep throttled-update pattern** - The `_last_chevron_level`, `_last_status_hash`, `_last_morale_band` caching is correct

---

## Phase 0 - Setup and Inventory (1 hour)

**Goal:** Complete dependency map before touching any code.

### Hour 0:00-1:00 - Audit and Documentation

#### Task 0.1: Create `ui_audit.md`

List every signal connection in the UI system:

**Files to grep:**
- `battle_system/ui/battle_hud.gd`
- `battle_system/ui/unit_card.gd`
- `battle_system/ui/control_group_bar.gd`
- `battle_system/systems/selection_manager.gd`
- `battle_system/signals/battle_signals.gd`

**Search patterns:**
```
\.connect(
\.emit(
signal
```

#### Task 0.2: Inventory Input Actions

Document all hotkeys the UI responds to:

| Key | Action | File | Line |
|-----|--------|------|------|
| Z/X/C/V | Stances | selection_manager.gd | 93-103 |
| F1-F4 | Formations | selection_manager.gd | 109-118 |
| Q/E/F | Abilities | selection_manager.gd | 121-128 |
| R | Run/Walk Toggle | selection_manager.gd | 130-132 |
| H | Hold Position | selection_manager.gd | 135-137 |
| SPACE | Focus Selected | selection_manager.gd | 142-144 |
| HOME | Focus General | selection_manager.gd | 147-149 |
| END | Focus Battle Center | selection_manager.gd | 152-154 |
| P | Pause Toggle | selection_manager.gd | 157-159 |
| Ctrl+G | Create Group | selection_manager.gd | 77-79 |
| Ctrl+0-9 | Save Group | selection_manager.gd | 82-91 |
| 0-9 | Recall Group | selection_manager.gd | 82-91 |
| Shift+0-9 | Add Group to Selection | selection_manager.gd | 82-91 |
| F5-F8 | Camera Bookmarks | selection_manager.gd | 162-169 |
| Shift/Ctrl+Click | Multi-select | selection_manager.gd | 187-196 |

#### Task 0.3: Baseline Screenshots

Create `ui_progress/` folder and capture 6 screenshots:
1. Empty battle (no selection)
2. One unit selected
3. Three units selected
4. Control group saved and selected
5. Unit routing
6. Unit dead

**Filename convention:** `phase0_before_[state].png`

---

## Phase 1 - Container Restructure (2.5 hours)

**Branch:** `ui-phase-1-containers`

**Goal:** Zero visible changes. HUD built on Godot containers instead of manual offsets.

### Hour 1:00-2:00 - Selected Unit Panel Restructure

#### Task 1.1: Replace `_create_selected_unit_panel()` (battle_hud.gd:401)

**Current structure:** Panel with 7 floating children using absolute offsets

**New structure:**
```
Panel
└── MarginContainer (margin: 8)
    └── VBoxContainer (separation: 6)
        ├── HBoxContainer [Header]
        │   ├── Panel [Portrait] (fixed 70x70)
        │   └── VBoxContainer [Stats] (SIZE_EXPAND_FILL)
        │       ├── Label [Name]
        │       └── VBoxContainer [selected_unit_stats]
        ├── VBoxContainer [Stance Row]
        │   ├── Label "Stance"
        │   └── HBoxContainer [stance_container]
        ├── VBoxContainer [Formation Row]
        │   ├── Label "Formation"
        │   └── HBoxContainer [formation_container]
        └── VBoxContainer [Abilities Row]
            ├── Label "Abilities (Q/E/R)"
            └── HBoxContainer [ability_container]
```

**Success criteria:** Panel appears at same location/size as before

**Delete these properties:**
- All `offset_left`, `offset_top`, `offset_right`, `offset_bottom` inside this function
- Use `custom_minimum_size` on portrait
- Use `size_flags_horizontal = SIZE_EXPAND_FILL` elsewhere

### Hour 2:00-2:30 - Unit Card Overlay Fix

#### Task 1.2: Fix unit_card.gd overlays (line 162)

**Current issues:**
- Chevron container uses `position = Vector2(2, 2)`
- Ability cooldown container uses anchored absolute position

**New structure:**
```
portrait_container (Control)
└── Control [Overlay Surface] (PRESET_FULL_RECT)
    ├── HBoxContainer [Chevrons] (top-left anchored)
    └── HBoxContainer [Cooldown Badges] (bottom-right anchored)
```

**Changes:**
- Parent chevron_container to portrait_container overlay
- Parent ability_cooldown_container to portrait_container overlay
- Remove absolute `position` assignments

### Hour 2:30-3:30 - Bottom HUD Unification

#### Task 1.3: Create unified bottom HUD structure

**Current:** Three independent anchored controls
- Selected unit panel (bottom-left)
- Unit card bar (bottom-center)
- Speed controls (bottom-right)

**New structure:**
```
HBoxContainer [BottomHUD] (PRESET_BOTTOM_WIDE, offset_top=-170, offset_bottom=-10)
├── Panel [SelectedUnitPanel] (custom_minimum_size.x = 300)
├── Panel [UnitCardBar] (SIZE_EXPAND_FILL)
└── Panel [SpeedControls] (custom_minimum_size.x = 190)
```

**Behavior:** Resize window - cards strip stretches/shrinks, side panels stay fixed

#### Task 1.4: Verification Battle

Play one full battle. Verify:
- [ ] Hover preview works
- [ ] After-action report displays
- [ ] Deployment panel toggle works
- [ ] Auto-pause on rout (if enabled)
- [ ] Control group bar (top-left) functions
- [ ] Minimap renders correctly
- [ ] Compass displays direction
- [ ] Tide bar animates
- [ ] Timer updates

**If anything regressed:** Fix before merging.

**Take screenshots:** `phase1_after_[state].png`

---

## Phase 2 - Readability Pass and Command Zone (4 hours)

**Branch:** `ui-phase-2-readability`

**Goal:** Modern, readable UI with unified command bar.

### Hour 3:30-4:30 - Strip Unit Card Down

#### Task 2.1: Simplify unit_card.gd

**Remove:**
- Faction-color background tint (line ~815-817)
- Unit-type letter badge in corner (lines ~194-213)
- Chevron overlay (move to selected panel)
- Per-state background colors (STATE_BG_COLORS competing with morale bar)

**Add:**
- 4px-wide ColorRect on leftmost edge colored by `UNIT_TYPE_COLORS`
- This is "type as peripheral edge color"

**Keep:**
- Border color for state (selected, damage, wavering, routing, dead)
- Subtle modulate for state
- Morale bar (already colored by state)

**Remove these constants/variables:**
- `_last_regiment_state`
- `STATE_BG_COLORS` dictionary
- `_update_state_background_color()` method

**Visual test:** Select 8 units, engage enemy. Can you tell at a glance which are in trouble?

### Hour 4:30-6:00 - Build Command Bar

#### Task 2.2: Create command bar structure

**Location:** Inside bottom panel (currently holding only unit cards scroll)

**New structure:**
```
VBoxContainer [BottomContent]
├── HBoxContainer [CommandBar] (custom_minimum_size.y = 44)
│   ├── HBoxContainer [OrdersSection]
│   │   ├── Button [Move] (40x36, icon + "[M]")
│   │   ├── Button [Attack] (40x36, icon + "[A]")
│   │   ├── Button [Halt] (40x36, icon + "[H]")
│   │   └── Button [Run Toggle] (40x36, icon + "[R]")
│   ├── ColorRect [Divider] (2px wide, accent color)
│   ├── HBoxContainer [FormationStanceSection]
│   │   ├── [Stance buttons moved from selected_unit_panel]
│   │   └── [Formation buttons moved from selected_unit_panel]
│   ├── ColorRect [Divider] (2px wide)
│   └── HBoxContainer [AbilitiesSection]
│       └── [Ability buttons - dynamically populated]
└── ScrollContainer [UnitCards] (SIZE_EXPAND_FILL)
```

**Move from selected_unit_panel:**
- stance_container (buttons Z/X/C/V)
- formation_container (buttons F1-F4)
- ability_container (buttons Q/E/F)

**Selected unit panel becomes purely informational:**
- Portrait
- Name
- Stats (Type, Men, Morale, Stamina, Rank, Ammo)
- Chevrons (moved from unit card)

### Hour 6:00-7:00 - Group Abilities

#### Task 2.3: Add `_abilities_for_selection()` to BattleHUD

```gdscript
func _abilities_for_selection() -> Array:
    var sel = SelectionManager.selected_regiments
    if sel.is_empty():
        return []
    if sel.size() == 1:
        var single = []
        for a in sel[0].abilities.available_abilities:
            single.append({"ability": a, "available_count": 1, "total": 1})
        return single
    var counts = {}
    for reg in sel:
        if not is_instance_valid(reg) or not reg.abilities:
            continue
        for a in reg.abilities.available_abilities:
            counts[a] = counts.get(a, 0) + 1
    var result = []
    for a in counts:
        result.append({"ability": a, "available_count": counts[a], "total": sel.size()})
    return result
```

#### Task 2.4: Create `_update_command_bar_abilities()`

- Fire on selection change
- Buttons with `available_count < total` show "3/8" badge
- Press handler iterates `SelectionManager.selected_regiments`
- Calls `use_ability()` or `toggle_ability()` on each unit that has the ability

#### Task 2.5: Update hotkey handlers

Modify `selection_manager.gd::_use_ability_hotkey()` to iterate all selected regiments:

```gdscript
func _use_ability_hotkey(slot: int):
    for regiment in selected_regiments:
        if not is_instance_valid(regiment) or not regiment.abilities:
            continue
        var abilities_list: Array = regiment.abilities.available_abilities
        if slot < abilities_list.size():
            var ability = abilities_list[slot]
            # ... existing target mode logic ...
            regiment.use_ability(ability, ...)
```

### Hour 7:00-7:30 - Polish Pass

#### Task 2.6: Border cleanup

**Rule:** One color, one width for "panel exists here"
- Reserve gold (`COLOR_GOLD`) for selected-state borders ONLY
- Timer and tide bar: remove gold borders (informational, not interactive)
- Drop any 2px decorative borders

**Changes:**
- `_create_timer_display()`: Use `COLOR_PANEL_BORDER` not `COLOR_GOLD`
- `_create_tide_bar()`: Keep 1px subtle border only
- `_create_compass()`: Use `COLOR_PANEL_BORDER`

**Take screenshots:** `phase2_after_[state].png`
**Compare to baseline.** Side-by-side shows improvement.

---

## Phase 3 - Control Group Integration (1.5 hours)

**Branch:** `ui-phase-3-groups`

**Goal:** Visual grouping of cards in bottom bar by control group.

### Hour 7:30-8:00 - Group Lookup Helper

#### Task 3.1: Add to SelectionManager

```gdscript
func find_group_for(reg: Regiment) -> int:
    """Return lowest group ID containing this regiment, or -1 if ungrouped."""
    for gid in saved_groups:
        if reg in saved_groups[gid]:
            return gid
    return -1
```

### Hour 8:00-8:45 - Bucket Cards by Group

#### Task 3.2: Modify `_populate_unit_cards()`

**Before adding cards:**
1. Build `{group_id: [regiments]}` dictionary
2. Build `ungrouped: [regiments]` array
3. Sort group IDs ascending

**Card population order:**
1. For each group (1-9 order):
   - Add thin vertical separator (2px ColorRect, accent color, full card height)
   - Add small floating group number label
   - Add cards for that group
2. Add ungrouped units at right end (no separator)

```gdscript
func _populate_unit_cards():
    # ... clear existing ...

    var regiments = get_tree().get_nodes_in_group("player_regiments")
    var grouped: Dictionary = {}  # group_id -> Array[Regiment]
    var ungrouped: Array[Regiment] = []

    for reg in regiments:
        if not reg is Regiment:
            continue
        var gid = SelectionManager.find_group_for(reg)
        if gid >= 0:
            if not grouped.has(gid):
                grouped[gid] = []
            grouped[gid].append(reg)
        else:
            ungrouped.append(reg)

    # Sort group IDs
    var sorted_gids = grouped.keys()
    sorted_gids.sort()

    # Add grouped cards
    for gid in sorted_gids:
        _add_group_divider(gid)
        for reg in grouped[gid]:
            _add_unit_card(reg)

    # Add ungrouped
    if not ungrouped.is_empty() and not grouped.is_empty():
        _add_ungrouped_divider()
    for reg in ungrouped:
        _add_unit_card(reg)
```

#### Task 3.3: Create divider helpers

```gdscript
func _add_group_divider(group_id: int):
    var container = Control.new()
    container.custom_minimum_size = Vector2(16, 0)

    var divider = ColorRect.new()
    divider.color = COLOR_GOLD
    divider.custom_minimum_size = Vector2(2, 120)
    divider.set_anchors_preset(Control.PRESET_CENTER)
    container.add_child(divider)

    var label = Label.new()
    label.text = str((group_id + 1) % 10)
    label.add_theme_font_size_override("font_size", 10)
    label.add_theme_color_override("font_color", COLOR_GOLD)
    label.set_anchors_preset(Control.PRESET_TOP_LEFT)
    label.offset_top = 2
    container.add_child(label)

    unit_card_container.add_child(container)
```

### Hour 8:45-9:00 - React to Group Changes

#### Task 3.4: Connect group_saved signal

```gdscript
# In _connect_signals():
BattleSignals.group_saved.connect(_on_group_changed)

func _on_group_changed(_group_id: int, _regiments: Array):
    _populate_unit_cards()  # Re-bucket cards
```

**Optimization note:** This recreates all cards. Future optimization: reorder existing cards, add/remove dividers only. Correctness first.

#### Task 3.5: Decision on top-left control group bar

**Keep it (Option A):**
- Already works
- Provides "is group 2 in trouble?" at a glance without selecting
- Players use both: top bar for overview, bottom for detail

**If playtesters find redundant:** Remove in future iteration.

**Take final screenshots:** `phase3_after_[state].png`

---

## Phase 4 - Optional Improvements (Future)

Not required for this 9-hour session, but worth doing eventually:

1. **Throttle control_group_bar.gd::_process** - Currently runs every frame. Use 2Hz pattern.

2. **Hover preview on card hover** - Show preview panel when hovering unit cards, not just 3D regiments.

3. **Right-click context menu on cards:**
   - "Save to group >" with submenu 1-0
   - "Disband formation"
   - "Order to retreat point"

4. **Ctrl-Shift-click drag-to-reorder cards** - Total War feature, nontrivial, defer.

---

## Verification Checklist

### After Each Phase

- [ ] All existing hotkeys still work
- [ ] Selection via click/drag works
- [ ] Multi-select (Shift/Ctrl) works
- [ ] Control groups save/recall work
- [ ] Abilities fire correctly
- [ ] Formations/stances apply
- [ ] Combat feedback (damage flash, routing, wavering) visible
- [ ] Morale bar colors change at thresholds
- [ ] Health bar updates
- [ ] Ammo warnings appear for ranged units
- [ ] Speed controls function
- [ ] Pause overlay shows
- [ ] Timer counts up
- [ ] Tide bar animates
- [ ] Minimap renders units
- [ ] Compass shows direction
- [ ] After-action report displays on battle end

### Screenshot Comparison Points

| State | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|-------|---------|---------|---------|---------|
| Empty | before_empty | after_empty | after_empty | after_empty |
| 1 Selected | before_1sel | after_1sel | after_1sel | after_1sel |
| 3 Selected | before_3sel | after_3sel | after_3sel | after_3sel |
| Group Active | before_group | after_group | after_group | after_group |
| Routing | before_routing | after_routing | after_routing | after_routing |
| Dead | before_dead | after_dead | after_dead | after_dead |

---

## Signal Dependency Reference

### BattleHUD connects to:
- `BattleSignals.regiment_selected`
- `BattleSignals.regiment_dead`
- `BattleSignals.deployment_ended`
- `BattleSignals.battle_started`
- `BattleSignals.unit_disengage_failed`
- `BattleSignals.unit_disengage_success`
- `BattleSignals.regiment_hover_entered`
- `BattleSignals.regiment_hover_exited`
- `BattleSignals.regiment_routing`
- `BattleSignals.battle_ended`
- `BattleSignals.battle_paused`
- `BattleTide.tide_changed` (if exists)

### UnitCard connects to:
- `BattleSignals.regiment_attacked`
- `BattleSignals.regiment_routing`
- `BattleSignals.regiment_rallied`
- `BattleSignals.stance_changed`
- `BattleSignals.formation_type_changed`
- `BattleSignals.ability_ready`

### ControlGroupBar connects to:
- `BattleSignals.group_saved`
- `BattleSignals.group_recalled`

### UnitCard emits:
- `card_clicked(regiment)`
- `card_right_clicked(regiment)`
- `card_shift_clicked(regiment)`
- `card_ctrl_clicked(regiment)`

---

## Git Workflow

```bash
# Phase 0
git checkout -b ui-phase-0-audit
# Create ui_audit.md, take screenshots
git add WIP/ui_audit.md ui_progress/
git commit -m "Phase 0: UI audit and baseline screenshots"

# Phase 1
git checkout -b ui-phase-1-containers
# Make container changes
git add battle_system/ui/
git commit -m "Phase 1: Convert HUD to container-based layout"
# Test full battle
git checkout main && git merge ui-phase-1-containers

# Phase 2
git checkout -b ui-phase-2-readability
# Strip card, build command bar, group abilities
git add battle_system/ui/ battle_system/systems/
git commit -m "Phase 2: Readability pass and unified command bar"
# Test full battle
git checkout main && git merge ui-phase-2-readability

# Phase 3
git checkout -b ui-phase-3-groups
# Group lookup, bucketed cards
git add battle_system/ui/ battle_system/systems/
git commit -m "Phase 3: Control group visual integration"
# Test full battle
git checkout main && git merge ui-phase-3-groups
```

---

## Sources

- [UI Strategy Game Design Dos and Don'ts](https://www.gamedeveloper.com/design/ui-strategy-game-design-dos-and-don-ts) - Game Developer
- [Game UI UX Design Best Practices](https://www.justinmind.com/ui-design/game) - JustInMind
- [The Complete Game UX Guide 2025](https://game-ace.com/blog/the-complete-game-ux-guide/) - Game-Ace
- [Strategy Game Battle UI Analysis](https://medium.com/@treeform/strategy-game-battle-ui-3b313ffd3769) - Medium
- [Company of Heroes UI Analysis](https://www.coh2.org/topic/111219/ui-icons-an-analysis) - COH2.org
- [UX Design: Readable User Interface](https://blog.tubikstudio.com/ux-design-readable-user-interface/) - Tubik Blog
- [Balancing Information Expressiveness in Games](https://www.gamedeveloper.com/design/-ux-design-balancing-information-and-its-expressiveness---analysis-of-ui-information-presentation-of-games) - Game Developer
