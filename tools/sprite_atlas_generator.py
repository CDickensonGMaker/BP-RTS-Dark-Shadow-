#!/usr/bin/env python3
"""
SOTHR Sprite Atlas Generator (v2 - Labeled PNG Support)
Converts labeled PNG sprite frames into Godot-ready atlas PNGs and .tres resources.

Expects input format: UNITNAME/AnimType/UNITNAME_FRAMENUM_DIR.png
Output: atlas PNG with 8 rows (directions) and N columns (animation frames)

Usage:
    python sprite_atlas_generator.py                    # Process all units
    python sprite_atlas_generator.py MCSWORD ORCBOYZ    # Process specific units
    python sprite_atlas_generator.py --list             # List available units
"""

import os
import sys
from pathlib import Path
from PIL import Image

# Configuration
SPRITES_INPUT_DIR = Path(__file__).parent.parent / "sothr_sprites_labeled"
SPRITES_OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "sprites" / "units"
FRAME_SIZE = 80  # 80x80 pixels per frame (larger for better visibility)
ROWS = 8         # 8 directions

# Direction order - must match engine expectation (clockwise from North):
# Row 0 = North, Row 1 = NE, Row 2 = E, Row 3 = SE, Row 4 = S, Row 5 = SW, Row 6 = W, Row 7 = NW
# This matches the SotHR extractor output: N, NE, E, SE, S, SW, W, NW
DIRECTIONS_8 = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# 16 directions (used by artillery) - clockwise from North
DIRECTIONS_16 = [
    "N", "NNE", "NE", "ENE",
    "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW",
    "W", "WNW", "NW", "NNW"
]

# Map 16 directions to 8 directions (take every other direction)
# N(0)->N, NNE(1)->skip, NE(2)->NE, ENE(3)->skip, etc.
DIR_16_TO_8 = {
    "N": "N", "NE": "NE", "E": "E", "SE": "SE",
    "S": "S", "SW": "SW", "W": "W", "NW": "NW"
}

DIRECTIONS = DIRECTIONS_8  # Default for atlas output

# Animation order for atlas columns
ANIMATION_ORDER = ["Idle", "Walk", "Attack", "Dead"]


def get_unit_folders(input_dir: Path) -> list:
    """Get list of unit folders that contain labeled PNG sprites."""
    units = []

    for item in input_dir.iterdir():
        if not item.is_dir():
            continue

        # Check if folder contains animation subfolders
        anim_folders = [f for f in item.iterdir() if f.is_dir() and f.name in ANIMATION_ORDER]
        if anim_folders:
            units.append(item)

    return sorted(units, key=lambda x: x.name)


def load_labeled_sprites(unit_dir: Path) -> dict:
    """
    Load all labeled PNG sprites for a unit.
    Handles both 8-direction and 16-direction input (downsamples 16 to 8).
    Returns dict: {direction: {animation: [frame_images in order]}}
    """
    sprites = {d: {a: [] for a in ANIMATION_ORDER} for d in DIRECTIONS}

    for anim_name in ANIMATION_ORDER:
        anim_dir = unit_dir / anim_name
        if not anim_dir.exists():
            continue

        # Collect frames by direction (support both 8 and 16 dir formats)
        frames_by_dir = {d: [] for d in DIRECTIONS}

        for png_file in anim_dir.glob("*.png"):
            if ".import" in png_file.name:
                continue

            # Parse filename: UNITNAME_DIR_FRAMENUM.png (e.g., "MORTAR_NNE_01.png")
            stem = png_file.stem
            parts = stem.rsplit('_', 2)

            if len(parts) >= 3:
                direction = parts[-2]
                try:
                    frame_num = int(parts[-1])
                except ValueError:
                    continue

                # Handle 16-direction input by mapping to 8 directions
                if direction in DIRECTIONS_8:
                    target_dir = direction
                elif direction in DIR_16_TO_8:
                    target_dir = DIR_16_TO_8[direction]
                elif direction in DIRECTIONS_16:
                    # This is an intermediate direction (NNE, ENE, etc.) - skip it
                    continue
                else:
                    continue

                try:
                    img = Image.open(png_file)
                    if img.mode != 'RGBA':
                        img = img.convert('RGBA')
                    frames_by_dir[target_dir].append((frame_num, img))
                except Exception as e:
                    print(f"  Warning: Failed to load {png_file.name}: {e}")

        # Sort by frame number and add to sprites dict
        for direction in DIRECTIONS:
            frames_by_dir[direction].sort(key=lambda x: x[0])
            sprites[direction][anim_name] = [img for _, img in frames_by_dir[direction]]

    return sprites


