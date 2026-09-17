# Capture coordinate conversion.
#
# The Godot window sits on the right monitor at (3840,0) at 3840x2160.
# Coord-finding captures are 1280 wide, so the scale is exactly 3.
#   screen X = 3840 + image X * 3
#   screen Y =        image Y * 3
#
# Roblox holds the mouse on the left monitor. If the window is on the left,
# SetCursorPos is thrown back to the center of the screen. Always put it on the right.

. "$PSScriptRoot\drive.ps1"

$script:WIN_X = 3840
$script:WIN_Y = 0
$script:WIN_W = 3840
$script:WIN_H = 2160
$script:SCALE = 3

function IX($ix) { return $script:WIN_X + [int]($ix * $script:SCALE) }
function IY($iy) { return $script:WIN_Y + [int]($iy * $script:SCALE) }

# Click in image coordinates.
function IClick($ix, $iy, $pause = 300) { Click-At (IX $ix) (IY $iy) $pause }
function IDbl($ix, $iy, $pause = 300)   { DblClick-At (IX $ix) (IY $iy) $pause }
function IMove($ix, $iy)                { Move-To (IX $ix) (IY $iy) }
function IScroll($ix, $iy, $n)          { Scroll-At (IX $ix) (IY $iy) $n }

function Ready-Win {
  $h = Get-GodotWin
  Set-Rect $h $script:WIN_X $script:WIN_Y $script:WIN_W $script:WIN_H
  $ok = Focus-Win $h
  Start-Sleep -Milliseconds 400
  if (-not $ok) { throw "Focus failed" }
  return $h
}

function Shot($name) {
  & "$PSScriptRoot\grab.ps1" "$PSScriptRoot\$name" | Out-Null
}

# Read a pixel in image coordinates and wait.
function IPixel($ix, $iy) { return Get-PixelAt (IX $ix) (IY $iy) }
function IWait($ix, $iy, $want, $timeoutMs = 8000, $tol = 26) {
  return Wait-Color (IX $ix) (IY $iy) $want $timeoutMs $tol
}

# Measured probe colors (points relative to the 1280-wide image)
$script:C_DLG_BG    = @(27, 27, 27)      # (450,178) when the dialog is up
$script:C_TOGGLE_ON = @(86, 158, 255)    # (1008,178) Advanced Settings on

function Assert-Or-Die($ok, $msg) {
  if (-not $ok) { throw "Capture aborted: $msg" }
}
