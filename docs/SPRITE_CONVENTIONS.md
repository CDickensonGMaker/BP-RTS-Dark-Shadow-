# Sprite Conventions

BP RTS Dark Shadows sprite format specification. All pipeline tools must conform to these standards.

## Directory Structure

```
output/
└── units/
    └── <sprite_name_lowercase>/
        ├── atlas.png           # Final atlas (stride columns × 8 direction rows)
        ├── manifest.json       # Frame metadata and animation definitions
        ├── palette.png         # 16-color palette strip (if applicable)
        ├── palette.json        # Palette metadata
        ├── preview.gif         # Animated preview for verification
        └── raw/                # Individual normalized frames
            ├── frame_0000.png
            ├── frame_0001.png
            └── ...
```

## Repo Policy

- **Original game files (.BOP, .FOL, .PAL)**: gitignored, not committed
- **Pipeline code**: committed
- **Manifests**: committed (enables diffing, review)
- **Generated atlases**: gitignored, regeneratable via `make sprites`

---

## Atlas Layout

### Grid Structure

```
         Col 0   Col 1   Col 2   ...   Col (stride-1)
        ┌───────┬───────┬───────┬─────┬───────┐
Row 0 S │ f000  │ f001  │ f002  │ ... │ f007  │  ← Pose 0, all directions
        ├───────┼───────┼───────┼─────┼───────┤
Row 1 SW│ f008  │ f009  │ f010  │ ... │ f015  │  ← Pose 1, all directions
        ├───────┼───────┼───────┼─────┼───────┤
   ...  │       │       │       │     │       │
        ├───────┼───────┼───────┼─────┼───────┤
Row 7 SE│ f056  │ f057  │ f058  │ ... │ f063  │  ← Pose N, all directions
        └───────┴───────┴───────┴─────┴───────┘
```

**Columns** = animation frames within a pose (stride-wide)
**Rows** = 8 directions

### Direction Order (Rows 0-7)

**Clockwise from North** - matches SotHR extractor output and engine (WorldCompass):

| Row | Direction | Abbrev | World Vector        | Notes              |
|-----|-----------|--------|---------------------|--------------------|
| 0   | North     | N      | (0, 0, -1)          | Toward camera top  |
| 1   | Northeast | NE     | (+0.7, 0, -0.7)     |                    |
| 2   | East      | E      | (+1, 0, 0)          |                    |
| 3   | Southeast | SE     | (+0.7, 0, +0.7)     |                    |
| 4   | South     | S      | (0, 0, +1)          | Default facing     |
| 5   | Southwest | SW     | (-0.7, 0, +0.7)     |                    |
| 6   | West      | W      | (-1, 0, 0)          |                    |
| 7   | Northwest | NW     | (-0.7, 0, -0.7)     |                    |

```
           0 (N)
        7       1
   (W) 6    +    2 (E)
        5       3
           4 (S)
```

### Stride Defaults

| Unit Class    | Stride | Notes                                    |
|---------------|--------|------------------------------------------|
| Infantry      | 8      | Standard foot soldiers                   |
| Cavalry       | 8      | Mounted units                            |
| Artillery     | 16     | Cannons, war machines (more detail)      |
| Large Monster | 16     | Dragons, giants, etc.                    |
| Projectile    | 8      | Arrows, bolts, cannonballs               |
| Effect        | 8      | Spell effects, explosions                |

**Never assume stride** - detect empirically or verify manually per sprite.

### Cell Dimensions

- Cell size = largest bounding box across all frames, rounded up to nearest **multiple of 8**
- All cells in one sprite's atlas share the same dimensions
- Typical sizes: 64x64, 80x80, 96x96, 128x128

---

## Pivot/Anchor Points

### Ground Units (Infantry, Cavalry, Artillery)

**Anchor: cell-bottom-center**

```
    ┌─────────────┐
    │             │
    │   sprite    │
    │   content   │
    │      │      │
    │      ▼      │
    └──────●──────┘
         pivot
```

- Pivot at horizontal center, vertical bottom
- Sprite "stands" on the pivot point
- Feet should touch the cell bottom edge (2px margin allowed)

### Projectiles and Effects

**Anchor: cell-center**

```
    ┌─────────────┐
    │             │
    │      ●      │  ← pivot at center
    │             │
    └─────────────┘
```

