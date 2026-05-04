# Divide et Impera Analysis - Lessons for Dark Shadows RTS

## Overview

Analysis of DEI (Divide et Impera) mod for Rome 2 Total War, extracting game design patterns applicable to our RTS battle system and future campaign layer.

---

## 1. SUPPLY SYSTEM (Campaign)

DEI implements a sophisticated supply system that affects army health and effectiveness.

### Key Mechanics Found:

```lua
-- Army supply cost calculation
function SupplyArmySize(military_force)
    local supply_points = military_force:unit_list():num_items()

    for i = 0, force:unit_list():num_items() - 1 do
        local unit = force:unit_list():item_at(i)

        -- Elephants cost extra supply
        if Unit_Is_in_Unit_List(unit:unit_class(), elephant_class_list) then
            supply_points = supply_points + 4
        end

        -- Cavalry costs extra supply
        if Unit_Is_in_Unit_List(unit:unit_class(), cavalry_class_list) then
            supply_points = supply_points + 1
        end
    end
    return supply_points
end
```

### Supply Variables Identified:
- `Supply_Base` - Base supply generation
- `Supply_Cap` - Maximum supply storage
- `Supply_Usage` - Current consumption rate
- `Supply_Exports` / `Supply_Imports` - Trade between regions
- `SupplyBuildings` - Buildings that provide supply
- `Supply_Status` - Current supply state

### Attrition Types:
- **Summer Attrition** - Heat/desert regions
- **Winter Attrition** - Cold regions without winter gear
- **Siege Attrition** - Both besieged and besieging forces
- **Naval Attrition** - Ships at sea too long
- **Desertion** - Low morale triggers desertion attrition

### Design Lessons for Dark Shadows:
1. **Unit Type Affects Supply Cost** - Cavalry/monsters should cost more to maintain
2. **Regional Supply** - Each province generates supply based on buildings
3. **Supply Lines** - Friendly territory provides supply, enemy territory doesn't
4. **AI Immunity Period** - AI gets temporary immunity to prevent early game deaths

---

## 2. POPULATION SYSTEM (Campaign)

DEI tracks regional population that limits recruitment.

### Key Mechanics:

```lua
function AddPop(unitKey, soldierCount, regionName, character, factionName)
    -- Determine unit class (mercenary, citizen, etc.)
    local class = UIRetrieveClass(unitKey, factionName)

    -- Deduct from regional population
    local costs = (soldierCount * -1)
    region_table[regionName][class] = region_table[regionName][class] + costs

    -- Ensure non-negative
    region_table[regionName][class] = math.max(region_table[regionName][class], 0)
end
```

### Population Classes Found:
- Citizens (regular recruitment)
- Mercenaries (hired externally)
- Levies (conscripted)
- Auxiliaries (allied troops)

### Design Lessons for Dark Shadows:
1. **Regional Population Pool** - Each region has limited manpower
2. **Class-Based Recruitment** - Different unit types draw from different pools
3. **Population Recovery** - Regions slowly regenerate population
4. **War Impact** - Battles fought in region reduce population

---

## 3. MORALE SYSTEM (Battle)

DEI has extensive morale modifiers affecting unit performance.

### Morale Modifier Types Found (97 unique):

**Positive Modifiers:**
- `c_force_unit_mod_morale_own_territory` - Fighting in homeland
- `alex_hellenic_units_morale` - Cultural bonuses
- `c_faction_trait_roman_morale_own_or_allied` - Faction traits

**Negative Modifiers:**
- `desertion_morale_penalty_attrition_threshold` - Low supply = morale penalty
- `c_force_unit_mod_morale_enemy_territory` - Fighting in enemy land
- `c_force_unit_mod_morale_versus_romans` - Special penalties vs certain factions

**Unit Type Modifiers:**
- `c_force_unit_mod_cavalry_light_morale` - Light cavalry morale
- `c_force_unit_mod_heavy_infantry_morale` - Heavy infantry morale
- `dei_mod_morale_auxiliary` - Auxiliary unit morale

