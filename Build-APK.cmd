@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel% equ 0 (
  py -3 scripts\build_android.py
) else (
  python scripts\build_android.py
)
if %errorlevel% neq 0 (
  echo Build failed. See docs\ANDROID.md for prerequisites.
  pause
  exit /b 1
)
echo APK is in the dist folder.
pause
