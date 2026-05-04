# package_release.ps1 [version]
# Mirrors the mod into ..\reisen_release (and optionally stamps version).
# Works when called from Git Bash, PowerShell, or cmd:
#   powershell -File tools\package_release.ps1 3.0.8
#   pwsh       -File tools\package_release.ps1 3.0.8

param(
    [string]$Version = ""
)

$ErrorActionPreference = 'Stop'

$toolsDir  = $PSScriptRoot
$modRoot   = Split-Path $toolsDir -Parent
$releaseDir = Join-Path (Split-Path $modRoot -Parent) 'reisen_release'

$modinfo   = Join-Path $modRoot 'modinfo.lua'
$changelog = Join-Path $modRoot 'changelog.txt'

# ── Resolve version ────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Version)) {
    $m = Select-String -LiteralPath $modinfo -Pattern '^\s*version\s*=\s*"([^"]+)"'
    if (-not $m) { Write-Error "Cannot parse version from modinfo.lua"; exit 3 }
    $Version = $m.Matches[0].Groups[1].Value
    Write-Host "[package_release] No version arg — using modinfo: $Version (packaging only, no stamp)"
} else {
    Write-Host "[package_release] Stamping + packaging version $Version"
    & "$toolsDir\stamp_version.ps1" -Version $Version -ModRoot $modRoot
    Write-Host "[package_release] Stamp OK"
}

# ── Clean release dir ──────────────────────────────────────────────────────────
if (Test-Path -LiteralPath $releaseDir) {
    Write-Host "[package_release] Removing old release folder..."
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $releaseDir | Out-Null

# ── Copy folders ───────────────────────────────────────────────────────────────
foreach ($folder in @('anim', 'bigportraits', 'images', 'scripts')) {
    $src = Join-Path $modRoot $folder
    $dst = Join-Path $releaseDir $folder
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Folder missing, skipping: $folder"
        continue
    }
    Write-Host "[package_release] Copying $folder..."
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}

# ── Copy root files ────────────────────────────────────────────────────────────
$rootFiles = @('modmain.lua','modinfo.lua','modicon.tex','modicon.xml','changelog.txt')
foreach ($f in $rootFiles) {
    $src = Join-Path $modRoot $f
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Root file missing, skipping: $f"
        continue
    }
    Copy-Item -LiteralPath $src -Destination $releaseDir -Force
}

# mod.manifest is optional
$manifest = Join-Path $modRoot 'mod.manifest'
if (Test-Path -LiteralPath $manifest) {
    Copy-Item -LiteralPath $manifest -Destination $releaseDir -Force
}

Write-Host ""
Write-Host "[package_release] Release $Version ready at:"
Write-Host "  $releaseDir"
Write-Host "Upload to Steam Workshop from that folder."