def count_animation_frames(sprites: dict) -> dict:
    """Count frames per animation (should be same for all directions)."""
    frame_counts = {}

    # Use first direction with data as reference
    for direction in DIRECTIONS:
        for anim in ANIMATION_ORDER:
            if sprites[direction][anim]:
                if anim not in frame_counts:
                    frame_counts[anim] = len(sprites[direction][anim])

    return frame_counts


def resize_frame_improved(img: Image.Image, target_size: int) -> Image.Image:
    """
    Resize frame to target size with improved quality.
    - Uses LANCZOS resampling for better quality
    - Maintains aspect ratio
    - Positions sprite at bottom (feet on ground)
    - Uses 95% of target size to leave small margin
    """
    result = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))

    if img.size == (target_size, target_size):
        return img

    # Get original dimensions
    orig_w, orig_h = img.size

    # Use 95% of target size to leave margin
    usable_size = int(target_size * 0.95)

    # Calculate scale to fit while maintaining aspect ratio
    scale = min(usable_size / orig_w, usable_size / orig_h)

    new_w = int(orig_w * scale)
    new_h = int(orig_h * scale)

    if new_w > 0 and new_h > 0:
        # Use LANCZOS for high quality downscaling
        resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

        # Center horizontally, align to bottom (feet on ground)
        x = (target_size - new_w) // 2
        y = target_size - new_h - 2  # 2px margin from bottom

        # Paste with alpha mask
        result.paste(resized, (x, y), resized)

    return result


def create_atlas(sprites: dict, frame_counts: dict, frame_size: int) -> tuple:
    """
    Create atlas image and calculate animation layout.
    Returns (atlas_image, animations_dict, columns)
    """
    # Calculate total columns needed
    total_frames = sum(frame_counts.get(a, 0) for a in ANIMATION_ORDER)
    columns = max(total_frames, 1)

    atlas_width = columns * frame_size
    atlas_height = ROWS * frame_size

    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    # Track animation positions for .tres file
    animations = {}
    current_col = 0

    for anim in ANIMATION_ORDER:
        frame_count = frame_counts.get(anim, 0)
        if frame_count == 0:
            continue

        animations[anim.lower()] = {
            "start_frame": current_col,
            "frame_count": frame_count
        }

        # Place frames for each direction (row)
        for row_idx, direction in enumerate(DIRECTIONS):
            frames = sprites[direction][anim]

            for frame_idx, img in enumerate(frames):
                col = current_col + frame_idx

                # Resize frame to fit, maintaining aspect ratio and positioning at bottom
                resized_frame = resize_frame_improved(img, frame_size)

                x = col * frame_size
                y = row_idx * frame_size
                atlas.paste(resized_frame, (x, y), resized_frame)  # Use alpha mask

        current_col += frame_count

    return atlas, animations, columns