### Design Lessons for Dark Shadows:
1. **Territory Affects Morale** - Fighting at home vs enemy territory
2. **Unit Type Matters** - Heavy infantry more steadfast than light troops
3. **Faction Traits** - Each faction has unique morale modifiers
4. **Supply Link** - Low supply causes morale penalties

---

## 4. FATIGUE SYSTEM (Battle)

DEI implements detailed fatigue affecting combat and movement.

### Fatigue States Found:
- `FATIGUED_IDLE` - Standing while fatigued
- `RUN_FATIGUED` - Running while fatigued (slower)
- `WALK_FATIGUED` - Walking while fatigued
- `STEP_FORWARD_FATIGUED` - Combat movement fatigued
- `TURN_LEFT/RIGHT_FATIGUED` - Rotating while fatigued

### Key Tables:
- `DeI_kv_fatigue` - Key-value fatigue settings
- `DeI_unit_fatigue_effects` - Fatigue penalties by state

### Faction Resistances:
- `c_tech_military_fatigue_resistance_greuthungi`
- `c_tech_military_fatigue_resistance_tervingi`
- `c_tech_military_fatigue_resistance_land_units`

### Design Lessons for Dark Shadows:
1. **Fatigue Affects Everything** - Movement, combat, turning speed
2. **Tech/Traits Reduce Fatigue** - Some factions handle fatigue better
3. **Animation States** - Visual feedback for fatigue level
4. **Recovery** - Fatigue recovers when idle

---

## 5. BATTLE MODIFIERS

### Effect Bundle Categories Found:
- `dei_all_battles` - Always active in battles
- `dei_attacking_battles_all` - When attacking
- `dei_defensive_battles_all` - When defending
- `dei_major_settlement_battles_all` - Siege battles
- `dei_human_vs_ai_all_battles` - Player vs AI adjustments

### Combat Stat Modifiers:
- `dei_melee_inf_attack` - Infantry melee attack bonus
- `dei_melee_inf_def` - Infantry melee defense bonus
- `dei_melee_inf_dmg` - Infantry damage bonus
- `dei_melee_skirmisher` - Skirmisher melee stats
- `dei_faction_trait_charge` - Charge bonus by faction
- `dei_faction_trait_british_group_charge` - British charge bonus

### Battle Context Modifiers:
- Ground type affects combat
- Weather affects combat
- Battle type (field vs siege) affects stats

---

## 6. WEAPON SYSTEMS

### Weapon Table Types Found:
- `DeI_melee_weapons` - Melee weapon definitions
- `DeI_missile_weapons` - Ranged weapon definitions
- `missile_weapons_to_projectiles` - Projectile linking

### Weapon Categories:
- Infantry weapons (swords, spears, axes)
- Cavalry weapons (lances, javelins)
- Missile weapons (bows, crossbows, slings)
- Artillery (ballistae, catapults)

---

## 7. UNIT CLASSIFICATION SYSTEM

### Unit Classes Found:
- Infantry (Heavy, Medium, Light)
- Cavalry (Shock, Melee, Missile)
- Elephants (special class)
- Artillery

### Class Effects:
- Supply cost multiplier
- Population class drawn from
- Special combat modifiers

---

## 8. AI SYSTEM

### AI Functions Found:
- `AIFactionTurnStart` - AI planning at turn start
- `AIMoneyScript` - AI economy management
- `AIBonuses_Imperium` - AI difficulty bonuses
- `AIRemovePop` - AI population management
- `activate_attrition_for_ai` - AI attrition handling

### AI Balancing:
- AI gets temporary immunity to mechanics (attrition, supply)
- AI receives economy bonuses based on difficulty
- AI has special personality traits affecting behavior

---

## IMPLEMENTATION RECOMMENDATIONS FOR DARK SHADOWS

### Battle System (Current Focus):

