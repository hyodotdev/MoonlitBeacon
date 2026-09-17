# Reset the capture project to "a new project just created with Compatibility"
# and launch a fresh editor. take.ps1 coordinates assume this exact state.

. "$PSScriptRoot\paths.ps1"
$godot = $GodotExe
$proj  = $TakeProj

Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
New-Item -ItemType Directory -Path $proj -Force | Out-Null

$default = @'
config_version=5

[application]

config/name="Moonlit Beacon"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
# PowerShell 5.1 `Set-Content -Encoding utf8` attaches a BOM.
# Godot reads it as part of the key name, producing junk like `"ï»¿config_version"=5`,
# and the project opens broken so every later operation drifts. Write without a BOM.
[System.IO.File]::WriteAllText("$proj\project.godot", $default,
  (New-Object System.Text.UTF8Encoding $false))
$head = [System.IO.File]::ReadAllBytes("$proj\project.godot")[0..2] -join ','
Write-Output "project.godot initialized (first 3 bytes: $head — should be 99,111,110)"

Start-Process -FilePath $godot -ArgumentList @("-e", "--path", $proj)
Start-Sleep -Seconds 16

. "$PSScriptRoot\lib.ps1"
$h = Ready-Win
Write-Output "Editor ready. rect=$((Get-Rect $h).W)x$((Get-Rect $h).H)"
