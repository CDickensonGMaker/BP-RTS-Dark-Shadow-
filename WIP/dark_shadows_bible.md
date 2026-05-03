# Dark Shadows — Game Design Bible

A 90s-inspired Total War-style RTS. This document is the canonical reference for game systems, intended to be consumable in sections by either humans or AI development agents working on individual subsystems.

---

## How to use this document

Each major system has its own section with:
- **Purpose** — what the system does in plain language
- **Player-facing behavior** — what the player sees and does
- **Technical contract** — what other systems can expect from it
- **Implementation notes** — the actual how
- **Dependencies** — what this system needs to exist first

If you're an AI agent working on a single section, you should be able to read just that section plus its listed dependencies and have everything you need. Cross-references use section numbers (e.g. "see §4.2") so you know exactly where to look.

---

## Table of Contents

1. [Game Pillars and Scope](#1-game-pillars-and-scope)
2. [Core Battle Loop](#2-core-battle-loop)
3. [Unit System](#3-unit-system)
4. [Selection and Control](#4-selection-and-control)
5. [Formations](#5-formations)
6. [Pathfinding and Movement](#6-pathfinding-and-movement)
7. [Combat and Morale](#7-combat-and-morale)
8. [Enemy AI](#8-enemy-ai)
9. [Deployment Phase](#9-deployment-phase)
10. [Sieges](#10-sieges)
11. [Special Units and Abilities](#11-special-units-and-abilities)
12. [Stances: Guard, Hold, Skirmish](#12-stances)
13. [Control Groups (Saveable Groups)](#13-control-groups)
14. [Meta Layer: Economy and Building](#14-meta-layer)
15. [Camera and UI](#15-camera-and-ui)
16. [Audio](#16-audio)
17. [Save System](#17-save-system)
18. [Technical Architecture](#18-technical-architecture)
19. [Build Order and Milestones](#19-build-order-and-milestones)

---

## 1. Game Pillars and Scope

Three pillars. Every design decision should serve at least one; if a feature serves none, cut it.

**Pillar 1: Tactical positioning matters more than clicking speed.** This is not StarCraft. Battles are won by good deployment, formation discipline, and reading the enemy — not APM. If a player who positions well loses to a player who clicks faster, the design is broken.

**Pillar 2: Battles tell stories.** A unit's history matters. Veterans feel different from levies. A routed unit that rallies is a moment. The player should be able to describe a battle afterward in narrative terms ("my left flank held while the cavalry circled around"), not just in stats.

**Pillar 3: 90s readability.** Clean silhouettes, distinct unit colors, chunky UI, fixed-resolution feel. A new player should be able to identify every unit type on screen at a glance. No modern over-shaders, no clutter.

### Scope guardrails

| In scope | Out of scope |
|----------|--------------|
| Real-time battles, 200-1500 men typical | MMO / multiplayer at launch (post-launch maybe) |
| Simple meta layer (economy, recruitment, map progression) | Full Total War campaign map with diplomacy, agents, etc. |
| 4-6 factions with distinct rosters | Mod tooling at launch |
| Land battles, sieges (assault and defend) | Naval battles |
| Single-player skirmish + campaign | Procedural battle generation |

**Scope reminder:** every "could we also" idea gets parked in a separate doc. The bible only describes what's being built.

---

## 2. Core Battle Loop

The atomic gameplay unit is one battle. A battle goes:

```
Pre-battle briefing
   ↓
Deployment phase (§9)
   ↓
Battle proper
   ├── Maneuver
   ├── Engagement
   ├── Rout / decisive moment
   └── Pursuit / consolidation
   ↓
Post-battle resolution
   ├── Casualty calculation
   ├── Veterancy gain (§3.4)
   ├── Loot / capture
   └── Return to meta layer (§14)
```

### Briefing

Static screen. Shows:
- Battle objective (defeat enemy / hold position / capture point)
- Enemy composition (rough — "approximately 800 men, mostly infantry")
- Map terrain preview
- Time of day / weather (affects visibility, movement)
- Reinforcement timing if any

Briefing is skippable. Not skippable on first encounter with a new enemy faction (lore beat).

### Battle proper

No fixed time limit by default. Optional difficulty modifier: "must achieve objective by sunset" for some scenarios.

Win conditions checked every 2 seconds:
- Enemy army routed (>70% of starting strength fled or dead)
- Objective completed (varies by battle)
- Player army destroyed (lose)
- Player general killed (in some battles, instant lose)
- Time expired (some battles)

### Pursuit

When the enemy is routing, surviving routed units that escape the map become "scattered" rather than killed in the meta layer — they may rejoin their faction at reduced strength later. This is a *deliberate* design choice: total annihilation is rare, and pursuit is a player choice with tradeoffs (see §7 morale).

### Post-battle

Casualty screen shows:
- Per-unit losses (men killed, men recoverable from wounded pool)
- Veterancy gained
- Heroes/officers killed
- Loot acquired

Then back to meta layer (§14).

---

## 3. Unit System

### 3.1 What a "unit" is

A **unit** is a regiment of 60-200 individual soldiers acting as one tactical entity. The player commands units, not individual soldiers. Soldiers within a unit are simulated individually for visuals, combat resolution, and morale (§7), but receive orders collectively from their unit.

### 3.2 Unit categories

| Category | Role | Examples |
|----------|------|----------|
| **Light Infantry** | Cheap line-holders, screen, pursuit | Levy spearmen, militia |
| **Heavy Infantry** | Anchor of the battle line | Men-at-arms, swordsmen |
| **Pikemen / Spearmen** | Anti-cavalry, defensive | Pike block, spear wall |
| **Light Cavalry** | Skirmish, pursuit, flanking | Hobilars, scouts |
| **Heavy Cavalry** | Decisive charge | Knights, lancers |
| **Archers** | Ranged, ammo-limited | Longbow, shortbow |
| **Skirmishers** | Mobile ranged, harass | Javelins, slingers |
| **Special** | Faction-defining (§11) | Faction-dependent |

Six categories is the minimum. Don't add a seventh without cutting one — readability (Pillar 3) suffers fast with more.

### 3.3 Unit stats (canonical)

```
- Name, faction, category
- Soldier count (current / max)
- Melee attack
- Melee defense
- Charge bonus (cavalry only)
- Ranged attack
- Range (meters)
- Ammo (if ranged)
- Armor
- Shield (yes/no, affects frontal projectile defense)
- Movement speed (walk / run / charge)
- Morale base (§7)
- Bravery modifier (per-unit-type, see §7 morale_constants)
- Veterancy level (0-3)
- Cost (recruitment cost in meta layer)
- Upkeep (per-turn cost)
```

Keep this list locked. Adding a new stat means touching every unit definition; if you find yourself wanting one, you probably want a *modifier* (see §11) instead.

### 3.4 Veterancy

Units gain veterancy by surviving battles and inflicting casualties. Levels:

- **0 — Fresh:** No bonuses
- **1 — Blooded:** +5% melee, +5 morale
- **2 — Veteran:** +10% melee, +10 morale, +5% ranged
- **3 — Elite:** +15% melee, +15 morale, +10% ranged, visual badge

Veterancy is per-unit, persists across battles. A unit reduced to <30% strength and replenished with new recruits drops one veterancy level. This makes preserving veteran units a real strategic concern.

### 3.5 Reinforcement / replenishment

Units below max strength refill in the meta layer over time when stationed at friendly settlements. Replenishment rate depends on settlement type and faction (§14).

### Dependencies

This section depends on §14 (meta layer for cost/recruitment). Combat stats are consumed by §7.

---

## 4. Selection and Control

### 4.1 Selection methods

Three ways to select units:

1. **Single-click** on a unit selects only that unit (deselects others)
2. **Click-and-drag selection box** ("scroll box") selects all units intersected by the box
3. **Double-click** on a unit selects all units of the same type on screen
4. **Control group recall** (§13) — number key recalls saved group

**Modifiers:**
- `Shift+click` — add unit to selection
- `Ctrl+click` — remove unit from selection
- `Alt+click` — select all units of that type on screen (alternative to double-click)

### 4.2 Selection box ("scroll box") implementation

Drag-select with left mouse button on empty terrain. While dragging:
- Render a translucent rectangle on screen
- Every 100ms, project the rectangle into world space and check which units' bounding circles intersect
- Provide visual feedback — units inside the box highlight in real time (don't wait until release)

On release:
- Confirm selection with all units intersected
- If `Shift` held, add to existing selection rather than replacing

**Edge case:** drag from off-unit empty terrain only. Drag starting on a unit should be either (a) repositioning that unit, or (b) doing nothing — never reinterpret as a select-box.

### 4.3 Selection visualization

Selected units show:
- Colored circle/oval at their feet (faction color, slightly thickened)
- Health bar above unit (only when selected, or when damaged below 100%)
- Unit card highlighted in the bottom UI panel

Up to 12 units can be in the bottom panel at once. More than 12 selected, the panel paginates with arrows. (Don't try to fit 30 unit portraits on screen — readability dies.)

### 4.4 Issuing orders

With unit(s) selected:
- **Right-click on terrain** → move there (§6)
- **Right-click on enemy unit** → attack-move toward and engage that unit
- **Right-click and hold + drag** → move to position with custom formation width/facing (§5.3)
- **Right-click on friendly unit** → no default action (reserved for special abilities like "join formation")
- **Hotkeys** for stance changes (§12), formation changes (§5), abilities (§11)

### Dependencies

§4 depends on §3 (units exist), §5 (formations for stretch-drag), §6 (movement orders).

---

## 5. Formations

### 5.1 Formation types

| Formation | Description | Available to |
|-----------|-------------|--------------|
| **Line** | Default. Wide, 2-3 ranks deep | Infantry, Archers |
| **Column** | Narrow, deep. Fast travel, weak combat | All |
| **Square** | Hollow square, all-around facing | Infantry, Spearmen |
| **Wedge** | Triangle, breakthrough bonus | Cavalry only |
| **Loose** | Spread out, reduced missile casualties | Skirmishers, Archers |
| **Shield Wall** | Tight, slow, frontal defense bonus | Heavy Infantry only |
| **Schiltron / Pike Square** | Anti-cavalry braced position | Pikemen only |

Each formation has:
- A slot template (grid of relative positions for soldiers)
- Movement speed modifier
- Combat stat modifiers (front/flank/rear)
- Allowed unit types

### 5.2 Default formations per type

When a unit is recruited or given no specific formation:
- Light Infantry → Line
- Heavy Infantry → Line
- Pikemen → Line (transitions to Schiltron when threatened)
- Cavalry → Line (transitions to Wedge on charge order)
- Archers → Loose
- Skirmishers → Loose

### 5.3 Drag-to-stretch (Total War style)

When the player right-clicks and *holds* on terrain with units selected:

1. Place a phantom formation marker at the click position
2. As the player drags, the second point defines:
   - **Distance from click point** = formation width
   - **Direction from click point** = formation facing
3. Render a translucent preview of where soldiers will end up
4. On release, issue the move order with that formation shape

```
Player presses RMB at point A
Player drags to point B (still holding)
   ↓
The line from A to B becomes the FRONT RANK of the formation,
with A as the left flank and B as the right flank.
   ↓
Formation faces 90° to the line A→B (perpendicular, "outward")
```

**Width clamping:** formations have a minimum width (no thinner than 1 rank deep) and a maximum width (no wider than the soldier count allows). If the player drags too wide, the formation hits max and stops stretching.

**Multi-unit drag:** if multiple units are selected, the drag distributes them along the line A→B in their selection order, each with width proportional to its soldier count.

### 5.4 Formation transitions

Changing formation is not instant. Soldiers must reassign slots and walk to them. During transition:
- Unit moves at reduced speed
- Combat effectiveness reduced 30%
- Cannot charge
- Vulnerable to attack

This is intentional — switching formation under fire is risky and should require tactical awareness.

### Dependencies

§5 depends on §3 (unit types), §6 (soldiers move to slots).

---

## 6. Pathfinding and Movement

### 6.1 Two-tier pathfinding

This is the single most important architectural decision for performance. Do not run A* per soldier.

**Tier 1: Unit anchor pathfinding.** The unit has a single "anchor" point (its center). A* runs on the navmesh from current anchor to destination. Path is cached.

**Tier 2: Soldier steering.** Each soldier has a target slot (relative to the anchor's current position along the path). Soldiers use steering behaviors (seek, separation, alignment) to reach their slot. They do not pathfind individually.

This means a 200-soldier unit costs ~1 A* call, not 200.

### 6.2 Navmesh

Generated at battle start from the terrain mesh:
- Walkable surface flagged (slope, terrain type)
- Obstacles (trees, rocks, buildings) cut out
- Faction-specific obstacles (enemy units block, allied units don't unless dense)

Use Godot's built-in `NavigationServer3D` for the navmesh. It's good enough; don't reinvent.

### 6.3 Movement speeds

Three speeds:
- **Walk** (default): full formation discipline maintained
- **Run** (held shift, or auto when "engage" order issued): formation looser, stamina drains
- **Charge** (cavalry-specific): max speed, formation breaks to wedge if not already, stamina drains fast

Stamina:
- Full at battle start
- Drains during run/charge
- Recovers when walking or stationary
- At zero stamina: forced walk, combat penalty until recovered

### 6.4 Right-click move

```
Player right-clicks at point P with units U1...Un selected
  ↓
For each unit:
   - Compute its destination D_i (with formation offset for multi-unit moves)
   - Request path from current anchor to D_i
   - Set unit state to MOVING
  ↓
Render move marker at P (brief flash, faction color)
```

**Attack-move:** if `A` is pressed before the click, units engage any enemy along the path rather than running past. This is critical for the player not having to micromanage every engagement.

### 6.5 Collision and pushing

Soldiers separate from each other via steering. Soldiers from different units do *not* pass through each other in melee (they fight). Outside melee, friendly units can pass through each other slowly (penalty to movement speed for both).

Cavalry charging into an enemy unit causes a "shock" — front-rank enemies are knocked back/down briefly, taking the charge bonus damage.

### Dependencies

§6 depends on §3 (units exist), §5 (formation slots define soldier targets). Consumed by §7 (combat triggers when units in contact).

---

## 7. Combat and Morale

(See the standalone `morale_system_godot.md` document for the full implementation. This section describes how it integrates with the rest of the game.)

### 7.1 Combat resolution

**Hybrid model** (decided in original AI doc):
- **Melee:** simulated. Each soldier picks a specific opponent and rolls attack vs defense. Damage applies vs armor.
- **Ranged:** statistical for performance. A volley computes total expected damage based on unit stats, distance, accuracy modifiers, then distributes across the target unit. Visual arrows are spawned for show but don't carry damage.

Combat ticks at 4 Hz (every 250ms) per soldier in melee. This is plenty for animation timing and reduces compute vs per-frame.

### 7.2 Morale integration

Morale is tracked per soldier, averaged per unit. Key event sources:
- Friend killed nearby
- Cavalry charge incoming/impact
- Flanked or rear-attacked
- Friendly unit routing nearby
- General killed (army-wide)
- Officer killed (unit-wide)
- Outnumbered locally
- Winning locally

Unit states: **Steady → Wavering → Shaken → Broken**. Broken units rout (flee toward map edge or friendly lines) and can rally if reaching safety near a general for ~5 seconds.

Combat effectiveness multiplier by state: Steady 1.0, Wavering 0.9, Shaken 0.75, Broken 0.3.

### 7.3 Pursuit

When an enemy unit routs, friendly units will *automatically* pursue if their stance is "Aggressive" (§12), or remain in position if "Defensive." This is a player choice — pursuing units get free kills but disorganize the line and may be drawn out of position.

### Dependencies

§7 depends on §3 (unit stats), §4 (orders), §6 (units in contact). Consumed by §8 (AI reads morale state).

---

## 8. Enemy AI

(See the standalone `enemy_ai_system.md` document for the full architecture.)

### 8.1 Three-tier summary

- **General AI (strategic):** picks a "play" from a library (Pin and Flank, Defensive Line, Hammer and Anvil, etc.) using a utility scoring system. Reassesses every ~5 seconds.
- **Commander AI (tactical):** per-unit behavior tree executing the General's orders, with priority overrides for emergencies (cavalry charge incoming, morale broken).
- **Soldier AI (behavioral):** dumb, cheap, executes its slot assignment and current target.

### 8.2 Difficulty scaling

Three difficulty levels affect the AI:

| Difficulty | General | Commander | Bonus |
|-----------|---------|-----------|-------|
| Easy | Picks plays randomly from top 3 scoring | 1s reaction time | None |
| Normal | Picks best play | 0.5s reaction time | None |
| Hard | Picks best play, considers 2 moves ahead | 0.2s reaction time | +10% morale, +5% combat |

Avoid stat-bloat as the primary difficulty knob. Smarter AI > tougher AI.

### 8.3 Faction personalities

Each AI faction has a personality preset that biases play scoring:
- **Aggressive:** offensive plays score +20%, retreat scores -50%
- **Defensive:** holds and counter-attack plays score higher
- **Cavalry-focused:** flanking plays score higher, prefers light infantry as pinning force
- **Methodical:** prefers Defensive Line, Hammer and Anvil; avoids high-risk plays

### Dependencies

§8 depends on §3, §6, §7. Heaviest dependency is §7 (morale state drives most decisions).

---

## 9. Deployment Phase

### 9.1 What happens

Before the battle starts, the player has unlimited time to position their army within a designated **deployment zone** (typically the player's edge of the map). The AI also pre-positions within its own zone, but the AI's deployment is computed and final by the time the player's deployment phase begins.

### 9.2 Player actions during deployment

- Drag units anywhere within the deployment zone
- Change formations
- Save groups (§13)
- Set initial stances (§12)
- Preview enemy starting positions if scouted (varies by battle)

UI shows:
- Deployment zone outlined on the ground (translucent colored overlay)
- "Begin Battle" button (bottom right)
- Time of day, weather, terrain notes
- Mini-map with both deployment zones visible

### 9.3 AI deployment logic

When the battle is generated:
1. AI evaluates the map (chokepoints, high ground, cover)
2. Picks a deployment "shape" based on personality (defensive line, forward aggressive, refused flank, etc.)
3. Slots units into the shape based on type:
   - Heavy infantry center
   - Pikemen anchoring flanks (or center if anti-cav role)
   - Archers behind infantry
   - Cavalry on flanks or held in reserve
   - Skirmishers forward of the line
   - General with reserves or behind line

This runs once at battle generation, not in real-time. AI does not re-deploy in response to player deployment.

### 9.4 Pre-battle scouting

Some battles allow scouting before deployment. Scouted enemy units show their positions and types in the deployment phase preview. Unscouted enemies show a "fog" zone with rough numbers only.

Scouting comes from the meta layer (sending scouts before engaging — see §14).

### Dependencies

§9 depends on §3, §4, §5, §13, §14.

---

## 10. Sieges

Sieges are a special battle type with distinct rules. Two sides: attacker and defender.

### 10.1 Siege battle layout

A walled settlement with:
- Outer walls (segments, each with HP)
- Gates (HP, can be broken or opened)
- Towers (provide ranged firing positions, take damage from siege weapons)
- Inner keep (final objective for attacker)
- Streets and buildings inside (cover, choke points)

### 10.2 Attacker tools

- **Siege engines:** ladders, siege towers, battering rams, trebuchets
  - Built between meta-layer turns or before battle, time-cost
  - Trebuchets damage walls/towers from range
  - Ladders allow infantry to climb walls (slow, vulnerable while climbing)
  - Siege towers move infantry to wall-top safely (slow movement)
  - Rams break gates (slow, vulnerable to oil/arrows from above)
- **Sappers / mining** (optional advanced feature): tunnel under walls to collapse a section. Long timer, vulnerable.

### 10.3 Defender tools

- **Wall-mounted archers:** firing from elevated positions, range bonus, harder to hit
- **Boiling oil / hot sand:** poured on units climbing walls or breaking gates (consumable, limited per battle)
- **Murder holes:** specific wall segments with bonus defense
- **Fall-back positions:** if outer wall falls, defenders retreat to inner keep

### 10.4 Siege win conditions

- **Attacker wins** by capturing the inner keep (hold a control point for 60 seconds, or kill all defenders inside)
- **Defender wins** by destroying all attacker siege equipment AND reducing attacker army below 25% strength
- **Time-based:** if the attacker is besieging from the meta layer (not assaulting), defender starves out after N turns unless relieved

### 10.5 Pathfinding for sieges

Sieges break the standard navmesh because walls are dynamic (segments can be destroyed). Implementation:
- Multi-layer navmesh (ground level, wall-top level, with connections at stairs/towers/ladders)
- When a wall segment is destroyed, the navmesh updates locally and creates a connection through the breach
- Siege engines have unique pathing rules (ladders attach to specific wall segments; siege towers move along ground until docking)

This is the most technically complex section of the bible. Build it last.

### Dependencies

§10 depends on §3, §6, §7. Adds ~2-3 months to development if done well.

---

## 11. Special Units and Abilities

### 11.1 What makes a unit "special"

Special units are faction-defining and break standard rules in interesting ways. Each faction has 1-3 special units. Examples (deliberately generic — fill in with your factions):

- **Faction A (heavily armored knights):** "Sworn Brothers" — heavy cav with formation bonus when fighting near each other
- **Faction B (mobile skirmishers):** "Horse Archers" — cavalry that can fire on the move
- **Faction C (defensive footmen):** "Old Guard" — heavy infantry with morale cap (cannot drop below Wavering)

### 11.2 Active abilities

Some units have active abilities triggered by hotkey:

| Ability | Effect |
|---------|--------|
| **Volley fire** | Archers hold fire until command, then fire synchronized salvo (more morale damage) |
| **Brace** | Infantry/spearmen plant against incoming charge (huge bonus vs cavalry) |
| **War cry** | General's ability — +morale to nearby units for 30s, cooldown |
| **Charge** | Cavalry — speed boost and damage spike, requires run-up |
| **Form schiltron** | Pikemen pack into anti-cav square (40% slower, immune to charge bonus) |

Each ability has:
- Cooldown
- Resource cost (none by default, but stamina or morale possible)
- Visual/audio cue when triggered

### 11.3 Heroes / Generals

Each army has one general (sometimes a hero). The general:
- Provides morale aura (§7)
- Has unique abilities (war cry, etc.)
- If killed, army-wide morale shock
- Has personality affecting AI plays (player generals don't, this is for AI)
- Can be wounded vs killed in battle (post-battle resolution)

### Dependencies

§11 depends on §3, §7, §12.

---

## 12. Stances

A stance is a per-unit toggle that modifies the unit's reactive behavior when not actively given an order. Three stances:

### 12.1 Aggressive (default for most units)

- Pursues fleeing enemies
- Engages enemies that come into range without orders
- Archers fire at any enemy in range
- Cavalry will charge incoming charges

### 12.2 Defensive

- Holds position
- Engages only enemies that come within close range
- Does not pursue fleeing enemies
- Archers fire only at enemies threatening the unit's position

### 12.3 Hold Fire / Skirmish

- For ranged units: do not fire until ordered (saves ammo)
- For skirmishers: maintain distance from approaching enemies, fire while retreating
- For melee units: equivalent to Defensive

### 12.4 Guard

A special order, not exactly a stance: "guard unit X." The guarding unit follows X's movement and defends X from attackers, taking attack-move priority on threats to X.

Use case: protect your archers from cavalry by guarding them with pikemen.

### Dependencies

§12 depends on §3, §4, §6.

---

## 13. Control Groups

### 13.1 Saving and recalling groups

Standard RTS pattern:
- `Ctrl+1` through `Ctrl+0` saves currently selected units as a control group
- `1` through `0` selects the saved group
- Double-tap `1` selects the group AND centers camera on them
- `Shift+1` adds the group to the current selection without replacing

Groups persist across the battle. They do NOT persist across battles (units may be lost or replaced). Saved groups are stored as references to unit IDs; if a unit is destroyed, it's silently removed from the group.

### 13.2 Group composition recommendations

These are tooltips/UI hints, not enforced:
- Mixed groups (infantry + ranged) work as combined arms
- Cavalry-only groups are best for flanking maneuvers
- Pure ranged groups need protection — consider mixing with melee

### 13.3 UI

Selected groups show a small icon at the top of the screen with:
- Group number
- Group composition icon (cav/inf/ranged mix indicator)
- Average health bar
- Status (engaged, moving, idle)

Click the icon to select the group; right-click the icon for group options (rename, dissolve, etc. — minor feature, post-launch).

### Dependencies

§13 depends on §4.

---

## 14. Meta Layer

The strategic layer between battles. Deliberately scoped down from full Total War — this is a 90s game.

### 14.1 Structure

A simple map with locations connected by paths. Locations are settlements (towns, cities, fortresses) and points of interest. The player has an army (or armies) that moves between locations.

Two modes considered, pick one in production:

**Option A: Linear chapter map.** Hand-authored campaign with fixed battles. Player progresses through battles in a set order, with some choice of paths. Simpler, faster to build, gives narrative control. **Recommended for first release.**

**Option B: Sandbox map.** Open map with multiple factions, dynamic events. Much more work, more replayability. Save for sequel/expansion.

### 14.2 Settlement types

- **Village:** generates small income, recruits levies, low replenishment
- **Town:** medium income, recruits standard troops, moderate replenishment
- **City:** high income, recruits special units, high replenishment
- **Fortress:** moderate income, recruits elite units, walls for siege defense
- **Capital:** highest income, all unit types, walls, lose = lose campaign

### 14.3 Economy

Single resource: **Gold.**

Per-turn income:
```
Income = sum of (settlement_income for each owned settlement)
       - sum of (unit_upkeep for each unit in your armies)
       - sum of (building_upkeep)
```

If income goes negative, the player can take debt for a few turns; sustained debt causes morale penalties (unpaid soldiers) and eventually unit defections.

### 14.4 Buildings

Each settlement has a build queue with limited slots (3-5 depending on size). Building types:

| Building | Effect |
|----------|--------|
| **Walls** | Defensive bonus in siege |
| **Barracks** | Recruits basic infantry |
| **Stables** | Recruits cavalry |
| **Archery Range** | Recruits archers |
| **Smithy** | Better equipment (combat stat bonuses to recruited units) |
| **Market** | Income bonus |
| **Watchtower** | Scouting range bonus, advance warning of enemy approach |
| **Temple / Morale building** | Morale bonus to garrisoned units, faction-specific name |

Buildings take 1-3 turns to construct. Higher-tier buildings require prerequisites (e.g., need Barracks before Smithy).

### 14.5 Recruitment

Recruit units at settlements. Each unit type has:
- Gold cost
- Turns to recruit (1-3 typically)
- Settlement requirement (need Stables for cavalry, etc.)
- Population requirement (settlement has a soft cap on units recruitable per turn)

### 14.6 Army movement

Armies move on the map a fixed number of "movement points" per turn. Different paths cost different amounts (roads cheap, mountains expensive). When two opposing armies meet, a battle is triggered.

If the player's army moves into an enemy settlement, it triggers a siege (§10) or open battle if no walls.

### 14.7 Turn structure

Each turn:
1. Player phase: move armies, build, recruit, manage
2. Resolve any battles triggered by player actions
3. AI phase: AI factions take their actions
4. Resolve any battles triggered by AI actions
5. End-of-turn: income, replenishment, building completion, events

### Dependencies

§14 depends on §3 (units exist). Required by §9 (some battles need pre-battle context like scouting).

---

## 15. Camera and UI

### 15.1 Camera

RTS-standard:
- WASD or screen-edge scroll
- Mouse wheel zoom (clamped — not too close, not too far)
- Right mouse drag for camera rotation (optional, can be disabled)
- Spacebar to center on currently selected unit
- Home key to center on player's general

Camera does NOT auto-follow units. Player keeps full control. Auto-follow is a setting that's off by default.

### 15.2 UI layout

```
┌─────────────────────────────────────────────────────────────────┐
│  [Time/Weather]                              [Group icons 1-0]  │
│                                                                  │
│                                                                  │
│                       BATTLE VIEW                                │
│                                                                  │
│                                                                  │
│                                                                  │
│  ┌─────────┬─────────────────────────────────────────┬───────────┐  │
│  │         │                                      │           │  │
│  │  MINI   │     SELECTED UNIT CARDS (up to 12)  │  ABILITY  │  │
│  │   MAP   │  [unit][unit][unit][unit][unit]...  │   PANEL   │  │
│  │         │                                      │           │  │
│  └─────────┴─────────────────────────────────────┴───────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

Each unit card shows:
- Unit portrait (faction color background)
- Soldier count (current/max)
- Health bar
- Stamina indicator
- Morale indicator (color-coded)
- Stance icon
- Status icons (in formation, charging, routing, etc.)

Click a unit card to select that unit; double-click to center camera on it.

### 15.3 Keybinds (default)

```
LMB:           select / drag-select
RMB:           move / attack-move / formation drag
RMB+drag:      formation stretch (§5.3)
A + click:     attack-move
S:             stop
G:             guard mode (next click selects target to guard)
F:             face direction (drag to set facing)
H:             halt (cancel current order)
Tab:           cycle through selected units
Space:         center on selection
F1-F4:         formation hotkeys (line, column, square, special)
Ctrl+1-0:      save group
1-0:           recall group
Shift+1-0:     add group to selection
Esc:           pause menu
Backtick (`):  toggle UI (for screenshots)
```

All keybinds remappable from the options menu.

### Dependencies

§15 depends on §4, §5, §13.

---

## 16. Audio

### 16.1 Layers

Audio in an RTS does heavy lifting for feedback and atmosphere. Five layers, mixed independently:

1. **Music:** dynamic, escalating with battle intensity
2. **Ambient:** environmental loops (wind, birds, distant thunder), terrain-dependent
3. **Unit chatter:** soldiers responding to orders, in-battle reactions
4. **Combat SFX:** weapon clashes, arrows, hooves, screams
5. **UI sounds:** clicks, alerts, notifications

### 16.2 Critical audio cues

The player should hear (and recognize without looking):
- A unit breaking / routing — distinct horror cue
- A unit being charged by cavalry — drum hit / horn
- A unit running out of ammo — quiet "click" or "empty quiver" sound
- Battle being won / lost — musical sting

### 16.3 Order acknowledgments

When the player issues an order to a unit, that unit's officer/leader voice-acks the command. This is critical 90s RTS feel ("Yes, my lord!"). Don't skip this. It also helps the player track which units they're commanding.

Lines should be:
- Short (<1.5s)
- Faction-specific accent/language
- Multiple variants per command (5+ to avoid repetition)
- Order types: select, move, attack, charge, retreat, formation-change, guard

### Dependencies

Standalone — depends on nothing structurally.

---

## 17. Save System

### 17.1 What gets saved

- Meta layer state (map, settlements owned, gold, buildings, recruitment queues)
- All army compositions (units, their veterancy, current strength)
- Campaign progress (battles completed, narrative flags)
- Settings

### 17.2 Save scopes

- **Auto-save** at end of each meta-layer turn
- **Manual save** anytime in meta layer
- **No saving in battle** (intentional — battles must be played to conclusion). Optional setting to allow battle saves for accessibility.
- **Quicksave / Quickload** for meta layer

### 17.3 Format

JSON for legibility during dev. Compress / migrate to binary post-launch if file size matters. Versioned save files (`save_version: 1.0`) so future patches can migrate old saves.

### Dependencies

§17 depends on every system that has state. Build last.

---

## 18. Technical Architecture

### 18.1 Engine: Godot 4.x

Justified by:
- GDScript fast iteration
- Good 3D support for Total War-style battles
- `NavigationServer3D` works for our two-tier pathfinding (§6)
- Free, no royalties
- C# escape hatch for perf-critical systems (soldier loop, combat resolution)

### 18.2 Language strategy

- **GDScript** for game logic, AI, UI, meta layer
- **C#** for performance-critical:
  - Soldier-level update loop
  - Combat resolution
  - Spatial queries
  - Pathfinding helpers (if Godot's nav is insufficient)

### 18.3 Data structures

Use ECS-style flat arrays for soldiers (cache coherency). Units, generals, and meta-layer entities can stay as Nodes — they're few enough that OOP doesn't hurt.

### 18.4 Tick rates

| System | Frequency |
|--------|-----------|
| Rendering | 60 Hz |
| Soldier animation / steering | 60 Hz |
| Soldier combat ticks | 4 Hz |
| Morale events | 4 Hz |
| Commander AI | 2-5 Hz |
| General AI | 0.5 Hz |
| Selection box check | 10 Hz |
| Save game (auto) | per meta turn |

### 18.5 Spatial query system

Required by morale (§7), AI target selection (§8), aura effects (§11). Implement as:
- Uniform grid (cell size ~10m) updated every 100ms
- Per-cell list of units/soldiers
- Radius queries iterate cells overlapping the radius

Don't use a quadtree for this — uniform grid is simpler and faster for the access pattern (lots of small radius queries).

### 18.6 Performance budget

Target: 60 FPS at 1500 soldiers on screen on mid-range hardware (2020-era GPU, 6-core CPU).

Per-frame budget:
- Rendering: 8ms
- Soldier steering / animation: 4ms
- Combat / morale ticks (when scheduled): 2ms peak
- AI (when scheduled): 1ms peak
- UI: 1ms

Total: ~16ms per frame for 60 FPS.

### Dependencies

This section is the foundation; everything else assumes these decisions.

---

## 19. Build Order and Milestones

Don't build top-down. Build vertically — get one thing working end-to-end, then expand. The path:

### Milestone 1: "Two units can fight" (2-4 weeks)
- One unit type
- Basic selection (click only)
- Right-click move with naive pathing
- Basic combat: two units in contact, soldiers attack each other
- Simple morale (just numeric, no states yet)
- Camera

**Win condition:** you can select a unit, send it into another unit, and watch them fight.

### Milestone 2: "Formations and selection" (3-5 weeks)
- Formation slots (line, column)
- Drag-select box
- Multiple units selectable
- Right-click formation drag (§5.3)
- Stance toggles
- Two unit types (heavy infantry + archers)

**Win condition:** you can drag-select 5 units, drag them into a line, and have them advance in formation.

### Milestone 3: "Real morale and AI" (4-6 weeks)
- Full morale system (per `morale_system_godot.md`)
- Commander behavior tree
- Routing, rallying
- Cavalry unit type with charge mechanics
- Basic enemy General AI (2-3 plays)

**Win condition:** you can fight a real battle against an AI opponent that makes recognizable tactical decisions, and units rout when they should.

### Milestone 4: "Deployment and full battle loop" (3-4 weeks)
- Deployment phase
- Pre-battle briefing
- Win condition checks
- Post-battle resolution
- Basic veterancy

**Win condition:** complete battles start to finish with proper bookends.

### Milestone 5: "Meta layer skeleton" (4-6 weeks)
- Linear campaign map
- Army movement
- Recruitment
- Income / upkeep
- Save/load
- Basic settlements

**Win condition:** play through a 5-battle campaign with persistent armies.

### Milestone 6: "Sieges" (6-8 weeks)
- Wall pathfinding
- Siege equipment
- Defensive abilities
- Siege win conditions

**Win condition:** assault a walled settlement and capture it.

### Milestone 7: "Special units, full roster, polish" (open-ended)
- Faction rosters complete
- Special units and abilities
- Hero/general system
- Audio pass
- UI polish
- Tutorial

### Milestone 8: "Content and balance" (open-ended)
- Campaign content
- Balance pass
- Bug fixing
- Difficulty tuning

---

## Appendix A: Naming this document's owner

This bible is the source of truth for game design. When a question comes up that the bible doesn't answer:

1. Check if it's actually a design question or an implementation question
2. If design: it goes here, and the bible is updated
3. If implementation: it goes in code comments and dev notes

When the bible and a piece of code disagree, the bible wins until the bible is explicitly updated. Don't drift.

---

## Appendix B: Decisions deferred

Things the bible deliberately does not decide yet, with notes on when to decide:

- **Multiplayer:** post-launch
- **Modding tools:** post-launch
- **Naval battles:** sequel
- **Dynamic campaign map (sandbox):** sequel
- **Number of factions in v1:** decide at start of M3
- **Historical setting vs fully fictional:** decide before content production
- **Art style specifics (low-poly PS1 vs higher-fidelity 90s vs stylized modern):** decide before M2 art begins

---

## Appendix C: Companion documents

Implementation deep-dives that complement this bible:

- `enemy_ai_system.md` — full AI architecture (consumed by §8)
- `morale_system_godot.md` — Godot implementation (consumed by §7)
- (Future) `formation_steering.md` — soldier slot assignment and steering
- (Future) `siege_pathfinding.md` — multi-layer navmesh details
- (Future) `combat_resolution.md` — melee/ranged math and balancing

Each companion doc should reference back to its bible section number so the relationship is bidirectional.
