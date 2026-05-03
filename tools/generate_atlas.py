#!/usr/bin/env python3
"""
Sprite Atlas Generator for SOTHR sprites.
Packs BMP frames into a single PNG atlas for use with Godot's SpriteFormation.

Usage: python tools/generate_atlas.py [UNIT_NAME]
       python tools/generate_atlas.py GRTSWORD
       python tools/generate_atlas.py --all
"""

import os
import sys
from pathlib import Path
from PIL import Image

# Configuration
SPRITES_INPUT_DIR = Path("sothr_sprites_output")
SPRITES_OUTPUT_DIR = Path("assets/sprites")

DIRECTIONS = 8
FRAMES_PER_DIRECTION = 13
TOTAL_FRAMES = DIRECTIONS * FRAMES_PER_DIRECTION
ATLAS_COLUMNS = FRAMES_PER_DIRECTION  # 13 columns
ATLAS_ROWS = DIRECTIONS  # 8 rows

# Magenta chroma key
CHROMA_KEY = (255, 0, 255)
CHROMA_THRESHOLD = 30  # Color distance threshold


def apply_chroma_key(image: Image.Image) -> Image.Image:
    """Convert magenta pixels to transparent."""
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    pixels = image.load()
    width, height = image.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            # Check if pixel is close to magenta
            diff = abs(r - CHROMA_KEY[0]) + abs(g - CHROMA_KEY[1]) + abs(b - CHROMA_KEY[2])
            if diff < CHROMA_THRESHOLD:
                pixels[x, y] = (0, 0, 0, 0)  # Fully transparent

    return image


def generate_atlas(unit_name: str, input_dir: Path, output_dir: Path) -> bool:
    """Generate atlas for a single unit."""
    print(f"\nGenerating atlas for: {unit_name}")

    unit_path = input_dir / unit_name
    if not unit_path.exists():
        print(f"  ERROR: Unit folder not found: {unit_path}")
        return False

    # Load all frames
    frames = []
    frame_size = None

    for i in range(TOTAL_FRAMES):
        bmp_path = unit_path / f"{unit_name}_{i:02d}.bmp"

        if bmp_path.exists():
            try:
                img = Image.open(bmp_path)
                if frame_size is None:
                    frame_size = img.size
                    print(f"  Frame size: {frame_size[0]}x{frame_size[1]}")

                img = apply_chroma_key(img)
                frames.append(img)
            except Exception as e:
                print(f"  ERROR loading {bmp_path}: {e}")
                if frame_size:
                    placeholder = Image.new('RGBA', frame_size, (0, 0, 0, 0))
                    frames.append(placeholder)
        else:
            print(f"  Missing: {bmp_path.name}")
            if frame_size:
                placeholder = Image.new('RGBA', frame_size, (0, 0, 0, 0))
                frames.append(placeholder)

    if not frames or frame_size is None:
        print(f"  ERROR: No frames loaded for {unit_name}")
        return False

    print(f"  Loaded {len(frames)} frames")

    # Create atlas
    atlas_width = frame_size[0] * ATLAS_COLUMNS
    atlas_height = frame_size[1] * ATLAS_ROWS
    print(f"  Atlas size: {atlas_width}x{atlas_height}")

    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    # Pack frames into atlas
    # Layout: rows = directions (0-7), columns = frame index (0-12)
    for frame_idx, frame in enumerate(frames):
        direction = frame_idx // FRAMES_PER_DIRECTION
        frame_in_dir = frame_idx % FRAMES_PER_DIRECTION

        dest_x = frame_in_dir * frame_size[0]
        dest_y = direction * frame_size[1]

        atlas.paste(frame, (dest_x, dest_y))

    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save atlas
    output_path = output_dir / f"{unit_name.lower()}_atlas.png"
    atlas.save(output_path, 'PNG')
    print(f"  Saved: {output_path}")

    return True


def get_all_units(input_dir: Path) -> list:
    """Get list of all unit folders."""
    units = []
    if input_dir.exists():
        for item in input_dir.iterdir():
            if item.is_dir() and not item.name.startswith('.'):
                # Check if it has BMP files
                bmps = list(item.glob("*.bmp"))
                if bmps:
                    units.append(item.name)
    return sorted(units)


def main():
    # Change to project directory
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    os.chdir(project_dir)

    print("=== Sprite Atlas Generator ===")
    print(f"Project dir: {project_dir}")

    input_dir = SPRITES_INPUT_DIR
    output_dir = SPRITES_OUTPUT_DIR

    if not input_dir.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    # Determine which units to process
    if len(sys.argv) > 1:
        if sys.argv[1] == '--all':
            units = get_all_units(input_dir)
            print(f"Processing all {len(units)} units...")
        else:
            units = sys.argv[1:]
    else:
        # Default to GRTSWORD for testing
        units = ["GRTSWORD"]

    # Generate atlases
    success_count = 0
    for unit in units:
        if generate_atlas(unit, input_dir, output_dir):
            success_count += 1

    print(f"\n=== Complete: {success_count}/{len(units)} atlases generated ===")

    if success_count > 0:
        print("\nNext steps:")
        print("1. Open Godot Editor")
        print("2. Create SpriteUnitAtlas resource (.tres) for each atlas")
        print("3. Set texture, columns=13, rows=8")
        print("4. Assign to Regiment's sprite_atlas property")


if __name__ == "__main__":
    main()
