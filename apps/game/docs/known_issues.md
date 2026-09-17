# Known limits

## Quitting while recording with Movie Maker (`--write-movie`) reports Ogg leaks

### Symptom

```
WARNING: 4 ObjectDB instances were leaked at exit
ERROR: 2 resources still in use at exit
```

With `--verbose`, the leak targets are exactly these four.

```
Leaked instance: OggPacketSequence            - Reference count: 3
Leaked instance: AudioStreamOggVorbis         - Reference count: 1
Leaked instance: AudioStreamPlaybackOggVorbis - Reference count: 1
Leaked instance: OggPacketSequencePlayback    - Reference count: 1
Resource still in use: .../title_theme.ogg::OggPacketSequence_eguve (OggPacketSequence)
Resource still in use: .../title_theme.ogg (AudioStreamOggVorbis)
```

### Cause

`AudioStreamPlayer` stops itself when it leaves the tree. That `stop()` only
marks the node in the AudioServer playback list as "to be deleted." Actual
release happens when the audio thread runs the next mix. Scene shutdown starts
engine cleanup immediately, so cleanup begins before that mix, and references
held by playback nodes remain.

In a normal run the audio thread is separate, so a short wait after stop lets
the thread finish cleanup. `_exit_tree()` in `scripts/ui/title_menu.gd` adds
that wait, and windowed mode plus `--headless` exit cleanly with it.

Movie Maker mode has no audio thread. For each drawn frame, `MovieWriter`
mixes that frame's audio itself. After the last frame is drawn, no mix runs
again. Game code cannot fix this.

### Evidence (Godot 4.7.1-stable, a13da4feb)

| Run | Result |
| --- | --- |
| `--quit-after 20 / 60 / 120 / 300` (windowed) | 0 errors |
| `--headless --quit-after 20 / 60 / 120 / 300` | 0 errors |
| `--write-movie ... --quit-after 120` | leak reported |
| `--write-movie ... --quit-after 120`, exit wait stretched to 1500ms | leak **still** reported |
| `--write-movie ... --quit-after 150`, BGM stopped at 1.5s while frames remain | 0 errors |

The last two rows are the point. Holding the main thread longer does nothing;
stopping while frames remain is clean. The condition is not "wait time" but
"does a mix run once more after stop."

### Scope

This log appears only from the recording convenience path. Device (Android),
desktop, and automated `--headless` all exit cleanly. If these two lines show
up in a video-capture log, ignore them.