1. **Fatigue Integration**
   - Already have StaminaSystem - enhance with DEI-style state effects
   - Add movement speed penalties per fatigue level
   - Add combat effectiveness penalties

2. **Morale Enhancement**
   - Add territory ownership check (if campaign layer exists)
   - Add faction trait modifiers
   - Add unit type specific morale modifiers

3. **Charge System**
   - Already have charge bonus - add faction-specific charge traits
   - Add charge distance requirements (already implemented)

### Campaign Layer (Future):

1. **Supply System**
   - Track army supply consumption
   - Cavalry/monsters cost extra
   - Supply from buildings + territory control
   - Attrition when supply runs out

2. **Population System**
   - Regional population pools
   - Class-based recruitment (citizens, mercenaries, levies)
   - Population recovery over time
   - Battle casualties affect regional pop

3. **Seasonal System**
   - Winter/Summer affects attrition
   - Weather affects battle performance
   - Seasonal events and mechanics

---

## RAW DATA TABLES FOUND

The following db tables were identified in the pack file:
- `land_units_tables` - Unit definitions
- `melee_weapons_tables` - Melee weapon stats
- `missile_weapons_tables` - Ranged weapon stats
- `unit_abilities_tables` - Unit special abilities
- `unit_armour_types_tables` - Armor definitions
- `unit_attributes_tables` - Unit attribute flags
- `battle_entities_tables` - Battle entity definitions
- `effect_bundles_tables` - Stat modifier bundles
- `_kv_morale_tables` - Morale key-value settings
- `_kv_fatigue_tables` - Fatigue key-value settings

Note: The actual numeric values are stored in binary format within the .pack file and require RPFM (Rusted Pack File Manager) to extract properly.

---

## DARK SHADOWS IMPLEMENTATION MAPPING

### Already Implemented (Compare to DEI)

| DEI Feature | Dark Shadows File | Status |
|-------------|-------------------|--------|
| Fatigue System | `battle_system/systems/stamina_system.gd` | ✅ 4 states matching DEI |
| Morale System | `battle_system/systems/unit_morale.gd` | ✅ Event-based modifiers |
| Charge Bonus | `battle_system/systems/combat_manager.gd` | ✅ Distance-based decay |
| Flanking Damage | `battle_system/systems/combat_manager.gd` | ✅ 1.0x/1.5x/2.0x |
| Formation Effects | `battle_system/data/formation_data.gd` | ✅ Speed/Attack/Defense mods |
| Combat Facing Lock | `battle_system/nodes/regiment.gd:53` | ✅ Prevents cavalry spinning |

### DEI Features to Add (Battle Layer)

| Feature | Suggested File | Priority |
|---------|----------------|----------|
| Territory Morale Bonus | `unit_morale.gd` | Medium |
| Unit Type Morale Mods | `morale_event.gd` | Medium |
| Faction Charge Traits | `regiment_data.gd` | Low |
| Weather Combat Effects | `combat_manager.gd` | Low |
| Fatigue Turn Speed Penalty | `regiment.gd` | Medium |

### DEI Features for Campaign Layer (Future)

| Feature | Suggested Implementation | Notes |
|---------|-------------------------|-------|
| Supply System | `CampaignSupplyManager` autoload | Track per-army consumption |
| Supply Cost by Unit | `RegimentData.supply_cost` | Cavalry=2, Monster=4, Infantry=1 |
| Regional Supply | `ProvinceData.supply_generation` | Based on buildings |
| Population Pools | `ProvinceData.population_pools{}` | Citizens, Mercenaries, Levies |
| Recruitment Deduction | `RecruitmentManager` | Subtract from regional pop |
| Population Recovery | Per-turn growth rate | +2% base, buildings modify |
| Seasonal Attrition | Campaign turn events | Winter/Summer regions |

### Combat Formula Comparison

**DEI (Total War):**
```
damage = max(melee_attack - melee_defence, 0)
```

