# The real recording. Run immediately after reset.ps1 initializes.
#
# Record only the right-monitor region. The Godot window exactly covers this
# monitor, so the left monitor (Roblox and so on) is outside the capture range
# to begin with.
# Do not use window capture (-i "title=") — see grab.ps1 comments; menu popups are missed.
#
# Pin the length with -t so ffmpeg ends itself. Killing it with Stop-Process
# can leave the container unclosed.

. "$PSScriptRoot\paths.ps1"
$dst = $FootageDir
New-Item -ItemType Directory -Path $dst -Force | Out-Null
$raw = Join-Path $dst 'chapter-01-editor-raw.mkv'

$LEAD = 3      # padding before operations start
$TAKE = 84     # take.ps1 measured 73.9s + pixel-sync waits + slack
$TAIL = 3      # padding after it ends
$DUR  = $LEAD + $TAKE + $TAIL

$args = @(
  "-y","-hide_banner","-loglevel","warning",
  "-f","gdigrab","-framerate","30","-draw_mouse","1",
  "-offset_x","3840","-offset_y","0","-video_size","3840x2160","-i","desktop",
  "-t","$DUR",
  "-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p",
  $raw
)
$ff = Start-Process -FilePath "ffmpeg" -ArgumentList $args -PassThru -NoNewWindow
Start-Sleep -Seconds $LEAD

Write-Output "Recording started (pid=$($ff.Id), $DUR s planned)"
$t0 = [Diagnostics.Stopwatch]::StartNew()

& "$PSScriptRoot\take.ps1" | Out-Null

Write-Output "Operations done: $([math]::Round($t0.Elapsed.TotalSeconds,1)) s — waiting for ffmpeg to finish"
$ff.WaitForExit(60000) | Out-Null
Start-Sleep -Seconds 1

if (Test-Path $raw) {
  $i = Get-Item $raw
  Write-Output "raw = $($i.FullName)  $([math]::Round($i.Length/1MB,1)) MB"
} else {
  Write-Output "FAIL: file is missing"
}

# Whether the recorded screen is correct is proven by the resulting project.godot.
# If any value is missing, the operations drifted, so discard this take.
$pg = Join-Path $TakeProj 'project.godot'
$want = @{
  'window/size/viewport_width'                      = '808'
  'window/size/viewport_height'                     = '360'
  'window/size/window_width_override'               = '1616'
  'window/size/window_height_override'              = '720'
  'window/stretch/mode'                             = '"canvas_items"'
  'window/stretch/aspect'                           = '"expand"'
  'window/handheld/orientation'                     = '4'
  'pointing/emulate_touch_from_mouse'               = 'true'
  'textures/canvas_textures/default_texture_filter' = '0'
}
$got = @{}
foreach ($line in Get-Content $pg) {
  $s = $line.Trim()
  if ($s -match '^[^;\[].*=' ) { $kv = $s -split '=', 2; $got[$kv[0].Trim()] = $kv[1].Trim() }
}
$bad = 0
foreach ($k in $want.Keys | Sort-Object) {
  $g = if ($got.ContainsKey($k)) { $got[$k] } else { '(missing)' }
  if ($g -ne $want[$k]) { $bad++; Write-Output ("  FAIL {0,-50} want={1,-16} got={2}" -f $k, $want[$k], $g) }
}
if ($bad -eq 0) { Write-Output "Verify: all 9 settings match — this take is valid" }
else            { Write-Output "Verify: $bad mismatches — discard this take and shoot again" }
