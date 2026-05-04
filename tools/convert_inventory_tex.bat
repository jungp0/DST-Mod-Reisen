@echo off
setlocal EnableDelayedExpansion

REM Convert Reisen inventory PNGs to .tex using ktech (ktools).
REM Set KTECH to the full path of ktech.exe if not using the default below.

set "MOD_ROOT=%~dp0.."
set "IMG=%MOD_ROOT%\images\inventoryimages"

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

for %%N in (reisen_casual reisen_uniform reisen_charm reisen_ointment) do (
  echo ktech: %%N.png -^> %%N.tex
  "%KT%" --no-mipmaps -c dxt5 "%IMG%\%%N.png" "%IMG%\%%N.tex"
  if errorlevel 1 (
    echo ERROR: ktech failed for %%N
    exit /b 1
  )
)

echo Done. Restart DST or reload the mod to refresh inventory icons.
