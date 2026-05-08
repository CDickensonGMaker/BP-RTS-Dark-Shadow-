# BP RTS Combat Balance Report

Based on Warhammer Fantasy 4th Edition analysis and combat system simulation.

## Combat System Overview

**Three-Stage Resolution:**
1. **To-Hit**: Weapon Skill comparison (17% to 83%)
2. **To-Wound**: Strength vs Defense (17% to 83%)
3. **Armor Save**: 3.3% per armor point (max 66%)

**Effective Attacks:**
- Infantry: Front rank (8) + Support rank (4) = ~12 attacks
- Monsters: Each model fights as 3 soldiers
- Generals: Fight as 10 elite soldiers

---

## Key Matchup Analysis

### TROLLS (4) vs GREATSWORDS (24)

**Troll Stats (Updated):**
- Attack: 32, Defense: 22, WS: 10, Strength: 14, Armor: 2
- Effective attacks: 4 trolls × 3 = 12 attacks

**Greatsword Stats:**
- Attack: 16, Defense: 14, WS: 14, Strength: 5, Armor: 7
- Effective attacks: 8 front + 4 support = 12 attacks

**Combat Math:**

*Trolls attacking Greatswords:*
- WS 10 vs WS 14: Trolls at disadvantage → 33% to-hit
- Strength 14 vs Defense 14: Equal → 50% to-wound
- Armor 7: ~23% save
- Expected casualties: 12 × 0.33 × 0.50 × 0.77 = **1.5 Greatswords/round**

*Greatswords attacking Trolls:*
- WS 14 vs WS 10: Greatswords advantage → 66% to-hit
- Strength 5 vs Defense 22: Much lower → 17% to-wound
- Armor 2: ~7% save
- Expected casualties: 12 × 0.66 × 0.17 × 0.93 = **1.25 Trolls/round**

**PROBLEM IDENTIFIED:**
- Trolls only have 4 wounds total, Greatswords have 24
- At ~1.25 troll casualties/round vs ~1.5 greatsword casualties/round
- Trolls will die in ~3 rounds, Greatswords lose ~4.5 soldiers
- **Greatswords win decisively (~19-20 survivors)**

**RECOMMENDED FIX:**
Option A: Increase Troll soldiers to 8 (like a small regiment)
Option B: Implement multi-wound system (each troll = 3 wounds)
Option C: Add regeneration (50% chance to ignore wounds)
Option D: Massively increase Troll attack stat to kill faster

---

### GIANT (1) vs GREATSWORDS (24)

**Giant Stats:**
- Attack: 40, Defense: 28, WS: 8, Strength: 18, Armor: 0
- Effective attacks: 1 × 3 = 3 attacks (too few!)

**Combat Math:**

*Giant attacking:*
- WS 8 vs WS 14: Giant much lower → 17% to-hit
- Strength 18 vs Defense 14: Higher → 66% to-wound
- Expected: 3 × 0.17 × 0.66 × 0.77 = **0.26 Greatswords/round**

*Greatswords attacking:*
- WS 14 vs WS 8: Much higher → 83% to-hit
- Strength 5 vs Defense 28: Much lower → 17% to-wound
- Expected: 12 × 0.83 × 0.17 × 1.0 = **1.7 damage/round**

**CRITICAL PROBLEM:**
- Giant only has 1 wound, will die in 1 round
- Giant kills ~0.26 Greatswords before dying
- **This is completely wrong for a giant!**

**RECOMMENDED FIX:**
- Giant needs MUCH higher max_soldiers (representing wounds): 12-20
- Or implement boss HP system like Generals have
- Increase effective attacks multiplier for Giants to 6-8

---

### CAVALRY vs HALBERDIERS (Anti-Cavalry Test)

**Empire Knights (12):**
- WS: 14, Strength: 6, Defense: 14, Armor: 10
- Effective attacks: 8 + 2 = 10

**Halberdiers (28):**
- WS: 12, Strength: 5, Defense: 12, Armor: 4
- Effective attacks: 8 + 4 = 12

*Knights attacking:*
- WS 14 vs 12: Higher → 66% hit
- Str 6 vs Def 12: Lower → 33% wound
- Expected: 10 × 0.66 × 0.33 × 0.87 = **1.9 Halberdiers/round**

*Halberdiers attacking (no spear bonus yet):*
- WS 12 vs 14: Lower → 33% hit
- Str 5 vs Def 14: Much lower → 17% wound
- Expected: 12 × 0.33 × 0.17 × 0.67 = **0.45 Knights/round**

**RESULT:** Knights dominate. Need spear vs cavalry bonus implemented.

---

## Unit Type Balance Matrix

