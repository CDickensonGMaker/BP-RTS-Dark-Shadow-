# Dark Omen Integration (Optional)

This folder contains configuration and scripts for integrating the [darkomen](https://github.com/mgi388/darkomen) Rust library with BP RTS Dark Shadows.

## What is darkomen?

A Rust library for reading and writing Warhammer: Dark Omen game files:
- 3D Models (.M3D, .M3X)
- Army files (.ARM)
- Battle tabletops (.BTB)
- Sprite sheets (.SPR)
- And more

## Integration Options

### Option A: CLI Tool (Recommended for Asset Pipeline)

1. Install Rust: https://www.rust-lang.org/tools/install
2. Install darkomen: `cargo install darkomen`
3. Use CLI commands to extract assets:
   ```bash
   # Extract all M3D models to assets/models/
   darkomen model extract DARKOMEN/GAMEDATA/MODELS/*.M3D --output ../../assets/models/
   
   # Extract sprite sheets to assets/sprites/
   darkomen sprite extract DARKOMEN/GAMEDATA/SPRITES/*.SPR --output ../../assets/sprites/
   ```
4. Import the extracted files into Godot

### Option B: GDExtension (Advanced - Runtime Loading)

For direct runtime loading of Dark Omen assets, create a GDExtension in `addons/darkomen_importer/`:

```toml
# addons/darkomen_importer/Cargo.toml
[package]
name = "darkomen_importer"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
godot = { version = "0.1", features = ["gdext"] }
darkomen = "0.5.0"
```

This allows Godot to directly load .M3D, .ARM files at runtime.

### Option C: Python Bridge (For Asset Processing Scripts)

Create Python scripts in `tools/darkomen/` that use darkomen via subprocess:

```python
# tools/darkomen/extract_assets.py
import subprocess
import os

def extract_models(input_path, output_path):
    subprocess.run([
        "darkomen", "model", "extract",
        input_path,
        "--output", output_path
    ])
```

## When to Use Dark Omen Assets

**Good for:**
- 3D models (units, buildings, terrain)
- Sprite sheets (unit portraits, icons)
- Sound effects
- Pre-existing animations

**Not needed for:**
- Core gameplay systems
- UI elements (better to create custom)
- Game logic and balancing

## Note

You must own a copy of Warhammer: Dark Omen to use its assets.
This integration is for personal/modding use only.
