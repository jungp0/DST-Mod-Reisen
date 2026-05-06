# Stamps modinfo.lua version line and changelog header/footer (UTF-8 no BOM).
# Called from make_release.bat — do not rely on env vars set only in the parent shell.

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ModRoot
)

$ErrorActionPreference = 'Stop'
$u8 = New-Object System.Text.UTF8Encoding $false

$modinfo = Join-Path $ModRoot 'modinfo.lua'
$changelog = Join-Path $ModRoot 'changelog.txt'

if (-not (Test-Path -LiteralPath $modinfo)) {
    Write-Error "modinfo.lua not found: $modinfo"
    exit 42
}
if (-not (Test-Path -LiteralPath $changelog)) {
    Write-Error "changelog.txt not found: $changelog"
    exit 43
}

$lines = [System.IO.File]::ReadAllLines($modinfo, $u8)
$done = $false
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\s*version\s*=') {
        $lines[$i] = 'version = "' + $Version + '"'
        $done = $true
        break
    }
}
if (-not $done) {
    Write-Error "No version = line found in modinfo.lua"
    exit 44
}
[System.IO.File]::WriteAllLines($modinfo, $lines, $u8)

$txt = [System.IO.File]::ReadAllText($changelog, $u8)
$d = Get-Date -Format 'dd.MM.yyyy'
$txt = $txt -replace 'Changelog \(Last Update:[^)]+\)', ('Changelog (Last Update: ' + $d + ' - Version ' + $Version + ')')
$txt = $txt -replace 'Current Mod Version: \[[^\]]*\]', ('Current Mod Version: [' + $Version + ']')
[System.IO.File]::WriteAllText($changelog, $txt, $u8)

Write-Host "[stamp_version.ps1] OK $Version"
