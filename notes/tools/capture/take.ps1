# Lesson 1 §3 capture — every project setting in the Godot editor.
#
# Reproduces lesson script 03:00 ~ 07:10 (3-1 ~ 3-6) as editor operations.
# Coordinates are relative to "an image of the right monitor grabbed at 1280 wide". See lib.ps1.
#
# This is a state-dependent script. Run it only immediately after reset.ps1.
# Restarting from the middle changes scroll position and every coordinate drifts.

. "$PSScriptRoot\lib.ps1"

$BEAT = 900      # breath between actions
$READ = 1600     # hold so the changed value is visible
$SECT = 2000     # larger breath when a section changes

$h = Ready-Win
Start-Sleep -Milliseconds 2200                 # lead-in padding

# ── 3-1. Project ▸ Project Settings ──────────────────────────────────────
IClick 70 34 $BEAT
Start-Sleep -Milliseconds 800                  # time to read the menu item
IClick 110 57 600

# Wait until the dialog is actually drawn. Skipping with a fixed wait sends the
# next click into empty air when load spikes (an 82-second failed take was recorded that way).
Assert-Or-Die (IWait 450 178 $C_DLG_BG 10000) "Project Settings dialog did not open"
Start-Sleep -Milliseconds 1200

# ── 3-2. Advanced Settings must be on before hidden items appear ─────────
IMove 1008 178
Start-Sleep -Milliseconds 900                  # one beat over the toggle
IClick 1008 178 600
Assert-Or-Die (IWait 1008 178 $C_TOGGLE_ON 6000) "Advanced Settings toggle did not turn on"
Start-Sleep -Milliseconds 1200
IClick 293 351 $SECT                           # Display ▸ Window

# ── 3-3. Internal resolution 808 x 360 ───────────────────────────────────
IDbl 860 250 450
Key "^a" 150
Type-Text "808" 95                             # show each character being typed
Key "{ENTER}" $READ

IDbl 860 272 450
Key "^a" 150
Type-Text "360" 95
Key "{ENTER}" $READ
Start-Sleep -Milliseconds 1000                 # let 808 x 360 land in the eye

# ── 3-4. Desktop test window size (integer 2x) ───────────────────────────
IScroll 700 400 -5
Start-Sleep -Milliseconds 600
IDbl 860 400 450
Key "^a" 150
Type-Text "1616" 95
Key "{ENTER}" $READ

IDbl 860 423 450
Key "^a" 150
Type-Text "720" 95
Key "{ENTER}" $READ
Start-Sleep -Milliseconds 1000

# ── 3-5. Stretch — mode canvas_items, aspect expand ──────────────────────
IScroll 700 400 -10
Start-Sleep -Milliseconds 800

IClick 858 242 $BEAT                           # Mode dropdown
Start-Sleep -Milliseconds 1300                 # show disabled / canvas_items / viewport
IClick 765 284 $READ                           # canvas_items

IClick 858 264 $BEAT                           # Aspect dropdown
Start-Sleep -Milliseconds 1600                 # show that keep is the default
IClick 749 355 $READ                           # expand
Start-Sleep -Milliseconds 900

# ── 3-6. Landscape lock — Sensor Landscape ───────────────────────────────
IClick 858 427 $BEAT                           # Handheld ▸ Orientation
Start-Sleep -Milliseconds 1500                 # show both Landscape and Sensor Landscape
IClick 778 518 $READ                           # Sensor Landscape
Start-Sleep -Milliseconds 1000

# ── 3-7. Pixel-art filter — Nearest ──────────────────────────────────────
IScroll 310 400 -12                            # roll the left category tree
Start-Sleep -Milliseconds 700
IClick 294 326 $SECT                           # Rendering ▸ Textures
IClick 858 250 $BEAT                           # Default Texture Filter dropdown
Start-Sleep -Milliseconds 1300                 # show Nearest / Linear side by side
IClick 751 276 $READ                           # Nearest
Start-Sleep -Milliseconds 1000

# ── 3-8. Emulate touch from the mouse ────────────────────────────────────
IScroll 310 400 -8
Start-Sleep -Milliseconds 700
IClick 293 503 $SECT                           # Input Devices ▸ Pointing
IMove 713 362
Start-Sleep -Milliseconds 800
IClick 713 362 $READ                           # Emulate Touch From Mouse check
Start-Sleep -Milliseconds 1200

# ── Close ────────────────────────────────────────────────────────────────
IClick 639 582 $SECT                           # Close
Start-Sleep -Milliseconds 1800                 # trailing padding

Write-Output "take complete"
