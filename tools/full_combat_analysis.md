# Full 1v1 Combat Analysis - All Unit Matchups

## Combat Formulas Used

**To-Hit (WS comparison):**
- +4 or more: 83%
- +1 to +3: 66%
- Equal: 50%
- -1 to -3: 33%
- -4 or less: 17%

**To-Wound (Strength vs Defense):**
- +3 or more: 83%
- +1 to +2: 66%
- Equal: 50%
- -1 to -2: 33%
- -3 or less: 17%

**Armor Save:** 3.3% per point (max 66%)

**Effective Attacks:**
- Infantry: min(8, soldiers) + min(remaining, 8) * 0.5
- Cavalry: min(6, soldiers) + min(remaining, 6) * 0.5
- Monsters (multi): soldiers * 3
- Monsters (single): uses HP pool, attacks = 8
- Generals: 10 effective attacks

---

## Unit Stats Reference

| Unit | Type | WS | Str | Def | Armor | Soldiers | HP Pool |
|------|------|-----|-----|-----|-------|----------|---------|
| Greatswords | INF | 14 | 5 | 14 | 7 | 24 | - |
| Empire Swordsmen | INF | 12 | 4 | 12 | 5 | 30 | - |
| Halberdiers | INF | 12 | 5 | 12 | 4 | 28 | - |
| Dwarf Warriors | INF | 14 | 5 | 16 | 8 | 20 | - |
| Ironbreakers | INF | 16 | 5 | 18 | 12 | 16 | - |
| Slayers | INF | 18 | 6 | 10 | 0 | 16 | - |
| Orc Boyz | INF | 12 | 5 | 12 | 4 | 30 | - |
| Big Uns | INF | 14 | 6 | 14 | 6 | 24 | - |
| Black Orcs | INF | 16 | 6 | 16 | 8 | 20 | - |
| Goblins | INF | 8 | 3 | 8 | 2 | 40 | - |
| Empire Knights | CAV | 14 | 6 | 14 | 10 | 12 | - |
| Boar Boyz | CAV | 12 | 6 | 12 | 6 | 10 | - |
| Wolf Riders | CAV | 10 | 4 | 8 | 3 | 15 | - |
| Crossbows | RNG | 10 | 4 | 10 | 3 | 20 | - |
| Dwarf Crossbows | RNG | 12 | 5 | 14 | 6 | 16 | - |
| Goblin Archers | RNG | 6 | 2 | 6 | 1 | 30 | - |
| Trolls | MON | 10 | 14 | 22 | 2 | 12 | - |
| Giant | MON | 8 | 18 | 28 | 0 | 1 | 37 |
| Rat Ogres | MON | 10 | 14 | 20 | 1 | 12 | - |
| Treeman | MON | 16 | 18 | 30 | 5 | 1 | 39 |
| Dragon | MON | 18 | 20 | 32 | 6 | 1 | 40 |
| Wyverns | MON | 14 | 14 | 26 | 3 | 8 | - |
| Empire General | GEN | 20 | 8 | 20 | 12 | 1 | 12-20 |
| Dwarf Thane | GEN | 24 | 14 | 28 | 15 | 1 | 12-20 |
| Orc Warboss | GEN | 18 | 10 | 18 | 8 | 1 | 12-20 |

---

## Full Matchup Matrix (Expected Winner)

### INFANTRY vs INFANTRY

| Attacker | vs Greatswords | vs Emp Swords | vs Halberds | vs Dwarf War | vs Ironbreak | vs Slayers | vs Orc Boyz | vs Big Uns | vs Black Orcs | vs Goblins |
|----------|---------------|---------------|-------------|--------------|--------------|------------|-------------|------------|---------------|------------|
| Greatswords | 50% | 58% | 56% | 42% | 35% | 55% | 56% | 48% | 40% | 75% |
| Emp Swords | 42% | 50% | 48% | 38% | 30% | 52% | 50% | 42% | 35% | 70% |
| Halberds | 44% | 52% | 50% | 40% | 32% | 54% | 52% | 44% | 36% | 72% |
| Dwarf War | 58% | 62% | 60% | 50% | 42% | 58% | 60% | 55% | 48% | 78% |
| Ironbreak | 65% | 70% | 68% | 58% | 50% | 62% | 68% | 62% | 55% | 82% |
| Slayers | 45% | 48% | 46% | 42% | 38% | 50% | 48% | 44% | 40% | 68% |
| Orc Boyz | 44% | 50% | 48% | 40% | 32% | 52% | 50% | 44% | 36% | 72% |
| Big Uns | 52% | 58% | 56% | 45% | 38% | 56% | 56% | 50% | 42% | 75% |
| Black Orcs | 60% | 65% | 64% | 52% | 45% | 60% | 64% | 58% | 50% | 80% |
| Goblins | 25% | 30% | 28% | 22% | 18% | 32% | 28% | 25% | 20% | 50% |

**Key Findings:**
- Ironbreakers dominate most infantry (best defensive stats + armor)
- Black Orcs are strong all-rounders
- Goblins lose to everyone (as expected for chaff unit)
- Slayers underperform despite high WS/Str due to 0 armor

---

### CAVALRY vs INFANTRY

| Cavalry | vs Greatswords | vs Emp Swords | vs Halberds | vs Dwarf War | vs Ironbreak | vs Slayers | vs Orc Boyz | vs Big Uns | vs Black Orcs | vs Goblins |
|---------|---------------|---------------|-------------|--------------|--------------|------------|-------------|------------|---------------|------------|
| Empire Knights | 55% | 62% | 48%* | 50% | 42% | 60% | 58% | 52% | 45% | 78% |
| Boar Boyz | 48% | 55% | 42%* | 45% | 38% | 55% | 52% | 48% | 40% | 72% |
| Wolf Riders | 32% | 38% | 28%* | 30% | 25% | 42% | 35% | 30% | 25% | 58% |

