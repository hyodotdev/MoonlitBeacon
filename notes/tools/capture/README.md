# Screen-capture tools

PowerShell tools that drive the Godot editor automatically and record that
screen. The Lesson 1 §3 clip (`chapter-01-editor.mp4`) was shot with this.

Background and traps are in [`/record`](../../../.claude/commands/record.md)
and the [recording pipeline](../../workflow/recording.md). **Read those first.**

## Files

| File | Role |
| --- | --- |
| `drive.ps1` | Window focus · mouse · keyboard · pixel checks. Lowest layer |
| `lib.ps1` | Image coords ↔ screen coords, probe-color constants |
| `grab.ps1` | Grabs one frame of the right monitor (for finding coords) |
| `reset.ps1` | Makes an empty capture project and opens the editor |
| `take.ps1` | Operation sequence. **Rewrite this file per clip** |
| `record.ps1` | Starts ffmpeg, runs `take.ps1`, then verifies the result |

## Sequence

Paths walk up from the script location to the repo root (`paths.ps1`).
It runs no matter where the repo is cloned. The Godot binary is found as
`GODOT_BIN` → PATH → winget install location, so it does not need to be on
PATH in advance.

```powershell
# From the repo root

# 1. Back up editor settings, then switch them for capture (see record.md)
# 2. Initialize the capture project + launch the editor
notes\tools\capture\reset.ps1

# 3. Find coordinates — grab one frame, read it, click, grab again
notes\tools\capture\grab.ps1 shot.png

# 4. Write the operation sequence in take.ps1

# 5. Rehearse without recording
notes\tools\capture\reset.ps1 ; notes\tools\capture\take.ps1

# 6. Confirm the resulting project.godot matches apps/game/project.godot

# 7. The real recording
notes\tools\capture\reset.ps1 ; notes\tools\capture\record.ps1

# 8. Restore editor settings
```

## Must keep

- **Shoot on the right monitor only.** A fullscreen game on the left steals
  the cursor.
- **`.ps1` files must have a BOM.** PowerShell 5.1 reads as ANSI and the
  parser dies on Hangul comments.
- **`project.godot` must not have a BOM.** Godot reads it as part of the key
  name.
- **Coordinates are relative to the 1280-wide image `grab.ps1` produces.**
  Screen coords = `3840 + x*3`, `y*3`.
- **Do not chase UI with fixed waits.** Check pixels with `IWait` and then
  continue.
- After capture, `builds/take/` can be deleted. It is gitignored.

## When shooting another clip

Rewrite only `take.ps1`. Reuse everything else.
Coordinates change when the editor layout changes, so **remeasure with
`grab.ps1` every time.**
