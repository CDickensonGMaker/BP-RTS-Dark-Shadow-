@echo off
REM BattleDebug Daemon Launcher
REM Run this overnight to automatically test and fix combat issues

REM Set your Anthropic API key here (or set it in system environment variables)
REM Get a key from: https://console.anthropic.com/
set ANTHROPIC_API_KEY=your-api-key-here

cd /d "%~dp0"

echo ================================================
echo  BattleDebug Daemon
echo  Autonomous Combat Testing and Fixing
echo ================================================
echo.

REM Check if API key is set
if "%ANTHROPIC_API_KEY%"=="your-api-key-here" (
    echo WARNING: ANTHROPIC_API_KEY not set!
    echo The daemon will run in analysis-only mode.
    echo To enable auto-fixing, edit this file and add your API key.
    echo.
    pause
)

REM Run the daemon
REM --hours 8    = Run for 8 hours (overnight)
REM --rounds 10  = 10 stress test battles per cycle
REM --dry-run    = Add this flag to test without applying fixes

python battle_daemon.py --hours 8 --rounds 10

echo.
echo Daemon finished. Check daemon_log.json for results.
pause