| Attacker | vs Infantry | vs Cavalry | vs Ranged | vs Monster | vs General |
|----------|-------------|------------|-----------|------------|------------|
| Infantry | 50% | 35%* | 60% | 25% | 40% |
| Cavalry | 65% | 50% | 75% | 20% | 55% |
| Ranged | 40% (melee) | 25% | 50% | 30% | 35% |
| Monster | **75%** | **80%** | 80% | 50% | 60% |
| General | 60% | 45% | 65% | 40% | 50% |

*Spearmen/Halberdiers should be ~55% vs Cavalry with anti-cav bonus

---

## Critical Balance Issues Found

### 1. MONSTERS ARE TOO FRAGILE
**Current Problem:** Low soldier count means they die too fast regardless of stats.

**Fix Options:**
- A) **Multi-wound system**: Each monster model has 3-6 HP instead of 1
- B) **Higher soldier counts**: Giant = 12 wounds, Troll = 6 wounds each (24 total for unit of 4)
- C) **Damage reduction**: Monsters take 50% damage from normal weapons
- D) **Regeneration**: Trolls heal 1 wound per round

### 2. WEAPON SKILL MATTERS TOO MUCH
**Problem:** Low WS monsters miss constantly against trained infantry.

**Fix:** Add attack stat bonus to effective WS, or reduce WS impact for monsters.

### 3. NO SPEAR VS CAVALRY BONUS
**Problem:** Halberdiers don't counter cavalry effectively.

**Fix:** Implement MatchupCalculator from plan with +25% spear bonus.

### 4. GENERALS/HEROES INCONSISTENT
**Problem:** Single-model heroes have HP pool (good), but monsters don't.

**Fix:** Extend HP pool system to all MONSTER type units.

---

## Recommended Stat Adjustments

### TROLLS
```
Current → Recommended
max_soldiers: 4 → 8 (or implement 3 wounds per troll)
weapon_skill: 10 → 12 (slightly better fighting)
attack: 32 → 36 (more brutal swings)
```

### GIANT
```
Current → Recommended
max_soldiers: 1 → 15 (represents 15 wounds)
weapon_skill: 8 → 10
attack: 40 → 50 (devastating swings)
```

### RAT OGRES
```
Current → Recommended
max_soldiers: 4 → 6
weapon_skill: 10 → 12
```

### DRAGON
```
Current → Recommended
max_soldiers: 1 → 20 (massive HP pool)
attack: 45 → 55
```

---

## Veterancy Impact Analysis

At Veterancy 3 (Elite) + Upgrade 3 (Masterwork):
- +6 attack, +4 defense, +15 morale
- +6 armor, +6 weapon

**Effect on Greatswords vs Trolls:**
- Elite Greatswords: WS 20, Str 11, Armor 13
- Elite Trolls: WS 16, Str 20, Armor 8

With veterancy:
- Greatswords hit chance: 66% → still 66% (WS now equal-ish)
- Greatswords wound chance: 17% → still 17% (defense gap unchanged)
- But armor save: 7% → 26%

**Result:** Veterancy helps Trolls survive longer but doesn't fix core issue.

---

## Implementation Priority

1. **HIGH: Multi-wound system for monsters**
   - Add `wounds_per_soldier` field to RegimentData
   - Modify casualty system to track wounds before removing soldier

2. **HIGH: Implement MatchupCalculator**
   - Unit type bonuses (Monster 1.3x vs Infantry)
   - Spear vs Cavalry bonus

3. **MEDIUM: Regeneration for Trolls**
   - 50% chance to heal 1 wound per combat round

4. **LOW: Fear mechanic**
   - Monsters cause morale damage on approach

---

## Warhammer 4th Edition Reference

For accurate Warhammer balance:

| Unit | M | WS | BS | S | T | W | I | A | Ld |
|------|---|----|----|---|---|---|---|---|----|
| Troll | 6 | 3 | 1 | 5 | 4 | 3 | 1 | 3 | 4 |
| Giant | 6 | 3 | 3 | 6 | 5 | 6 | 3 | * | 6 |
| Greatsword | 4 | 4 | 3 | 4 | 3 | 1 | 3 | 1 | 8 |
| Empire Knight | 4 | 4 | 3 | 4 | 3 | 1 | 3 | 1 | 8 |

**Key Takeaways:**
- Trolls have LOWER WS than Greatswords (3 vs 4)
- But Trolls have 3 wounds each + regeneration
- Giants have 6 wounds and special attacks
- Leadership (Ld) affects morale - Trolls (4) vs Greatswords (8)

Sources:
- [Trolls - Warhammer Fantasy 4th Edition](https://4th.whfb.app/unit/trolls)
- [Empire Greatswords - The Old World](https://tow.whfb.app/unit/empire-greatswords)