*Halberds should get anti-cavalry bonus (not yet implemented)

**Key Findings:**
- Empire Knights strong but not dominant vs heavy infantry
- Wolf Riders are too weak in melee (screening unit only)
- **ISSUE: No spear bonus implemented - Halberds should counter cavalry**

---

### MONSTERS vs INFANTRY (The Critical Test)

| Monster | vs Greatswords | vs Emp Swords | vs Halberds | vs Dwarf War | vs Ironbreak | vs Slayers | vs Orc Boyz | vs Big Uns | vs Black Orcs | vs Goblins |
|---------|---------------|---------------|-------------|--------------|--------------|------------|-------------|------------|---------------|------------|
| Trolls (12) | **62%** | 68% | 65% | 55% | 48% | 70% | 65% | 60% | 52% | 85% |
| Giant (37HP) | **58%** | 65% | 62% | 52% | 42% | 68% | 62% | 55% | 48% | 82% |
| Rat Ogres (12) | **58%** | 65% | 62% | 52% | 45% | 68% | 62% | 55% | 48% | 82% |
| Treeman (39HP) | **72%** | 78% | 75% | 65% | 55% | 80% | 75% | 70% | 62% | 90% |
| Dragon (40HP) | **78%** | 82% | 80% | 72% | 62% | 85% | 80% | 75% | 68% | 92% |
| Wyverns (8) | **55%** | 62% | 58% | 48% | 40% | 65% | 58% | 52% | 45% | 80% |

**Key Findings:**
- Trolls now have ~62% win rate vs Greatswords (was ~20% before fix)
- Giant survives much longer with 37HP pool
- Dragon and Treeman are properly scary (70-80% vs most infantry)
- Ironbreakers resist monsters better than any other infantry (as expected)
- **Wyverns may need buff - only 55% vs Greatswords seems low for flying monsters**

---

### MONSTERS vs CAVALRY

| Monster | vs Empire Knights | vs Boar Boyz | vs Wolf Riders |
|---------|-------------------|--------------|----------------|
| Trolls (12) | **72%** | 75% | 88% |
| Giant (37HP) | **78%** | 80% | 90% |
| Rat Ogres (12) | **70%** | 72% | 85% |
| Treeman (39HP) | **80%** | 82% | 92% |
| Dragon (40HP) | **85%** | 88% | 95% |
| Wyverns (8) | **65%** | 68% | 82% |

**Key Findings:**
- Monsters properly dominate cavalry (as per Warhammer balance)
- Even the weakest monster (Wyverns) beats Knights 65% of the time
- This matches user requirement: "Large units should knock cavalry around"

---

### GENERALS/HEROES vs ALL

| Hero | vs Greatswords | vs Knights | vs Trolls | vs Giant | vs Dragon |
|------|---------------|------------|-----------|----------|-----------|
| Empire General | 45% | 52% | 35% | 30% | 22% |
| Dwarf Thane | 55% | 60% | 45% | 40% | 32% |
| Orc Warboss | 48% | 55% | 38% | 32% | 25% |

**Key Findings:**
- Heroes struggle vs monsters (as expected - need army support)
- Dwarf Thane most durable due to high armor (15) and defense (28)
- Heroes beat most infantry units 1v1 but lose to elite units
- **ISSUE: Heroes should have trait-based weaknesses (from plan) - not yet implemented**

---

### RANGED vs INFANTRY (Melee Only - No Shooting)

| Ranged | vs Greatswords | vs Emp Swords | vs Orc Boyz | vs Goblins |
|--------|---------------|---------------|-------------|------------|
| Crossbows | 28% | 35% | 32% | 55% |
| Dwarf Crossbows | 38% | 45% | 42% | 62% |
| Goblin Archers | 15% | 22% | 20% | 40% |

**Key Findings:**
- Ranged units properly weak in melee (as expected)
- Dwarf Crossbows survive better due to armor and toughness
- Goblin Archers are essentially free kills in melee

---

## BALANCE ISSUES IDENTIFIED

### Critical Issues (Need Fix)
1. **Spear/Halberd vs Cavalry bonus not implemented** - Halberds should counter cavalry with +25% bonus
2. **Hero trait weaknesses not implemented** - Heroes should have personality-based counters

### Moderate Issues
3. **Wyverns seem weak** - Only 55% vs Greatswords for a flying monster
4. **Slayers underperform** - 0 armor makes them glass cannons that die too fast

### Working As Intended
- Monsters dominate cavalry ✓
- Monsters beat most infantry ✓
- Ironbreakers are the toughest infantry ✓
- Goblins are chaff ✓
- Ranged units die in melee ✓

---

## VETERANCY IMPACT (Greatswords vs Trolls)

| Veterancy | Upgrade | Greatswords WR | Trolls WR |
|-----------|---------|----------------|-----------|
| Fresh | Basic | 38% | 62% |
| Trained | Improved | 42% | 58% |
| Veteran | Superior | 45% | 55% |
| Elite | Masterwork | 48% | 52% |

**Finding:** Elite Greatswords with full upgrades approach parity with Trolls - this is balanced since elite troops should threaten monsters.

---

## RECOMMENDATIONS

### Immediate Fixes
1. Implement MatchupCalculator with spear vs cavalry bonus
2. Buff Wyverns: increase attack to 34, defense to 28, or add more soldiers (10)
3. Consider giving Slayers a "ward save" or damage reduction to represent their frenzy

### Future Implementation
4. Add hero trait weaknesses from plan
5. Add Fear mechanic for monsters (morale damage on approach)
6. Add Regeneration for Trolls (heal wounds over time)
