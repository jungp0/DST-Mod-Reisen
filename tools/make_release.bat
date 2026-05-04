@echo off

setlocal EnableDelayedExpansion



:: -------------------------------------------------------

:: make_release.bat [VERSION]

::

::   Double-click (or run from cmd.exe) to stamp + package.

::   From Git Bash use package_release.ps1 instead — Git Bash converts

::   the /c flag to C:/ and causes cmd.exe to hang interactively.

::

::   Preferred command line (works from Git Bash, PowerShell, cmd):

::     powershell -NoProfile -ExecutionPolicy Bypass -File tools\package_release.ps1 X.Y.Z

::

::   VERSION  Stamp modinfo.lua; update changelog header date + footer;

::            mirror mod folders into ..\reisen_release\

::

::   (omit)   Package using current version in modinfo.lua (no file edits).

::

:: -------------------------------------------------------



pushd "%~dp0.." 2>nul || (

    echo [%~nx0] ERROR: Cannot cd to mod root beside tools folder.

    exit /b 1

)

set "MOD_ROOT=!CD!"



for %%I in ("!MOD_ROOT!\..\reisen_release") do set "RELEASE_DIR=%%~fI"



set "MODINFO_PATH=!MOD_ROOT!\modinfo.lua"

set "CHANGELOG_PATH=!MOD_ROOT!\changelog.txt"



if not exist "!MODINFO_PATH!" (

    echo [%~nx0] ERROR: modinfo.lua missing: "!MODINFO_PATH!"

    popd

    exit /b 2

)



set "NEW_VER=%~1"

if "!NEW_VER!"=="" (

    for /f "tokens=2 delims== " %%v in ('findstr /b /c:"version =" "!MODINFO_PATH!"') do set "NEW_VER=%%~v"

    if "!NEW_VER!"=="" (

        echo [%~nx0] ERROR: Could not parse version from modinfo.lua.

        popd

        exit /b 3

    )

    echo No VERSION argument. Using modinfo.lua: !NEW_VER!

    echo Packaging without stamping.

    set "DO_STAMP=0"

) else (

    echo Stamping and packaging: !NEW_VER!

    set "DO_STAMP=1"

)



if "!DO_STAMP!"=="1" (

    echo.

    echo Running stamp_version.ps1 for !NEW_VER! ...

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stamp_version.ps1" -Version "!NEW_VER!" -ModRoot "!MOD_ROOT!"

    if errorlevel 1 (

        echo [%~nx0] ERROR: stamp_version.ps1 failed.

        popd

        exit /b 10

    )

    echo [OK] modinfo.lua + changelog stamped ^(UTF-8 no BOM^)

)



echo.

echo Cleaning: !RELEASE_DIR!

if exist "!RELEASE_DIR!" rmdir /s /q "!RELEASE_DIR!"

if exist "!RELEASE_DIR!" (

    echo [%~nx0] ERROR: Cannot remove old release folder ^(in use?^).

    popd

    exit /b 11

)

mkdir "!RELEASE_DIR!"

if not exist "!RELEASE_DIR!\." (

    echo [%~nx0] ERROR: Cannot create release folder.

    popd

    exit /b 12

)



echo Copying subfolders via robocopy /MIR ...

call :mirror_dir anim

if errorlevel 8 goto :pkg_fail

call :mirror_dir bigportraits

if errorlevel 8 goto :pkg_fail

call :mirror_dir images

if errorlevel 8 goto :pkg_fail

call :mirror_dir scripts

if errorlevel 8 goto :pkg_fail



echo Copying root files ...

copy /y "!MOD_ROOT!\modmain.lua" "!RELEASE_DIR!\" >nul || goto :pkg_fail

copy /y "!MOD_ROOT!\modinfo.lua" "!RELEASE_DIR!\" >nul || goto :pkg_fail

copy /y "!MOD_ROOT!\modicon.tex" "!RELEASE_DIR!\" >nul || goto :pkg_fail

copy /y "!MOD_ROOT!\modicon.xml" "!RELEASE_DIR!\" >nul || goto :pkg_fail

copy /y "!MOD_ROOT!\mod.manifest" "!RELEASE_DIR!\" >nul || goto :pkg_fail

copy /y "!MOD_ROOT!\changelog.txt" "!RELEASE_DIR!\" >nul || goto :pkg_fail



popd



echo.

echo Release !NEW_VER! ready at:

echo   !RELEASE_DIR!

echo.

echo Upload to Steam Workshop from that folder.

exit /b 0



:pkg_fail

echo [%~nx0] ERROR: Packaging failed.

popd

exit /b 20



:mirror_dir

set "SRC=!MOD_ROOT!\%~1"

set "DST=!RELEASE_DIR!\%~1"

if not exist "!SRC!\" (

    echo [%~nx0] WARN: Missing folder, skipping: %~1

    exit /b 0

)

robocopy "!SRC!" "!DST!" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP /XA:SH >nul

set "RC=!ERRORLEVEL!"

if !RC! GEQ 8 (

    echo [%~nx0] ERROR: robocopy %~1 failed ^(code !RC!^).

    exit /b 8

)

exit /b 0


