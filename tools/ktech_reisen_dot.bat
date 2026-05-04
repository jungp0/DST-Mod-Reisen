@echo off
setlocal EnableDelayedExpansion

REM Convert images\reisen_dot.png -> images\reisen_dot.tex using ktech (ktools).
REM Set KTECH to the full path of ktech.exe if not using the default below.

set "MOD_ROOT=%~dp0.."
set "IMG=%MOD_ROOT%\images"

if defined KTECH (
  set "KT=!KTECH!"
) else if exist "E:\Workspace\ktools\build\Release\ktech.exe" (
  set "KT=E:\Workspace\ktools\build\Release\ktech.exe"
) else if exist "E:\workspace\ktools\build\Release\ktech.exe" (
  set "KT=E:\workspace\ktools\build\Release\ktech.exe"
) else if exist "E:\Workspace\ktools\build\ktech.exe" (
  set "KT=E:\Workspace\ktools\build\ktech.exe"
) else if exist "E:\workspace\ktools\build\ktech.exe" (
  set "KT=E:\workspace\ktools\build\ktech.exe"
) else (
  echo Set KTECH to your ktech.exe path, e.g.:
  echo   set KTECH=E:\workspace\ktools\build\Release\ktech.exe
  exit /b 1
)

echo ktech: reisen_dot.png -^> reisen_dot.tex
"%KT%" --no-mipmaps -c rgba "%IMG%\reisen_dot.png" "%IMG%\reisen_dot.tex"
if errorlevel 1 (
  echo ERROR: ktech failed for reisen_dot
  exit /b 1
)

echo Done. Restart DST or reload the mod to refresh HUD dot icons.
