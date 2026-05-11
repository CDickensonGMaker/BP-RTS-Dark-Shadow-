@echo off
REM Batch normalize all artillery models to target heights
REM Requires Blender to be installed and in PATH, or set BLENDER_PATH below

SET BLENDER_PATH=blender
SET SCRIPT_PATH=%~dp0normalize_artillery.py
SET MODELS_PATH=%~dp0..\..\assets\models\3d units

echo ===========================================
echo Artillery Model Normalizer
echo ===========================================
echo.

REM Great Cannon - target height 1.5m (barrel at crew chest level)
echo Processing: Great Cannon (target: 1.5m)
"%BLENDER_PATH%" --background --python "%SCRIPT_PATH%" -- "%MODELS_PATH%\great_cannon.glb" "%MODELS_PATH%\great_cannon_normalized.glb" 1.5
echo.

REM Medieval Mortar - target height 1.2m (short, squat profile)
echo Processing: Medieval Mortar (target: 1.2m)
"%BLENDER_PATH%" --background --python "%SCRIPT_PATH%" -- "%MODELS_PATH%\medieval_mortar.glb" "%MODELS_PATH%\medieval_mortar_normalized.glb" 1.2
echo.

REM Great Catapult - target height 3.5m (towers over crew)
echo Processing: Great Catapult (target: 3.5m)
"%BLENDER_PATH%" --background --python "%SCRIPT_PATH%" -- "%MODELS_PATH%\great_catapult.glb" "%MODELS_PATH%\great_catapult_normalized.glb" 3.5
echo.

echo ===========================================
echo Done! Normalized models created with _normalized suffix.
echo After testing, rename to replace originals.
echo ===========================================
pause
