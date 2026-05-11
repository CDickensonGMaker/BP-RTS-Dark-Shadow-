"""
Blender script to normalize siege weapon models to target sizes.

Usage:
    blender --background --python normalize_artillery.py -- <input.glb> <output.glb> <target_height>

Example:
    blender --background --python normalize_artillery.py -- great_cannon.glb great_cannon_normalized.glb 1.5

Or run interactively in Blender:
    - Open script in Blender's text editor
    - Modify TARGET_DIMENSIONS dictionary for your models
    - Run script
"""

import bpy
import sys
import os
from mathutils import Vector

# Target dimensions for siege weapons (in meters/Godot units)
# Height is the primary dimension to match
TARGET_DIMENSIONS = {
    "great_cannon": {"height": 1.5, "length": 3.0, "width": 1.2},
    "medieval_mortar": {"height": 1.2, "length": 1.5, "width": 1.5},
    "great_catapult": {"height": 3.5, "length": 3.5, "width": 2.5},
    "war_wagon": {"height": 2.5, "length": 4.0, "width": 2.0},
    "volley_gun": {"height": 1.8, "length": 2.5, "width": 1.5},
}


def get_scene_bounds():
    """Calculate the bounding box of all mesh objects in the scene."""
    min_co = Vector((float('inf'), float('inf'), float('inf')))
    max_co = Vector((float('-inf'), float('-inf'), float('-inf')))

    found_mesh = False
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            found_mesh = True
            # Get world-space bounding box corners
            bbox_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
            for corner in bbox_corners:
                min_co.x = min(min_co.x, corner.x)
                min_co.y = min(min_co.y, corner.y)
                min_co.z = min(min_co.z, corner.z)
                max_co.x = max(max_co.x, corner.x)
                max_co.y = max(max_co.y, corner.y)
                max_co.z = max(max_co.z, corner.z)

    if not found_mesh:
        return None, None, None

    size = max_co - min_co
    return {
        "width": size.x,   # X axis
        "height": size.z,  # Z axis (Blender Z = Godot Y for height)
        "length": size.y,  # Y axis (Blender Y = Godot Z for depth)
    }, min_co, max_co


def normalize_model(target_height: float, center_on_ground: bool = True):
    """
    Scale the model so its height matches target_height.
    Uses uniform scaling to preserve proportions.

    Args:
        target_height: Target height in meters/Godot units
        center_on_ground: If True, move model so bottom is at Y=0
    """
    bounds, min_co, max_co = get_scene_bounds()
    if bounds is None:
        print("ERROR: No mesh objects found in scene!")
        return False

    current_height = bounds["height"]
    if current_height <= 0:
        print(f"ERROR: Invalid model height: {current_height}")
        return False

    # Calculate uniform scale factor based on height
    scale_factor = target_height / current_height

    print(f"Current dimensions: {bounds['width']:.3f}W x {bounds['height']:.3f}H x {bounds['length']:.3f}L")
    print(f"Target height: {target_height}")
    print(f"Scale factor: {scale_factor:.4f}")

    # Select all objects and apply scale
    bpy.ops.object.select_all(action='SELECT')

    # Set 3D cursor to world origin
    bpy.context.scene.cursor.location = (0, 0, 0)

    # Scale all objects uniformly
    bpy.ops.transform.resize(value=(scale_factor, scale_factor, scale_factor))

    # Apply scale to mesh data
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Recalculate bounds after scaling
    new_bounds, new_min, new_max = get_scene_bounds()
    print(f"New dimensions: {new_bounds['width']:.3f}W x {new_bounds['height']:.3f}H x {new_bounds['length']:.3f}L")

    # Center on ground (move so bottom of model is at Z=0)
    if center_on_ground and new_min is not None:
        z_offset = -new_min.z
        for obj in bpy.context.scene.objects:
            if obj.type == 'MESH':
                obj.location.z += z_offset

        # Apply location
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

        print(f"Centered on ground (Z offset: {z_offset:.3f})")

    return True


