#!/usr/bin/env python3
"""
Convert undead sprite sheets to SOTHR atlas format.

Input format: 1024x1536 (8 cols × 24 rows, 128x64 per frame)
Layout:
- Rows 0-7: Walk (8 directions × 8 frames)
- Rows 8-15: Idle + Attack (8 directions × 8 frames, first 2 cols idle, rest attack)
- Rows 16-23: Death (8 directions × 8 frames)

Output format: 13 cols × 8 rows, 64x64 pixels per frame
- Col 0: Idle
- Cols 1-9: Walk (9 frames, repeat from 8)
- Cols 10-11: Attack (2 frames)
- Col 12: Death
"""

from PIL import Image
from pathlib import Path
import sys

# Configuration
INPUT_FRAME_W = 128
INPUT_FRAME_H = 64
INPUT_COLS = 8
INPUT_ROWS = 24

OUTPUT_COLS = 13
OUTPUT_ROWS = 8
OUTPUT_FRAME_SIZE = 80  # Larger frames for undead sprites

# Direction mapping - input rows to output rows
# Input appears to be: S, SW, W, NW, N, NE, E, SE (same as SOTHR)
DIRECTION_MAP = list(range(8))  # Direct mapping


def extract_frame(img, col, row):
    """Extract a single frame from the sprite sheet."""
    x = col * INPUT_FRAME_W
    y = row * INPUT_FRAME_H
    return img.crop((x, y, x + INPUT_FRAME_W, y + INPUT_FRAME_H))


def resize_frame(frame, target_size=OUTPUT_FRAME_SIZE):
    """Resize frame to target size, keeping full sprite visible."""
    # Create transparent canvas
    result = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))

    # Scale the entire frame (128x64) to fit in target while maintaining aspect
    frame_w, frame_h = frame.size

    # Use 95% of target size to leave small margin
    usable_size = int(target_size * 0.95)
    scale = min(usable_size / frame_w, usable_size / frame_h)

    new_w = int(frame_w * scale)
    new_h = int(frame_h * scale)

    if new_w > 0 and new_h > 0:
        resized = frame.resize((new_w, new_h), Image.Resampling.LANCZOS)

        # Center horizontally, align to bottom (feet on ground)
        x = (target_size - new_w) // 2
        y = target_size - new_h - 2  # 2px margin from bottom
        result.paste(resized, (x, y), resized)  # Use alpha mask

    return result


def create_atlas(input_img, unit_name):
    """Create SOTHR-format atlas from undead sprite sheet."""
    atlas_w = OUTPUT_COLS * OUTPUT_FRAME_SIZE
    atlas_h = OUTPUT_ROWS * OUTPUT_FRAME_SIZE
    atlas = Image.new('RGBA', (atlas_w, atlas_h), (0, 0, 0, 0))

    for out_row in range(OUTPUT_ROWS):
        in_dir = DIRECTION_MAP[out_row]
        out_col = 0

        # Column 0: Idle (from row 8+direction, col 0)
        idle_frame = extract_frame(input_img, 0, 8 + in_dir)
        idle_frame = resize_frame(idle_frame)
        atlas.paste(idle_frame, (out_col * OUTPUT_FRAME_SIZE, out_row * OUTPUT_FRAME_SIZE))
        out_col += 1

        # Columns 1-9: Walk (from rows 0-7, cols 0-7, repeat col 0 at end)
        for walk_idx in range(9):
            walk_col = walk_idx % 8  # Repeat first frame for 9th
            walk_frame = extract_frame(input_img, walk_col, in_dir)
            walk_frame = resize_frame(walk_frame)
            atlas.paste(walk_frame, (out_col * OUTPUT_FRAME_SIZE, out_row * OUTPUT_FRAME_SIZE))
            out_col += 1

        # Columns 10-11: Attack (from row 8+direction, cols 2-3 or 4-5)
        for attack_idx in range(2):
            attack_col = 2 + attack_idx  # Attack frames at cols 2-3 in middle section
            attack_frame = extract_frame(input_img, attack_col, 8 + in_dir)
            attack_frame = resize_frame(attack_frame)
            atlas.paste(attack_frame, (out_col * OUTPUT_FRAME_SIZE, out_row * OUTPUT_FRAME_SIZE))
            out_col += 1

        # Column 12: Death (from row 16+direction, col 4 or last frame)
        death_frame = extract_frame(input_img, 4, 16 + in_dir)
        death_frame = resize_frame(death_frame)
        atlas.paste(death_frame, (out_col * OUTPUT_FRAME_SIZE, out_row * OUTPUT_FRAME_SIZE))

    return atlas


def generate_tres(unit_name):
    """Generate the .tres resource file."""
    return f'''[gd_resource type="Resource" script_class="SpriteUnitAtlas" load_steps=3 format=3]

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


def process_sprite(input_path, unit_name, output_dir):
    """Process a single sprite sheet."""
    print(f"Processing {input_path} -> {unit_name}...")

    input_img = Image.open(input_path)
    if input_img.mode != 'RGBA':
        input_img = input_img.convert('RGBA')

    print(f"  Input size: {input_img.size}")

    # Create atlas
    atlas = create_atlas(input_img, unit_name)

    # Save atlas PNG
    output_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = output_dir / f"{unit_name}_atlas.png"
    atlas.save(atlas_path, 'PNG')
    print(f"  Created: {atlas_path}")

    # Save .tres file
    tres_content = generate_tres(unit_name)
    tres_path = output_dir / f"{unit_name}_atlas.tres"
    with open(tres_path, 'w') as f:
        f.write(tres_content)
    print(f"  Created: {tres_path}")

    return True


def main():
    output_dir = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\assets\sprites\units")

    # Map input files to unit names
    sprites = [
        (r"C:\Users\caleb\Downloads\skeleton_sword.png", "skeleton"),
        (r"C:\Users\caleb\Downloads\grave knight.png", "graveknight"),
        (r"C:\Users\caleb\Downloads\grave gaurd.png", "graveguard"),
        (r"C:\Users\caleb\Downloads\skeleton_archer.png", "skelarch"),
    ]

    for input_path, unit_name in sprites:
        try:
            process_sprite(Path(input_path), unit_name, output_dir)
        except Exception as e:
            print(f"  ERROR: {e}")

    print("\nDone!")


if __name__ == "__main__":
    main()
