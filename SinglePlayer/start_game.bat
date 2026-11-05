@echo off
if not exist "%~dp0Windows\YachtDuel.exe" (echo Game build missing. Run build_game.bat. & pause & exit /b 1)
start "" "%~dp0Windows\YachtDuel.exe"
