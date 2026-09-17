# Define paths the capture tools use in one place.
#
# Previously each script had `D:\Github\hyodotdev\MoonlitBeacon\...`
# hard-coded. This repo is going open source, so that dies on someone else's PC.
# Walk up from the script location to the repo root.
#
#   notes/tools/capture/paths.ps1  ->  ..\..\..  = repo root

$script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:BuildsDir  = Join-Path $RepoRoot 'builds'
$script:FootageDir = Join-Path $BuildsDir 'footage'
$script:TakeDir    = Join-Path $BuildsDir 'take'
$script:TakeProj   = Join-Path $TakeDir  'moonlit-beacon'
$script:RealProj   = Join-Path $RepoRoot 'apps\game'

# Godot executable. Same search order as scripts/godot.mjs in package.json.
#   1. GODOT_BIN
#   2. godot on PATH
#   3. winget install location
# Here a window must open, so pick the regular exe, not the console build (_console.exe).
function Resolve-Godot {
  if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }

  $onPath = Get-Command godot -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }

  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $hit = Get-ChildItem $winget -Filter 'Godot*' -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { Get-ChildItem $_.FullName -Filter 'Godot*.exe' -ErrorAction SilentlyContinue } |
      Where-Object { $_.Name -notlike '*console*' } |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }

  throw "Could not find Godot. Set GODOT_BIN to the full path."
}

$script:GodotExe = Resolve-Godot
