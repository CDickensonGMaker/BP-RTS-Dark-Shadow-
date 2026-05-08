#!/usr/bin/env python3
"""
Convert GENBATT (general battlefield) sprites into useful atlases.

Processes:
- Arrows: Projectile sprites for ranged combat
- Dead bodies: Corpse sprites for battlefield
- Spell effects: Magic visual effects
- Birds: Ambient battlefield sprites

Output: Individual atlases for each category
"""

from PIL import Image
from pathlib import Path
import re

# Configuration
INPUT_DIR = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\sothr_sprites_labeled\GENeral sprites")
OUTPUT_DIR = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows\assets\sprites\effects")
FRAME_SIZE = 80

# Direction order matching SOTHR standard
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def parse_frame_info(filename):
    """Parse GENBATT_XXX_DIR.png filename."""
    match = re.match(r'GENBATT_(\d+)_(\w+)\.png', filename)
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
        # Center the sprite
        x = (target_size - new_w) // 2
        y = (target_size - new_h) // 2
        result.paste(resized, (x, y), resized)

    return result


def create_directional_atlas(frames_dict, name, output_dir):
    """
    Create an atlas from frames organized by direction.
    Rows = directions (8), Columns = animation frames.
    """
    if not frames_dict:
        print(f"  No frames found for {name}")
        return None

    # Get sorted frame numbers
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

    # Save atlas
    output_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = output_dir / f"{name}_atlas.png"
    atlas.save(atlas_path, 'PNG')
    print(f"  Saved: {atlas_path}")

    # Generate .tres file
    generate_effect_tres(name, num_columns, output_dir)

    return atlas


def generate_effect_tres(name, columns, output_dir):
    """Generate a simple effect atlas .tres resource."""
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


def create_simple_atlas(frames_list, name, output_dir, frame_size=FRAME_SIZE):
    """Create a simple linear atlas from a list of frames."""
    if not frames_list:
        print(f"  No frames found for {name}")
        return None

    num_frames = len(frames_list)
    # Arrange in a grid (roughly square)
    cols = min(8, num_frames)
    rows = (num_frames + cols - 1) // cols

    print(f"  Creating {name} atlas: {cols}x{rows} grid ({num_frames} frames)")

    atlas_w = cols * frame_size
    atlas_h = rows * frame_size
    atlas = Image.new('RGBA', (atlas_w, atlas_h), (0, 0, 0, 0))

    for idx, img in enumerate(frames_list):
        row = idx // cols
        col = idx % cols
        resized = resize_frame(img, frame_size)
        x = col * frame_size
        y = row * frame_size
        atlas.paste(resized, (x, y), resized)

    output_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = output_dir / f"{name}_atlas.png"
    atlas.save(atlas_path, 'PNG')
    print(f"  Saved: {atlas_path}")

    return atlas


def process_arrows():
    """Process arrow projectile sprites."""
    print("\nProcessing Arrows...")
    folder = INPUT_DIR / "Arrows"
    if not folder.exists():
        print("  Arrows folder not found")
        return

    frames = load_frames_from_folder(folder)
    create_directional_atlas(frames, "arrow", OUTPUT_DIR)


def process_dead_bodies():
    """Process dead body/corpse sprites."""
    print("\nProcessing Dead Bodies...")
    folder = INPUT_DIR / "Dead bodies"
    if not folder.exists():
        print("  Dead bodies folder not found")
        return

    frames = load_frames_from_folder(folder)
    create_directional_atlas(frames, "corpse", OUTPUT_DIR)


def process_spells():
    """Process spell effect sprites."""
    print("\nProcessing Spells and Casualties...")
    folder = INPUT_DIR / "spells and casutalties"
    if not folder.exists():
        print("  Spells folder not found")
        return

    frames = load_frames_from_folder(folder)

    # Group by animation (every 8 frames is a new animation cycle)
    # Frames 000-007, 008-015, etc. are different animations
    animations = {}
    for frame_num, dir_frames in frames.items():
        # Determine which animation group this belongs to
        anim_group = frame_num // 8
        if anim_group not in animations:
            animations[anim_group] = {}
        animations[anim_group][frame_num] = dir_frames

    # Create separate atlases for each animation type
    anim_names = {
        0: "spell_impact_1",  # 000-007
        1: "spell_impact_2",  # 008-015
        2: "spell_cast_1",    # 016-023
        3: "spell_cast_2",    # 024-031
        5: "spell_effect_1",  # 040-047
        6: "spell_effect_2",  # 048-055
    }

    for anim_group, group_frames in animations.items():
        name = anim_names.get(anim_group, f"spell_anim_{anim_group}")
        create_directional_atlas(group_frames, name, OUTPUT_DIR)


def process_birds():
    """Process bird ambient sprites."""
    print("\nProcessing Birds...")
    folder = INPUT_DIR / "birds"
    if not folder.exists():
        print("  Birds folder not found")
        return

    frames = load_frames_from_folder(folder)
    create_directional_atlas(frames, "birds", OUTPUT_DIR)


def process_explosions():
    """Process explosion effect sprites."""
    print("\nProcessing Explosions...")
    folder = INPUT_DIR / "explosions"
    if not folder.exists():
        print("  Explosions folder not found")
        return

    frames = load_frames_from_folder(folder)
    # Explosions might not be directional, just collect all frames
    all_frames = []
    for frame_num in sorted(frames.keys()):
        for direction in DIRECTIONS:
            if direction in frames[frame_num]:
                all_frames.append(frames[frame_num][direction])
                break  # Just use first direction found

    if all_frames:
        create_simple_atlas(all_frames, "explosion", OUTPUT_DIR)


def main():
    print("Converting GENBATT sprites to effect atlases...")
    print(f"Input: {INPUT_DIR}")
    print(f"Output: {OUTPUT_DIR}")

    process_arrows()
    process_dead_bodies()
    process_spells()
    process_birds()
    process_explosions()

    print("\nDone!")


if __name__ == "__main__":
    main()
