#!/usr/bin/env python3
"""
Convert SPELLS sprites into effect atlases.

Processes all spell effect sprites from the SPELLS folder.
"""

from PIL import Image
from pathlib import Path
import re

# Configuration
INPUT_DIR = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\sothr_sprites_labeled\SPELLS")
OUTPUT_DIR = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\assets\sprites\effects")
FRAME_SIZE = 80

# Direction order matching SOTHR standard
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def parse_frame_info(filename):
    """Parse SPELLS_XXX_DIR.png filename."""
    match = re.match(r'SPELLS_(\d+)_(\w+)\.png', filename)
    if match:
        return int(match.group(1)), match.group(2)
    return None, None


def load_frames_from_folder(folder_path):
    """Load all frames from a folder, organized by frame number and direction."""
    frames = {}

    for png_file in folder_path.glob("*.png"):
        frame_num, direction = parse_frame_info(png_file.name)
        if frame_num is None:
            continue

        try:
            img = Image.open(png_file)
            if img.mode != 'RGBA':
                img = img.convert('RGBA')

            if frame_num not in frames:
                frames[frame_num] = {}
            frames[frame_num][direction] = img
        except Exception as e:
            print(f"  Warning: Failed to load {png_file.name}: {e}")

    return frames


def resize_frame(img, target_size=FRAME_SIZE):
    """Resize frame to fit target size with proper positioning."""
    result = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))

    orig_w, orig_h = img.size
    usable_size = int(target_size * 0.95)
    scale = min(usable_size / orig_w, usable_size / orig_h)

    new_w = int(orig_w * scale)
    new_h = int(orig_h * scale)

    if new_w > 0 and new_h > 0:
        resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        x = (target_size - new_w) // 2
        y = (target_size - new_h) // 2
        result.paste(resized, (x, y), resized)

    return result


def create_directional_atlas(frames_dict, name, output_dir):
    """Create an atlas from frames organized by direction."""
    if not frames_dict:
        print(f"  No frames found for {name}")
        return None

    frame_nums = sorted(frames_dict.keys())
    num_columns = len(frame_nums)

    print(f"  Creating {name} atlas: {num_columns} frames x 8 directions")

    atlas_w = num_columns * FRAME_SIZE
    atlas_h = 8 * FRAME_SIZE
    atlas = Image.new('RGBA', (atlas_w, atlas_h), (0, 0, 0, 0))

    for col_idx, frame_num in enumerate(frame_nums):
        dir_frames = frames_dict[frame_num]
        for row_idx, direction in enumerate(DIRECTIONS):
            if direction in dir_frames:
                resized = resize_frame(dir_frames[direction])
                x = col_idx * FRAME_SIZE
                y = row_idx * FRAME_SIZE
                atlas.paste(resized, (x, y), resized)

    output_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = output_dir / f"{name}_atlas.png"
    atlas.save(atlas_path, 'PNG')
    print(f"  Saved: {atlas_path}")

    generate_effect_tres(name, num_columns, output_dir)
    return atlas


def generate_effect_tres(name, columns, output_dir):
    """Generate effect atlas .tres resource."""
    content = f'''[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/effects/{name}_atlas.png" id="1"]

[resource]
texture = ExtResource("1")
columns = {columns}
rows = 8
frame_size = Vector2({FRAME_SIZE}, {FRAME_SIZE})
'''
    tres_path = output_dir / f"{name}_atlas.tres"
    with open(tres_path, 'w') as f:
        f.write(content)
    print(f"  Saved: {tres_path}")


def process_named_folder(folder_name, output_name):
    """Process a named spell folder."""
    print(f"\nProcessing {folder_name}...")
    folder = INPUT_DIR / folder_name
    if not folder.exists():
        print(f"  Folder not found: {folder}")
        return

    frames = load_frames_from_folder(folder)
    if frames:
        create_directional_atlas(frames, output_name, OUTPUT_DIR)


def process_assorted():
    """Process assorted spell effects, grouping by animation."""
    print("\nProcessing assorted spells...")
    folder = INPUT_DIR / "assorted"
    if not folder.exists():
        print("  Assorted folder not found")
        return

    frames = load_frames_from_folder(folder)

    # Group frames by animation (8 frames per animation)
    animations = {}
    for frame_num, dir_frames in frames.items():
        anim_group = frame_num // 8
        if anim_group not in animations:
            animations[anim_group] = {}
        animations[anim_group][frame_num] = dir_frames

    # Name the animations based on frame ranges
    anim_names = {
        0: "magic_missile_1",   # 000-007
        1: "magic_missile_2",   # 008-015
        2: "magic_missile_3",   # 016-023
        3: "magic_missile_4",   # 024-031
        4: "fire_skull",        # 032-039 (duplicate from Fire Skull folder)
        5: "lightning_1",       # 040-047
        6: "lightning_2",       # 048-055
        7: "attack_spell_1",    # 056-063
        8: "attack_spell_2",    # 064-071
        9: "ice_shard_1",       # 072-079
        10: "ice_shard_2",      # 080-087
        11: "holy_light",       # 088-095
    }

    for anim_group, group_frames in sorted(animations.items()):
        name = anim_names.get(anim_group, f"spell_misc_{anim_group}")
        create_directional_atlas(group_frames, name, OUTPUT_DIR)


def main():
    print("Converting SPELLS sprites to effect atlases...")
    print(f"Input: {INPUT_DIR}")
    print(f"Output: {OUTPUT_DIR}")

    # Process named folders
    process_named_folder("Attack", "attack_spell")
    process_named_folder("Fire Skull", "fire_skull_projectile")
    process_named_folder("Fire Wall", "fire_wall")
    process_named_folder("Smite", "smite")

    # Process assorted effects
    process_assorted()

    print("\nDone!")


if __name__ == "__main__":
    main()
