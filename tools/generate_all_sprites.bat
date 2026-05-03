@echo off
echo ==========================================
echo SOTHR Sprite Atlas Generator
echo ==========================================
echo.

cd /d "%~dp0"

REM Check for Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found! Please install Python 3.
    pause
    exit /b 1
)

REM Check for Pillow
python -c "import PIL" >nul 2>&1
if errorlevel 1 (
    echo Installing Pillow library...
    pip install Pillow
)

echo.
echo Processing all unit sprites...
echo.

python sprite_atlas_generator.py --force %*

echo.
echo ==========================================
echo Done! Check assets/sprites/units/ for output
echo ==========================================
pause
