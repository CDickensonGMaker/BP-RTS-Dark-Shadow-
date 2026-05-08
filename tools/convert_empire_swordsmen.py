#!/usr/bin/env python3
"""
Convert empire_swordsmen.png sprite sheet to SOTHR atlas format.

Input format: 9 cols × 8 rows, ~65x49 pixels per frame
- Col 0: Idle (1 frame)
- Cols 1-4: Walk (4 frames)
- Cols 5-6: Attack (2 frames)
- Cols 7-8: Death (2 frames)

Output format: 13 cols × 8 rows, 64x64 pixels per frame
- Col 0: Idle (1 frame)
- Cols 1-4: Walk (4 frames, or repeat to fill)
- Cols 5-10: Attack (2 frames repeated or padded)
- Cols 11-12: Death (2 frames)

Direction mapping (clockwise from North):
Row 0: N, Row 1: NE, Row 2: E, Row 3: SE, Row 4: S, Row 5: SW, Row 6: W, Row 7: NW
"""

from PIL import Image
from pathlib import Path

# Paths
INPUT_PATH = Path(r"C:\Users\caleb\Downloads\empire_swordsmen.png")
OUTPUT_DIR = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\assets\sprites\units")

# Input sprite sheet config
INPUT_COLS = 9
INPUT_ROWS = 8
INPUT_FRAME_W = 65
INPUT_FRAME_H = 49  # Approximate, will handle rounding

# Output atlas config (matches SOTHR format)
OUTPUT_COLS = 13
OUTPUT_ROWS = 8
OUTPUT_FRAME_SIZE = 64

# Animation layout in input
INPUT_ANIMS = {
    "idle": (0, 1),      # start_col, count
    "walk": (1, 4),
    "attack": (5, 2),
    "dead": (7, 2),
}

# Direction names for output (clockwise from North, matches SOTHR extractor)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def extract_frame(img, col, row, frame_w, frame_h):
    """Extract a single frame from the sprite sheet."""
    x = col * frame_w
    y = row * frame_h
    # Handle edge cases where frame might extend beyond image
    x2 = min(x + frame_w, img.width)
    y2 = min(y + frame_h, img.height)

    frame = img.crop((x, y, x2, y2))
    return frame


def resize_frame(frame, target_size):
    """Resize frame to target size, centering the sprite."""
    # Create transparent canvas
    result = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))

    # Resize frame maintaining aspect ratio
    aspect = frame.width / frame.height
    if aspect > 1:
        new_w = target_size
        new_h = int(target_size / aspect)
    else:
        new_h = target_size
        new_w = int(target_size * aspect)

    resized = frame.resize((new_w, new_h), Image.Resampling.NEAREST)

    # Center on canvas
    x = (target_size - new_w) // 2
    y = (target_size - new_h) // 2
    result.paste(resized, (x, y))

    return result


def create_atlas(input_img, unit_name):
    """Create SOTHR-format atlas from input sprite sheet."""
    atlas_w = OUTPUT_COLS * OUTPUT_FRAME_SIZE
    atlas_h = OUTPUT_ROWS * OUTPUT_FRAME_SIZE
    atlas = Image.new('RGBA', (atlas_w, atlas_h), (0, 0, 0, 0))

    # Calculate actual input frame height
    actual_frame_h = input_img.height // INPUT_ROWS

    print(f"Input image: {input_img.size}")
    print(f"Calculated frame size: {INPUT_FRAME_W}x{actual_frame_h}")

    for row in range(OUTPUT_ROWS):
        direction = DIRECTIONS[row]
        out_col = 0

        # Idle: 1 frame at col 0
        frame = extract_frame(input_img, 0, row, INPUT_FRAME_W, actual_frame_h)
        frame = resize_frame(frame, OUTPUT_FRAME_SIZE)
        atlas.paste(frame, (out_col * OUTPUT_FRAME_SIZE, row * OUTPUT_FRAME_SIZE))
        out_col += 1

        # Walk: 4 frames at cols 1-4, repeat to fill 9 slots (cols 1-9)
        walk_start, walk_count = INPUT_ANIMS["walk"]
        for i in range(9):  # Fill 9 walk slots
            src_col = walk_start + (i % walk_count)
            frame = extract_frame(input_img, src_col, row, INPUT_FRAME_W, actual_frame_h)
            frame = resize_frame(frame, OUTPUT_FRAME_SIZE)
            atlas.paste(frame, (out_col * OUTPUT_FRAME_SIZE, row * OUTPUT_FRAME_SIZE))
            out_col += 1

        # Attack: 2 frames at cols 5-6, fill 2 slots (cols 10-11)
        attack_start, attack_count = INPUT_ANIMS["attack"]
        for i in range(2):
            src_col = attack_start + (i % attack_count)
            frame = extract_frame(input_img, src_col, row, INPUT_FRAME_W, actual_frame_h)
            frame = resize_frame(frame, OUTPUT_FRAME_SIZE)
            atlas.paste(frame, (out_col * OUTPUT_FRAME_SIZE, row * OUTPUT_FRAME_SIZE))
            out_col += 1

        # Death: 1 frame at col 12 (use first death frame)
        dead_start, dead_count = INPUT_ANIMS["dead"]
        frame = extract_frame(input_img, dead_start, row, INPUT_FRAME_W, actual_frame_h)
        frame = resize_frame(frame, OUTPUT_FRAME_SIZE)
        atlas.paste(frame, (out_col * OUTPUT_FRAME_SIZE, row * OUTPUT_FRAME_SIZE))

    return atlas


def generate_tres(unit_name):
    """Generate the .tres resource file."""
    content = f'''[gd_resource type="Resource" script_class="SpriteUnitAtlas" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/units/{unit_name}_atlas.png" id="1"]
[ext_resource type="Script" path="res://battle_system/data/sprite_unit_atlas.gd" id="2"]

[resource]
script = ExtResource("2")
texture = ExtResource("1")
columns = {OUTPUT_COLS}
rows = {OUTPUT_ROWS}
frame_size = Vector2({OUTPUT_FRAME_SIZE}, {OUTPUT_FRAME_SIZE})
directions = {OUTPUT_ROWS}
animation_speed = 8.0
animations = {{
"idle": {{"start_frame": 0, "frame_count": 1}},
"walk": {{"start_frame": 1, "frame_count": 9}},
"attack": {{"start_frame": 10, "frame_count": 2}},
"death": {{"start_frame": 12, "frame_count": 1}}
}}
'''
    return content


def main():
    unit_name = "empsword"  # Empire Swordsmen / Elite troops

    print(f"Converting empire_swordsmen.png to {unit_name}_atlas...")

    # Load input
    if not INPUT_PATH.exists():
        print(f"Error: Input file not found: {INPUT_PATH}")
        return

    input_img = Image.open(INPUT_PATH)
    if input_img.mode != 'RGBA':
        input_img = input_img.convert('RGBA')

    # Create atlas
    atlas = create_atlas(input_img, unit_name)

    # Save atlas PNG
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas_path = OUTPUT_DIR / f"{unit_name}_atlas.png"
    atlas.save(atlas_path, 'PNG')
    print(f"Created: {atlas_path}")

    # Save .tres file
    tres_content = generate_tres(unit_name)
    tres_path = OUTPUT_DIR / f"{unit_name}_atlas.tres"
    with open(tres_path, 'w') as f:
        f.write(tres_content)
    print(f"Created: {tres_path}")

    print(f"\nDone! Atlas size: {atlas.size}")
    print(f"To use this unit, create a regiment data file referencing {unit_name}_atlas.tres")


if __name__ == "__main__":
    main()
