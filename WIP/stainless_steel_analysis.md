# Stainless Steel & Third Age Analysis - Lessons for Dark Shadows RTS

## Overview

Analysis of Stainless Steel 6.4 and Third Age Total War mods for Medieval 2 Total War, extracting game design patterns applicable to our RTS battle system.

**Sources:**
- [Stainless Steel - TWC Wiki](https://wiki.twcenter.net/index.php?title=Stainless_Steel)
- [RC 2.0 Medieval Combat Guide](https://www.stainless-steel-mod.com/RR_RC_Guide_2)
- [M2TW AI Modification Essay](https://medieval2.heavengames.com/m2tw/mod_portal/tutorials/ai_essay/)
- [Third Age Total War - ModDB](https://www.moddb.com/mods/third-age-total-war)

---

## 1. UNIT QUALITY TIERS

Stainless Steel's Real Combat system uses 7 quality tiers affecting all stats:

| Quality | Attack | Defense | Charge | Morale | Heat Penalty |
|---------|--------|---------|--------|--------|--------------|
| Peasant | -3 | -3 | -1 | 4 | +3 |
| Peasant Militia | -2 | -2 | -1 | 5 | +2 |
| Militia | -1 | -1 | 0 | 7 | +1 |
| Average | 0 | 0 | 0 | 9 | 0 |
| Superior | +1 | +1 | 0 | 11 | -1 |
| Elite | +3 | +3 | +1 | 14 | -2 |
| Exceptional | +4 | +4 | +1 | 16 | -3 |

### Design Lesson for Dark Shadows:
Our VeterancySystem already has 4 levels (FRESH, BLOODED, VETERAN, ELITE). Consider:
- Expanding to more granular tiers
- Adding heat/stamina penalties to heavy armor
- Quality affects charge bonus, not just attack/defense

---

## 2. UNIT TYPE MODIFIERS

Special unit behavior types with stat trade-offs:

| Type | Attack | Defense | Morale Effect |
|------|--------|---------|---------------|
| Bodyguard | -2 | +2 | Disciplined |
| Guard | -1 | +1 | Disciplined |
| Impetuous | +1 | -1 | May break formation |
| Reckless | +2 | -2 | May break formation |
| Fanatic | +2 | -3 | Lock morale (never rout) |

### Design Lesson for Dark Shadows:
Add unit personality traits that affect combat behavior:
- **Disciplined**: Won't pursue, holds formation
- **Impetuous**: May charge without orders, +attack/-defense
- **Fanatic**: Ignores morale checks, fights to death

---

## 3. RANGED UNIT DISTINCTION

Key insight: **Skirmishers vs Missileers** are fundamentally different:

| Type | Range | Accuracy | Rate | Melee Skill |
|------|-------|----------|------|-------------|
| Skirmisher | Short | High (direct fire) | Low | Quality - 1 |
| Missileer | Long | Low (arrow shower) | High | Quality - 2 |

**Skirmishers**: Shoot directly over open sights, most accurate, better melee
**Missileers**: Maximum rate at range, create arrow shower, weak in melee

### Design Lesson for Dark Shadows:
- Differentiate archer types by fire mode
- Add "direct fire" (accurate, single target) vs "volley fire" (AOE, less accurate)
- Skirmisher-type ranged should be better in melee fallback

---

## 4. MORALE SYSTEM

### Base Morale by Quality:
- Peasant: 4
- Militia: 7
- Average: 9
- Elite: 14
- Exceptional: 16

### Morale Modifiers:
| Condition | Modifier |
|-----------|----------|
| Mounted | +1 |
| Skirmisher | -1 |
| Missile unit | -2 |
| Mercenary (loyal) | +2 |
| Mercenary (unknown) | 0 |
| Mercenary (disloyal) | -3 |
| Disciplined | Slower to break |
| Impetuous | Faster to break, may charge |

### Design Lesson for Dark Shadows:
Our morale system already has events. Add:
- Unit type base morale modifiers
- Mercenary loyalty affecting morale
- "Impetuous" units that may ignore orders

---

## 5. STANCE MECHANICS (Third Age / M2TW)

### Guard Mode Behavior:
- **Guard Mode ON**: Unit holds position, won't pursue fleeing enemies
- **Guard Mode OFF**: Unit will chase routing enemies (can break formation)

### Defensive Stance (Shield Wall, Spear Wall):
- Changes spacing to tight formation
- Front row does most fighting
- Unit takes fewer casualties but gets fewer kills
- Sacrifices individual effectiveness for army cohesion
- "Protects squishy units behind"

### Fire At Will:
- **ON**: Archers fire automatically at targets in range
- **OFF**: Archers hold fire until ordered (saves ammo, prevents friendly fire)

### Design Lesson for Dark Shadows:
Our stance system should map to these behaviors:

| Our Stance | M2TW Equivalent | Behavior |
|------------|-----------------|----------|
| AGGRESSIVE | Guard OFF | Pursue enemies, auto-engage |
| DEFENSIVE | Guard ON | Hold position, engage in range only |
| HOLD_GROUND | Defensive stance | Don't move at all, tight formation |
| SKIRMISH | Skirmish mode | Maintain distance, kite |

**Already implemented today** - verify behavior matches.

---

## 6. BATTLE AI CONFIGURATION

### Key AI Parameters (from config_ai_battle.xml):

**Sally-out Ratio**: `2.0`
- Defenders only counter-attack if strength >= 2x attackers
- Prevents suicidal sorties

**Strength Comparison**: `0.8`
- AI considers itself "stronger" even at 80% enemy strength
- Makes AI more aggressive

### AI Formation Selection:
- AI chooses from 6+ battlefield formations
- Selection based on: terrain, enemy composition, relative strength
- Siege battles have many more formation options

### Design Lesson for Dark Shadows:
Our GeneralAI should consider:
- Strength ratios before committing to attacks
- Defensive vs offensive stance based on force comparison
- Formation selection based on enemy unit types

---

## 7. MASS AND COLLISION

### Unit Mass System:
Mass ranges from 0.7 to 1.2 based on armor:
- Light units: ~0.7-0.8
- Medium units: ~0.9-1.0
- Heavy units: ~1.1-1.2
- Missile/Skirmish: -0.1 penalty (less melee training)

Mass affects:
- Charge impact damage
- Knockback distance
- Ability to hold ground vs cavalry

### Design Lesson for Dark Shadows:
Our charge system already uses mass. Verify:
- Light infantry gets knocked back by cavalry
- Heavy infantry can brace and hold
- Ranged units have reduced mass for collision

---

## 8. WEAPON BALANCE

### Melee Weapons:
| Type | Attack | Charge | Defense |
|------|--------|--------|---------|
| Sword | 5-7 | 3-4 | 3-5 |
| Axe | 7-9 | 4-5 | 1-2 |
| Spear | 4-6 | 2-3 | 4-6 |
| Pike | 5-7 | 6 (brace) | 3-4 |

### Charge Weapons (Mounted):
- Charge Distance: 20-45 meters required
- Heavy Lance: Base charge 15
- Light Lance: Base charge 8-10

### Missile Weapons:
| Type | Attack | Range |
|------|--------|-------|
| Javelin | 11 | Short |
| Short Bow | 12-14 | Medium |
| Longbow | 16-18 | Long |
| Crossbow | 18-20 | Medium |
| Arquebus | 22 | Medium |

### Design Lesson for Dark Shadows:
Our RegimentData has attack/defense stats. Consider:
- Weapon-specific charge bonuses
- Minimum charge distance already implemented (10 units)
- Ranged weapon attack scaling by type

---

## 9. HEAT AND FATIGUE

Heavy armor causes heat penalties:
| Armor Type | Heat Value |
|------------|------------|
| Unarmored | 0 |
| Light | 2-4 |
| Medium | 5-7 |
| Heavy | 8-10 |
| Gothic Plate | +8 |

**Key insight**: "If kill rates are too low then heavy armored units are at too great a disadvantage, they will tire too easily."

### Design Lesson for Dark Shadows:
Our StaminaSystem should factor in:
- Armor weight affecting fatigue rate
- Heavy units tire faster in prolonged combat
- Balance kill rate so heavy armor is still viable

---

## 10. BATTLE PACING

Stainless Steel's core pacing changes:
- **Longer battles** due to higher morale
- **More decisive** once morale breaks
- **Armor matters** more than vanilla

### Key Balance Point:
"During the siege their poor quality spearmen clogged the streets and my men's morale was not enough to deal with their numbers. It's a battle I would have won on vanilla Medieval, but that is why this mod is so refreshing."

Numbers can overwhelm quality - but quality still matters for elite units.

### Design Lesson for Dark Shadows:
Our combat tuning (MELEE_TICK_RATE = 1.5, DAMAGE_MULT = 0.5) should:
- Allow time for tactical decisions
- Make morale matter (battles end from routing, not attrition)
- Let quality troops shine without being invincible

---

## IMPLEMENTATION RECOMMENDATIONS

### Already Implemented (Compare to SS):
| Feature | Dark Shadows File | Status |
|---------|-------------------|--------|
| Quality tiers | VeterancySystem | 4 levels |
| Morale system | UnitMorale | Event-based |
| Charge bonus | CombatManager | Distance-based |
| Stamina/Fatigue | StaminaSystem | 4 states |
| Stances | StanceType | 5 types |

### Features to Add:

| Feature | Priority | Suggested Implementation |
|---------|----------|-------------------------|
| Unit personality traits | Medium | Add to RegimentData (disciplined, impetuous, fanatic) |
| Ranged fire modes | Low | Direct fire vs volley fire toggle |
| Armor heat penalty | Low | Modify stamina drain by armor type |
| AI strength ratio check | Medium | Add to GeneralAI before attack commits |
| Guard mode "no pursue" | High | **Already done** - DEFENSIVE stance |

### Combat Formula Comparison

**Stainless Steel (M2TW):**
```
hit_chance = base + (attack - defense)
damage = weapon_damage * armor_reduction
morale_check = base_morale + modifiers vs threshold
```

**Dark Shadows (current):**
```gdscript
hit_chance = clamp(35 + (attack - defense), 8, 90)
damage = base_damage * COMBAT_DAMAGE_MULTIPLIER * flank_mult
morale = per_soldier tracking with events
```

Both systems use attack-defense comparison. Dark Shadows adds hit chance RNG which SS handles through damage variance.

---

## KEY TAKEAWAYS

1. **Quality tiers matter** - Consider expanding veterancy effects
2. **Unit personalities** - Disciplined vs Impetuous creates tactical variety
3. **Ranged distinction** - Skirmishers (accurate) vs Archers (volume)
4. **Guard mode = no pursue** - Our DEFENSIVE stance already does this
5. **Armor = fatigue trade-off** - Heavy armor should tire faster
6. **AI needs strength checks** - Don't attack when outnumbered badly
7. **Morale ends battles** - Focus on morale, not pure attrition

---

*Analysis compiled from online documentation*
*Stainless Steel 6.4 and Third Age Total War mods for Medieval II: Total War*