**Dark Shadows (current):**
```gdscript
# From combat_manager.gd
hit_chance = clamp(35 + (attack - defense), 8, 90)
damage = base_damage * (1.0 + bonus_damage) * flank_multiplier
```

The Dark Shadows system adds hit chance RNG which DEI handles differently. Both use attack-defense comparison.

### Morale Modifier IDs for Reference

From DEI's 97 morale modifiers, these patterns are useful:

```gdscript
# Suggested morale event sources for Dark Shadows
enum MoraleSource {
    # Territory
    OWN_TERRITORY_BONUS,      # +10% in friendly land
    ENEMY_TERRITORY_PENALTY,  # -10% in hostile land

    # Unit Type
    HEAVY_INFANTRY_BONUS,     # +5% steadfast troops
    LIGHT_CAVALRY_PENALTY,    # -5% skirmishers
    ELITE_UNIT_BONUS,         # +15% guard/elite units

    # Battle Context
    DEFENDING_BONUS,          # +10% when defending
    SIEGE_DEFENDER_BONUS,     # +20% defending walls
    OUTNUMBERED_PENALTY,      # -15% when 2:1 disadvantage
    GENERAL_PRESENT,          # +10% with army commander
}
```

---

## NEXT STEPS

1. **Install RPFM** - Download from GitHub to properly extract pack files
2. **Extract Key Tables** - Get actual numeric values for combat formulas
3. **Study Unit Balance** - How DEI balances unit stats
4. **Study AI Behavior** - How DEI creates challenging AI

---

## TOTALWARSIMULATOR ANALYSIS

Additional patterns extracted from the TotalWarSimulator Unity project (open source reference).

### Combat System (CUnit.cs)

```csharp
// Per-soldier damage calculation
float damage = Mathf.Max(s.meeleAttack - enemy.meeleDefence, 0);
enemy.health -= (damage + Random.Range(0, 1)) * Time.deltaTime;

// Death check
if (health < 0 && !isDead) {
    isDead = true;
    // Play death animation
}
```

### Unit Stats Structure (MeleeStats.cs)

```csharp
public float topSpeed;           // Movement speed
public float movementForce;      // Acceleration
public float meeleRange;         // Combat reach
public float health;             // HP per soldier
public float meeleDefence;       // Defense stat
public float meeleAttack;        // Attack stat
public float pathSpeed;          // Pathfinding speed
public float soldierDistVertical;   // Formation spacing
public float soldierDistLateral;    // Formation spacing
public float noise;              // Position jitter
public float attackingFactor;    // Combat multiplier
public int startingNumOfSoldiers;
public int startingCols;
```

### Ranged Combat (Archer.cs)

```csharp
// Target prediction for moving enemies
var enemyVelocity = targetUnit.GetComponentInChildren<Rigidbody>().velocity;
Vector3 predictedPosition = targetUnit.position + 2 * enemyVelocity;

// Fire interval system
IEnumerator FireArrowsRepeating() {
    while (true) {
        FireArrowsTowardTarget();
        yield return new WaitForSeconds(s.fireInterval);
    }
}
```

### Key Patterns for Dark Shadows

1. **Target Prediction** - Lead shots for archers hitting moving targets
2. **Per-Soldier Combat** - Individual health tracking (we use regiment-level)
3. **Formation Spacing** - Vertical/lateral distance uniforms
4. **Noise/Jitter** - Organic positioning looks more natural
5. **Coroutine Fire Interval** - Clean volley timing pattern

### Geometry-Based Collision

TotalWarSimulator uses NetTopologySuite for:
- Convex hull generation for unit boundaries
- Fan-shaped archer range detection
- Efficient collision between irregular formations

**Dark Shadows equivalent:** Use AABB from `SpriteFormation.get_formation_bounds()` for basic collision, upgrade to convex hull if needed.

---

*Analysis generated from DEI v1.35 pack files*
*Supplemented with TotalWarSimulator Unity source*
*Updated with Dark Shadows implementation mapping*
