# Grab one frame of the right monitor (= the screen Godot is filling).
#
# Two reasons not to use window capture (-i "title=...").
#   1. Window capture holds only the client area, so coordinates are off by the title bar.
#   2. Godot menu dropdowns are separate OS popups even with single_window_mode,
#      so window capture misses them. Desktop capture does not.
#
# The Godot window exactly covers the right monitor, so no other window enters this region.
# The left monitor (Roblox and so on) is outside the capture range to begin with.
#
#   .\grab.ps1 out.png                 full (1280 wide, screen coords = 3840 + x*3, y*3)
#   .\grab.ps1 out.png 900 200 1200 600   native scale, w,h from physical offset x,y
param(
  [string]$Out,
  [int]$CropX = -1, [int]$CropY = 0, [int]$CropW = 0, [int]$CropH = 0
)
if ($CropX -ge 0) {
  $ox = 3840 + $CropX; $oy = $CropY
  ffmpeg -y -hide_banner -loglevel error -f gdigrab -framerate 2 `
    -offset_x $ox -offset_y $oy -video_size "${CropW}x${CropH}" -i desktop `
    -frames:v 1 $Out
} else {
  ffmpeg -y -hide_banner -loglevel error -f gdigrab -framerate 2 `
    -offset_x 3840 -offset_y 0 -video_size 3840x2160 -i desktop `
    -frames:v 1 -vf "scale=1280:-2" $Out
}
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL exit=$LASTEXITCODE"; exit 1 }
$i = Get-Item $Out
Write-Output "$($i.Name)  $($i.Length) bytes"