- Pivot at cell center
- Used for things that fly, float, or don't have a "ground" contact point

---

## Palette Handling

### Shadow Cyan Resolution

Source sprites may use cyan `(0, 255, 255)` for shadows or transparency. Resolve as follows:

1. **Pure cyan `#00FFFF`** → fully transparent (alpha = 0)
2. **Near-cyan** (within 8 RGB units of pure cyan) → fully transparent
3. **All other colors** → preserve as-is

### Sub-8 RGB Values

Very dark colors (R, G, B all < 8) that aren't intentional black should be evaluated:
- If adjacent to transparent pixels and part of an edge → likely unintended, make transparent
- If part of intentional dark content → preserve

### Palette Export Format

**palette.png**: Horizontal strip of 16 colors, 16x1 pixels (or Nx1 for N palette entries)

**palette.json**:
```json
{
  "color_count": 16,
  "colors": [
    {"index": 0, "r": 255, "g": 0, "b": 255, "a": 0, "name": "transparent"},
    {"index": 1, "r": 128, "g": 0, "b": 0, "a": 255, "name": "dark_red"},
    ...
  ],
  "source_pal_file": "MCSWORD.PAL",
  "pal_index": 0
}
```

---

## Animation Layout

### Pose Organization

Poses are organized in the manifest, not in atlas rows. A single atlas can contain multiple poses arranged sequentially:

```
Cols:  0  1  2  3  4  5  6  7  8  9  10 11 12
       |------ Idle -----|------ Walk -----|-- Attack --|
       |  4 frames       |  5 frames       |  4 frames  |
```

Each pose occupies `frame_count` consecutive columns, and applies to all 8 direction rows.

### Standard Pose Names

| Pose Name  | Description                        |
|------------|------------------------------------|
| `idle`     | Standing still                     |
| `walk`     | Movement animation                 |
| `attack`   | Melee/ranged attack                |
| `death`    | Death animation (non-looping)      |
| `charge`   | Running/charging (cavalry)         |
| `load`     | Loading weapon (artillery)         |
| `fire`     | Firing weapon (artillery/ranged)   |
| `special`  | Unit-specific special animation    |

---

## Naming Conventions

### File Names

- Sprite folder: lowercase, matches source file stem (`MCSWORD.SPR` → `mcsword/`)
- Atlas: `atlas.png`
- Manifest: `manifest.json`
- Raw frames: `frame_NNNN.png` (4-digit zero-padded)

### Manifest Naming

Use lowercase with underscores for pose names and enum-like values:
- `"idle"` not `"Idle"`
- `"bottom_center"` not `"BottomCenter"`
- `"infantry"` not `"Infantry"`

---

## Source Format Notes

### SotHR File Types

Shadow of the Horned Rat uses a different format than Dark Omen:

| Extension | Purpose                              |
|-----------|--------------------------------------|
| `.FOL`    | Frame offset list (16 bytes/frame)   |
| `.BOP`    | Bitmap pixel data                    |
| `.PAL`    | Palette lookup tables                |

**Not `.SPR`** - Dark Omen uses SPR, SotHR uses FOL/BOP/PAL triplets.

### Extractor Output Convention

The existing `sothr_extract.py` outputs:
- Direction order: N, NE, E, SE, S, SW, W, NW (clockwise from **North**)
- Folder structure: `UNIT/AnimType/UNIT_DIR_NN.png`

**No conversion needed** - the engine now uses the same North-first order as the extractor.

---

## Quality Checks

### Required Verifications

1. **Stride consistency**: `frame_count == stride × pose_count`
2. **Cell uniformity**: All cells same dimensions
3. **Pivot stability**: Centroid drift < 2px across directions for pose 0
4. **No stray transparency colors**: No `(0,255,255)` pixels in final atlas
5. **Manifest integrity**: Every atlas cell referenced, every reference valid

### Visual Inspection

Use the manifest viewer to verify:
- Animation plays smoothly
- Pivot doesn't "jump" between frames
- Directions are correctly ordered (unit faces expected direction)
- No missing or corrupted frames

---

## Version History

| Version | Date       | Changes                                |
|---------|------------|----------------------------------------|
| 1.0     | 2026-05-07 | Initial conventions document           |
