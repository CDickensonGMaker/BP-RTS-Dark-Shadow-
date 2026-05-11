# 3D Arrows & Unit Zoo Enhancement Plan

## Research Summary

### Web Research Findings

#### Ballistic Trajectory Mathematics
From [ForrestTheWoods - Solving Ballistic Trajectories](https://www.forrestthewoods.com/blog/solving_ballistic_trajectories/):
- **Core equation**: `final_position = initial_position + velocity*time + 0.5*acceleration*time^2`
- Solutions typically yield **two angles** (low arc / high arc)
- For hitting a target at position (x, y) from origin, the formula for launch angle is:

```
tan(θ) = (v² ± √(v⁴ - g(gx² + 2yv²))) / gx
```

Where: v = projectile speed, g = gravity, x = horizontal distance, y = vertical difference

#### Total War Style Volleys
From [Total War Center Projectile Guide](https://www.twcenter.net/threads/a-guide-on-the-descr_projectile-txt.468257/):
- **scatter_angle**: 5-30 degrees to simulate multiple soldiers firing
- **projectile_number**: Controls volley density
- **min_angle / max_angle**: Constrains launch angle range
- **velocity**: Higher = flatter trajectory

#### Godot Implementation Patterns
From [Godot 3 Ballistic Bullet Recipe](https://kidscancode.org/godot_recipes/3.x/2d/ballistic_bullet/index.html):
```gdscript
# Simple ballistic motion without physics engine
velocity.y += gravity * delta
position += velocity * delta
rotation = velocity.angle()
```

From [GDQuest Ranged Attacks](https://www.gdquest.com/library/ranged_attacks/):
- Use Area2D/Area3D for hit detection
- Separate ImpactDetectorArea from HitArea (damage source)

---

## Current System Analysis

### What Already Exists (GOOD NEWS!)

#### 1. 3D Arrow Projectile System ✅ COMPLETE
Location: `battle_system/nodes/projectile.gd` (1177 lines)

**Features Already Implemented:**
- `use_3d_arrows: bool = true` - **Already enabled by default!**
- Loads 3D model from `battle_system/nodes/arrow_3d.tscn` → `assets/models/arrow.glb`
- **Parabolic arc trajectory** with configurable height
- **Object pooling** via `ProjectilePool` (300 pool, 500 max active)
- **Homing** with slerp-based turning (180°/sec turn rate)
- **Piercing** with damage falloff (25% per pierce)
- **AOE explosions** on impact
- **Trail particles** with per-type customization
- Multiple projectile types: ARROW, CROSSBOW, MAGIC, SHELL, FLAME, PELLET, CHAIN

**Arc Motion Code (lines 824-854):**
```gdscript
# Calculate arc progress (0 to 1) based on distance traveled
var arc_progress: float = clampf(_distance_traveled / _total_distance, 0.0, 1.0)

# Calculate parabolic arc offset (peaks at midpoint)
var arc_offset: float = 4.0 * arc_height * arc_progress * (1.0 - arc_progress)

# Calculate base height interpolation
var base_height: float = lerpf(_start_position.y, _target_position.y, arc_progress)
```

#### 2. Selection & Unit Control ✅ INFRASTRUCTURE EXISTS
- `SelectionManager` autoload handles click/drag selection
- `FormationDragHandler` autoload handles right-click movement
- Both support **SubViewport coordinate conversion** for Unit Zoo
- Control groups (Ctrl+1-9 save, 1-9 recall)
- Stance hotkeys (Z/X/C/V), Formation hotkeys (F1-F4)

#### 3. Unit Zoo ✅ PARTIALLY COMPLETE
Location: `scenes/unit_zoo_controller.gd`

**Current Features:**
- Unit spawning with dropdown selection
- Button-based commands (Move, Attack, Charge, Disengage)
- Formation/Stance selectors
- Weather system integration
- Stat adjustment (veterancy, armor, attack)
- Auto-test and stress test modes
- Projectile debug overlay (P key)

**What's Missing:**
- Full RTS-style unit control (click-to-select, right-click-to-move)
- Debug visualizations for formations

---

## Implementation Plan

### Phase 1: Verify 3D Arrow System Works
**Status: Should already work - needs verification**

Tasks:
1. [ ] Test that `use_3d_arrows = true` shows 3D arrow models in flight
2. [ ] Verify arc trajectory looks correct (parabolic, peaks at midpoint)
3. [ ] Check arrow rotation follows flight path (look_at direction)
4. [ ] Test trail particles emit properly

If issues found:
- Check `arrow_3d.tscn` scale (currently 0.5)
- Verify `_spawn_3d_arrow()` is being called in `activate()`

### Phase 2: Enhance Arrow Volley System
**Goal: Multiple arrows per volley with scatter like Total War**

Location: `battle_system/ai/commander/regiment_firing.gd`

Current firing patterns:
- STAGGER: Independent reload timers
- VOLLEY: All fire together
- SINGLE: Crewed weapons

Enhancement:
```gdscript
## When firing volley, spawn multiple projectiles with scatter
func _fire_volley(regiment: Regiment, target: Regiment) -> void:
    var volley_size: int = mini(regiment.current_soldiers, MAX_VOLLEY_SIZE)
    var scatter_angle: float = deg_to_rad(VOLLEY_SCATTER_DEGREES)

    for i in volley_size:
        var offset: Vector3 = _get_soldier_fire_position(regiment, i)
        var scatter: Vector3 = _apply_scatter(target.global_position, scatter_angle)
        _spawn_arrow(regiment, offset, scatter)
```

Parameters to add:
- `VOLLEY_SCATTER_DEGREES: float = 5.0` - Angular scatter
- `MAX_VOLLEY_SIZE: int = 10` - Max arrows per volley frame
- `VOLLEY_STAGGER_TIME: float = 0.1` - Time between soldier fires

### Phase 3: Unit Zoo Full Control Integration
**Goal: Make Unit Zoo use same controls as Battle Scene**

#### 3.1 Verify SelectionManager Works in Unit Zoo
The SelectionManager already has SubViewport support via `_is_mouse_in_battle_viewport()`.

Check `_input()` function:
```gdscript
# Already handles SubViewport coordinate conversion
if not _is_mouse_in_battle_viewport():
    return
```

**Test:**
1. Click on regiment in Unit Zoo viewport → should select
2. Drag select box → should select multiple
3. Right-click terrain → should move
4. Right-click enemy → should attack-move

#### 3.2 Wire Up FormationDragHandler
The FormationDragHandler also supports SubViewport. Verify it receives mouse events.

**Potential Issue:** Unit Zoo's `_input()` might be intercepting events before autoloads.

**Fix if needed:** Ensure Unit Zoo doesn't consume mouse events:
```gdscript
func _input(event: InputEvent) -> void:
    # Only handle keyboard hotkeys
    if event is InputEventKey and event.pressed and not event.echo:
        # ... handle keys ...
    # Let mouse events pass through to SelectionManager/FormationDragHandler
```

### Phase 4: Debug Visualization System
**Goal: Visual debugging aids for formation and melee**

#### 4.1 Formation Front Arrow (When Selected)
Show a small arrow indicating unit facing direction.

Create: `battle_system/debug/formation_debug_overlay.gd`

```gdscript
class_name FormationDebugOverlay
extends Node3D

## Draws debug overlays for selected regiments:
## - Formation front arrow
## - Melee engagement box

var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _enabled: bool = false

const ARROW_LENGTH: float = 3.0
const ARROW_HEAD_SIZE: float = 0.8
const ARROW_COLOR: Color = Color(0.2, 0.8, 0.2, 0.8)  # Green

func _ready() -> void:
    _setup_mesh()

func _setup_mesh() -> void:
    _immediate_mesh = ImmediateMesh.new()
    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.mesh = _immediate_mesh

    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _mesh_instance.material_override = mat

    add_child(_mesh_instance)

func _process(_delta: float) -> void:
    if not _enabled:
        return
    _draw_overlays()

func _draw_overlays() -> void:
    _immediate_mesh.clear_surfaces()

    if not SelectionManager:
        return

    for regiment in SelectionManager.selected_regiments:
        if not is_instance_valid(regiment):
            continue
        _draw_formation_arrow(regiment)
        _draw_melee_box(regiment)

func _draw_formation_arrow(regiment: Regiment) -> void:
    _immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, null)

    var center: Vector3 = regiment.global_position + Vector3(0, 0.5, 0)
    var facing: Vector3 = regiment.get_facing_direction()
    var right: Vector3 = facing.cross(Vector3.UP).normalized()

    # Arrow shaft
    var arrow_start: Vector3 = center
    var arrow_end: Vector3 = center + facing * ARROW_LENGTH

    _immediate_mesh.surface_set_color(ARROW_COLOR)
    _immediate_mesh.surface_add_vertex(arrow_start)
    _immediate_mesh.surface_add_vertex(arrow_end)

    # Arrow head (V shape)
    var head_left: Vector3 = arrow_end - facing * ARROW_HEAD_SIZE + right * ARROW_HEAD_SIZE * 0.5
    var head_right: Vector3 = arrow_end - facing * ARROW_HEAD_SIZE - right * ARROW_HEAD_SIZE * 0.5

    _immediate_mesh.surface_add_vertex(arrow_end)
    _immediate_mesh.surface_add_vertex(head_left)
    _immediate_mesh.surface_add_vertex(arrow_end)
    _immediate_mesh.surface_add_vertex(head_right)

    _immediate_mesh.surface_end()
```

#### 4.2 Melee Engagement Box
Show the area where melee combat occurs.

```gdscript
const MELEE_BOX_COLOR: Color = Color(0.8, 0.3, 0.3, 0.5)  # Red-ish
const MELEE_MIN_GAP: float = 0.8  # From melee_resolver.gd

func _draw_melee_box(regiment: Regiment) -> void:
    if regiment.state != Regiment.State.ENGAGING:
        return

    _immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, null)

    var center: Vector3 = regiment.global_position + Vector3(0, 0.3, 0)
    var facing: Vector3 = regiment.get_facing_direction()
    var right: Vector3 = facing.cross(Vector3.UP).normalized()

    # Get formation width and engagement distance
    var front_offset: float = regiment.get_front_rank_offset()
    var formation_width: float = _estimate_formation_width(regiment)

    # Draw box at formation front
    var front_center: Vector3 = center + facing * front_offset
    var half_width: float = formation_width / 2.0
    var box_depth: float = MELEE_MIN_GAP + 0.5

    # Four corners of melee zone
    var fl: Vector3 = front_center + right * half_width
    var fr: Vector3 = front_center - right * half_width
    var bl: Vector3 = fl + facing * box_depth
    var br: Vector3 = fr + facing * box_depth

    _immediate_mesh.surface_set_color(MELEE_BOX_COLOR)

    # Front edge
    _immediate_mesh.surface_add_vertex(fl)
    _immediate_mesh.surface_add_vertex(fr)

    # Sides
    _immediate_mesh.surface_add_vertex(fl)
    _immediate_mesh.surface_add_vertex(bl)
    _immediate_mesh.surface_add_vertex(fr)
    _immediate_mesh.surface_add_vertex(br)

    # Back edge
    _immediate_mesh.surface_add_vertex(bl)
    _immediate_mesh.surface_add_vertex(br)

    _immediate_mesh.surface_end()

func _estimate_formation_width(regiment: Regiment) -> float:
    # Estimate based on soldier count and formation type
    var info = FormationData.get_formation(regiment.current_formation)
    var cols: int = ceili(float(regiment.current_soldiers) / float(info.rows))
    return cols * info.spacing * info.frontage_mult
```

#### 4.3 Toggle Controls
Add to Unit Zoo:
```gdscript
# In _input() handler
elif event.keycode == KEY_F:
    _toggle_formation_debug()

var _formation_debug_overlay: FormationDebugOverlay = null

func _toggle_formation_debug() -> void:
    if not _formation_debug_overlay:
        _formation_debug_overlay = FormationDebugOverlay.new()
        _formation_debug_overlay.name = "FormationDebugOverlay"
        unit_container.add_child(_formation_debug_overlay)
    _formation_debug_overlay._enabled = not _formation_debug_overlay._enabled
    print("[UnitZoo] Formation debug %s" % ("ENABLED" if _formation_debug_overlay._enabled else "DISABLED"))
```

---

## Implementation Order

### Priority 1: Verification (Quick Wins)
1. Test existing 3D arrows in battle scene
2. Test SelectionManager click-select in Unit Zoo
3. Test FormationDragHandler right-click move in Unit Zoo

### Priority 2: Unit Zoo Full Control
4. Ensure mouse events pass through to autoloads
5. Add any missing viewport coordinate conversion
6. Test complete RTS control flow in Unit Zoo

### Priority 3: Debug Visualizations
7. Create FormationDebugOverlay class
8. Implement formation front arrow
9. Implement melee engagement box
10. Add toggle hotkey (F key)

### Priority 4: Arrow Enhancements (Optional)
11. Add volley scatter for multiple arrows
12. Implement high/low arc calculation
13. Add arrow drop-off at max range

---

## Files to Create/Modify

### New Files:
- `battle_system/debug/formation_debug_overlay.gd` - Debug visualization

### Files to Modify:
- `scenes/unit_zoo_controller.gd` - Add debug toggle, verify mouse passthrough
- `battle_system/nodes/projectile.gd` - (Optional) Enhance trajectory calculations
- `battle_system/ai/commander/regiment_firing.gd` - (Optional) Volley scatter

---

## Testing Checklist

### 3D Arrows
- [ ] Arrows visible as 3D models in flight
- [ ] Arc trajectory looks natural (parabolic)
- [ ] Arrow rotates to face direction of travel
- [ ] Trail particles follow arrow
- [ ] Arrows return to pool correctly

### Unit Zoo Control
- [ ] Left-click selects regiment
- [ ] Drag-select multiple regiments
- [ ] Right-click terrain moves selected
- [ ] Right-click enemy orders attack
- [ ] Formation hotkeys work (F1-F4)
- [ ] Stance hotkeys work (Z/X/C/V)
- [ ] Control groups save/recall (Ctrl+1-9, 1-9)

### Debug Visualizations
- [ ] F key toggles debug overlay
- [ ] Arrow shows facing direction for selected units
- [ ] Melee box appears when regiment is ENGAGING
- [ ] Overlays update in real-time as units move

---

## Sources

- [ForrestTheWoods - Solving Ballistic Trajectories](https://www.forrestthewoods.com/blog/solving_ballistic_trajectories/)
- [GDQuest - Ranged Attacks Guide](https://www.gdquest.com/library/ranged_attacks/)
- [Godot Recipes - Ballistic Bullet](https://kidscancode.org/godot_recipes/3.x/2d/ballistic_bullet/index.html)
- [Total War Center - Projectile Guide](https://www.twcenter.net/threads/a-guide-on-the-descr_projectile-txt.468257/)
- [GameDev.net - Projectile Motion](https://www.gamedev.net/blogs/entry/2259073-projectile-motion/)
- [Unity Forum - Debug.DrawArrow](https://forum.unity.com/threads/debug-drawarrow.85980/)
- [Vertx.Debugging - Unity Gizmo Library](https://github.com/vertxxyz/Vertx.Debugging)