def generate_tres_file(unit_name: str, animations: dict, columns: int) -> str:
    """Generate Godot .tres resource file content."""
    texture_path = f"res://assets/sprites/units/{unit_name}_atlas.png"

    # Format animations dictionary for Godot
    anim_lines = []
    for name, data in animations.items():
        anim_lines.append(f'"{name}": {{"start_frame": {data["start_frame"]}, "frame_count": {data["frame_count"]}}}')

    anim_str = ",\n".join(anim_lines)

    content = f'''[gd_resource type="Resource" script_class="SpriteUnitAtlas" load_steps=3 format=3]

[ext_resource type="Texture2D" path="{texture_path}" id="1"]
[ext_resource type="Script" path="res://battle_system/data/sprite_unit_atlas.gd" id="2"]

[resource]
script = ExtResource("2")
texture = ExtResource("1")
columns = {columns}
rows = {ROWS}
frame_size = Vector2({FRAME_SIZE}, {FRAME_SIZE})
directions = {ROWS}
animation_speed = 8.0
animations = {{
{anim_str}
}}
'''
    return content


def process_unit(unit_dir: Path, output_dir: Path, force: bool = False) -> bool:
    """Process a single unit: create atlas PNG and .tres file."""
    unit_name = unit_dir.name.lower()

    atlas_png = output_dir / f"{unit_name}_atlas.png"
    atlas_tres = output_dir / f"{unit_name}_atlas.tres"

    # Skip if already exists (unless force)
    if not force and atlas_png.exists() and atlas_tres.exists():
        print(f"  Skipping {unit_name} (already exists)")
        return True

    print(f"  Processing {unit_name}...")

    # Load labeled sprites
    sprites = load_labeled_sprites(unit_dir)

    # Count frames per animation
    frame_counts = count_animation_frames(sprites)

    if not frame_counts:
        print(f"    Error: No animation frames found")
        return False

    total_frames = sum(frame_counts.values())
    print(f"    Found {total_frames} total frames: ", end="")
    print(", ".join(f"{a}={c}" for a, c in frame_counts.items()))

    # Create atlas
    atlas, animations, columns = create_atlas(sprites, frame_counts, FRAME_SIZE)

    print(f"    Atlas size: {atlas.width}x{atlas.height} ({columns} cols x {ROWS} rows)")

    # Save atlas PNG
    atlas.save(atlas_png, 'PNG')
    print(f"    Created {atlas_png.name}")

    # Generate and save .tres file
    tres_content = generate_tres_file(unit_name, animations, columns)
    with open(atlas_tres, 'w') as f:
        f.write(tres_content)
    print(f"    Created {atlas_tres.name}")

    return True


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate sprite atlases from labeled SOTHR sprites")
    parser.add_argument("units", nargs="*", help="Specific units to process (default: all)")
    parser.add_argument("--list", action="store_true", help="List available units")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    parser.add_argument("--input", type=Path, default=SPRITES_INPUT_DIR, help="Input directory")
    parser.add_argument("--output", type=Path, default=SPRITES_OUTPUT_DIR, help="Output directory")

    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: Input directory not found: {args.input}")
        return

    # Find all unit folders
    all_units = get_unit_folders(args.input)

    if args.list:
        print(f"Available units in {args.input}:")
        for unit in all_units:
            anims = [d.name for d in unit.iterdir() if d.is_dir() and d.name in ANIMATION_ORDER]
            print(f"  {unit.name}: {', '.join(anims)}")
        return

    # Filter to specific units if provided
    if args.units:
        unit_names = [u.upper() for u in args.units]
        units_to_process = [u for u in all_units if u.name.upper() in unit_names]

        # Check for missing units
        found_names = [u.name.upper() for u in units_to_process]
        for name in unit_names:
            if name not in found_names:
                print(f"Warning: Unit '{name}' not found")
    else:
        units_to_process = all_units

    if not units_to_process:
        print("No units to process!")
        return

    # Create output directory
    args.output.mkdir(parents=True, exist_ok=True)

    print(f"Processing {len(units_to_process)} units...")
    print(f"Input: {args.input}")
    print(f"Output: {args.output}")
    print()

    success = 0
    failed = 0

    for unit_dir in units_to_process:
        if process_unit(unit_dir, args.output, args.force):
            success += 1
        else:
            failed += 1

    print()
    print(f"Done! Success: {success}, Failed: {failed}")


if __name__ == "__main__":
    main()