def export_glb(output_path: str):
    """Export the scene as a GLB file."""
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_colors=True,
    )
    print(f"Exported to: {output_path}")


def print_model_info():
    """Print current model dimensions and statistics."""
    bounds, min_co, max_co = get_scene_bounds()
    if bounds is None:
        print("No mesh objects in scene")
        return

    print("\n=== Model Information ===")
    print(f"Dimensions (Blender coords):")
    print(f"  X (width):  {bounds['width']:.4f}")
    print(f"  Y (length): {bounds['length']:.4f}")
    print(f"  Z (height): {bounds['height']:.4f}")
    print(f"\nBounding box:")
    print(f"  Min: ({min_co.x:.4f}, {min_co.y:.4f}, {min_co.z:.4f})")
    print(f"  Max: ({max_co.x:.4f}, {max_co.y:.4f}, {max_co.z:.4f})")

    # Count vertices and faces
    total_verts = 0
    total_faces = 0
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            total_verts += len(obj.data.vertices)
            total_faces += len(obj.data.polygons)

    print(f"\nMesh statistics:")
    print(f"  Vertices: {total_verts}")
    print(f"  Faces: {total_faces}")
    print("========================\n")


def process_artillery_model(input_path: str, output_path: str, target_height: float):
    """
    Main processing function for normalizing an artillery model.

    Args:
        input_path: Path to input GLB file
        output_path: Path for output GLB file
        target_height: Target height in meters
    """
    print(f"\n{'='*50}")
    print(f"Processing: {input_path}")
    print(f"Target height: {target_height}m")
    print(f"{'='*50}\n")

    # Clear existing scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Import the model
    if input_path.lower().endswith('.glb') or input_path.lower().endswith('.gltf'):
        bpy.ops.import_scene.gltf(filepath=input_path)
    elif input_path.lower().endswith('.fbx'):
        bpy.ops.import_scene.fbx(filepath=input_path)
    elif input_path.lower().endswith('.obj'):
        bpy.ops.import_scene.obj(filepath=input_path)
    else:
        print(f"ERROR: Unsupported file format: {input_path}")
        return False

    print("Model imported successfully")
    print_model_info()

    # Normalize the model
    if not normalize_model(target_height):
        return False

    print("\nAfter normalization:")
    print_model_info()

    # Export
    export_glb(output_path)

    print(f"\nDone! Normalized model saved to: {output_path}")
    return True


def batch_process_artillery():
    """
    Process all artillery models in the assets/models/3d units/ directory.
    Creates normalized versions with _normalized suffix.
    """
    # Path relative to project root (adjust if needed)
    models_dir = "//assets/models/3d units/"

    models_to_process = [
        ("great_cannon.glb", 1.5),
        ("medieval_mortar.glb", 1.2),
        ("great_catapult.glb", 3.5),
    ]

    for model_name, target_height in models_to_process:
        input_path = bpy.path.abspath(models_dir + model_name)
        output_name = model_name.replace(".glb", "_normalized.glb")
        output_path = bpy.path.abspath(models_dir + output_name)

        if os.path.exists(input_path):
            process_artillery_model(input_path, output_path, target_height)
        else:
            print(f"WARNING: Model not found: {input_path}")


# Command-line interface
if __name__ == "__main__":
    # Check for command line arguments (after --)
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]

        if len(args) >= 3:
            input_file = args[0]
            output_file = args[1]
            target_height = float(args[2])
            process_artillery_model(input_file, output_file, target_height)
        elif len(args) == 1 and args[0] == "--batch":
            batch_process_artillery()
        else:
            print("Usage: blender --background --python normalize_artillery.py -- <input.glb> <output.glb> <target_height>")
            print("       blender --background --python normalize_artillery.py -- --batch")
    else:
        # Running in Blender UI - just print info about current scene
        print("\n=== Artillery Model Normalizer ===")
        print("Run from command line or modify script for batch processing.")
        print("\nCurrent scene info:")
        print_model_info()
