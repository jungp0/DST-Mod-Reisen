@echo off
setlocal enabledelayedexpansion

rem Stexatlaser release (oblivioncth/Stexatlaser). Old 1.1.1.1 asset URLs return 404.
set STEX_TAG=v0.6
set STEX_URL=https://github.com/oblivioncth/Stexatlaser/releases/download/%STEX_TAG%/Stex_%STEX_TAG%_Windows_Shared_x64.zip
set OUT_ZIP=%~dp0bin\stex_download.zip
set BIN_DIR=%~dp0bin
set DEST_DIR=%BIN_DIR%\stex_v0.6

echo Downloading Stex %STEX_TAG% ...
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

curl -L -o "%OUT_ZIP%" "%STEX_URL%"
if errorlevel 1 (
    echo ERROR: Download failed. Check your internet connection.
    echo URL: %STEX_URL%
    echo.
    echo Alternatively, download manually from:
    echo   https://github.com/oblivioncth/Stexatlaser/releases
    echo and extract so Stex.exe is at: %DEST_DIR%\bin\Stex.exe
    pause
    exit /b 1
)

if exist "%DEST_DIR%" rmdir /s /q "%DEST_DIR%"
echo Extracting to %DEST_DIR% ...
powershell -Command "Expand-Archive -Force '%OUT_ZIP%' '%DEST_DIR%'"
del /q "%OUT_ZIP%"

if exist "%DEST_DIR%\bin\Stex.exe" (
    echo Done. Stex.exe: %DEST_DIR%\bin\Stex.exe
    echo Build scripts expect this path ^(see tools/build_*_from_triptych.py^).
) else (
    echo WARNING: Stex.exe not found after extraction.
    echo Please download manually from https://github.com/oblivioncth/Stexatlaser/releases
    echo and extract so Stex.exe is at: %DEST_DIR%\bin\Stex.exe
)
pause
