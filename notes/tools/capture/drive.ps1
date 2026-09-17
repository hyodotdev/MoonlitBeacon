# Godot editor operation driver.
#
# The cause of the previous two capture failures was "Godot ignores mouse
# input on a window that does not have focus."
# So every operation must call Focus-Win first.
#
# This PC is 4K at 200% scale. If SetProcessDPIAware is not called,
# SetCursorPos is interpreted as logical coords (1920x1080) and the actual
# click lands at half the point. Call it first.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  // dwData uses negatives (down) for the wheel. Receiving as uint blows up on -120 at the cast.
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@

[void][W]::SetProcessDPIAware()

$script:MOUSEEVENTF_LEFTDOWN  = 0x0002
$script:MOUSEEVENTF_LEFTUP    = 0x0004
$script:MOUSEEVENTF_WHEEL     = 0x0800

function Get-GodotWin {
  $p = Get-Process -Name "Godot*" -ErrorAction SilentlyContinue |
       Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "Could not find the Godot window" }
  return $p.MainWindowHandle
}

# SetForegroundWindow fails silently if the calling thread is not in the foreground.
# Attach briefly to the target window's input queue and take it by force.
function Focus-Win([IntPtr]$h) {
  $fg = [W]::GetForegroundWindow()
  if ($fg -eq $h) { return $true }
  # A short ALT down/up releases the foreground lock. Without this,
  # SetForegroundWindow returns true and the window still does not come forward.
  [W]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
  [W]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  $me  = [W]::GetCurrentThreadId()
  $tgt = [W]::GetWindowThreadProcessId($h, [IntPtr]::Zero)
  [void][W]::AttachThreadInput($me, $tgt, $true)
  [void][W]::BringWindowToTop($h)
  [void][W]::SetForegroundWindow($h)
  [void][W]::SetActiveWindow($h)
  [void][W]::AttachThreadInput($me, $tgt, $false)
  Start-Sleep -Milliseconds 150
  return ([W]::GetForegroundWindow() -eq $h)
}

function Get-Rect([IntPtr]$h) {
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($h, [ref]$r)
  return [pscustomobject]@{ X=$r.L; Y=$r.T; W=($r.R-$r.L); H=($r.B-$r.T) }
}

# MoveWindow does not work on a maximized window. Restore first.
function Set-Rect([IntPtr]$h, $x, $y, $w, $t) {
  if ([W]::IsZoomed($h)) {
    [void][W]::ShowWindow($h, 9)   # SW_RESTORE
    Start-Sleep -Milliseconds 600
  }
  [void][W]::MoveWindow($h, $x, $y, $w, $t, $true)
  Start-Sleep -Milliseconds 400
}

# Move the cursor in several steps, as a person would.
# Instant jumps make it impossible to follow the mouse in the video.
function Move-To($x, $y, $steps = 18, $ms = 12) {
  $pos = [System.Windows.Forms.Cursor]::Position
  $sx = $pos.X; $sy = $pos.Y
  for ($i = 1; $i -le $steps; $i++) {
    $t = $i / $steps
    $e = if ($t -lt 0.5) { 2*$t*$t } else { 1 - [Math]::Pow(-2*$t + 2, 2)/2 }   # ease-in-out
    [void][W]::SetCursorPos([int]($sx + ($x-$sx)*$e), [int]($sy + ($y-$sy)*$e))
    Start-Sleep -Milliseconds $ms
  }
  [void][W]::SetCursorPos($x, $y)
}

function Click-At($x, $y, $pause = 260) {
  Move-To $x $y
  Start-Sleep -Milliseconds 120
  [W]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 45
  [W]::mouse_event($MOUSEEVENTF_LEFTUP, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $pause
}

function DblClick-At($x, $y, $pause = 260) {
  Move-To $x $y
  Start-Sleep -Milliseconds 120
  foreach ($i in 1..2) {
    [W]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [W]::mouse_event($MOUSEEVENTF_LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 55
  }
  Start-Sleep -Milliseconds $pause
}

function Scroll-At($x, $y, $clicks) {
  Move-To $x $y
  Start-Sleep -Milliseconds 100
  foreach ($i in 1..([Math]::Abs($clicks))) {
    [W]::mouse_event($MOUSEEVENTF_WHEEL, 0, 0, (120 * [Math]::Sign($clicks)), [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
  }
  Start-Sleep -Milliseconds 200
}

function Escape-Key([char]$c) {
  # SendKeys reserved characters must be wrapped in braces to enter as literals.
  if ('+^%~(){}[]'.IndexOf($c) -ge 0) { return "{$c}" }
  return [string]$c
}

# Send one character at a time. Dumping all at once makes Godot's LineEdit drop the first letters.
function Type-Text($text, $ms = 45) {
  foreach ($c in $text.ToCharArray()) {
    [System.Windows.Forms.SendKeys]::SendWait((Escape-Key $c))
    Start-Sleep -Milliseconds $ms
  }
}

function Key($k, $pause = 200) {
  [System.Windows.Forms.SendKeys]::SendWait($k)
  Start-Sleep -Milliseconds $pause
}

# ── Screen-state sync ──────────────────────────────────────────────────────
#
# Chasing UI with only a fixed wait (Start-Sleep) fails. This actually happened:
# while ffmpeg encoded 4K30, CPU stalled, the Project Settings dialog opened late,
# the Advanced Settings toggle click sent in between hit empty air,
# and 82 seconds were recorded with every later coordinate wrong.
#
# So confirm "it was drawn" with a pixel, then move to the next action.

function Get-PixelAt($x, $y) {
  $bmp = New-Object System.Drawing.Bitmap 1, 1
  $g   = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size 1, 1))
  $c = $bmp.GetPixel(0, 0)
  $g.Dispose(); $bmp.Dispose()
  return @($c.R, $c.G, $c.B)
}

function Near-Color($got, $want, $tol = 26) {
  for ($i = 0; $i -lt 3; $i++) {
    if ([Math]::Abs($got[$i] - $want[$i]) -gt $tol) { return $false }
  }
  return $true
}

# Wait until the given point is the expected color. $false if the timeout elapses.
function Wait-Color($x, $y, $want, $timeoutMs = 8000, $tol = 26) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    if (Near-Color (Get-PixelAt $x $y) $want $tol) { return $true }
    Start-Sleep -Milliseconds 120
  }
  return $false
}

# Grab one window frame with ffmpeg and save it. Used when finding coordinates.
function Grab($path, $width = 1600) {
  ffmpeg -y -hide_banner -loglevel error -f gdigrab -framerate 2 `
    -i "title=$script:GodotTitle" -frames:v 1 -vf "scale=${width}:-2" $path | Out-Null
  return (Test-Path $path)
}
