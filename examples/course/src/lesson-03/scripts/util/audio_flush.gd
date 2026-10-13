## Shared audio shutdown for positional and non-positional players alike.
##
## Stopping a player only marks its playback "to be removed" inside the audio
## server; the real free happens on the audio thread's next mix. When a scene
## with playing audio leaves the tree (a transition) or the process quits, the
## scene script stops its players and then waits out one mix here, so nothing
## leaks and transitions never stall on a wait they do not need.
class_name AudioFlush
extends RefCounted

## Headroom over the longest mix period measured (120ms headless).
const MIX_WAIT_MSEC: int = 150


static func stop_player(player: Node) -> void:
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stop()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stop()


static func is_playing(player: Node) -> bool:
	if player is AudioStreamPlayer:
		return (player as AudioStreamPlayer).playing
	if player is AudioStreamPlayer2D:
		return (player as AudioStreamPlayer2D).playing
	return false


static func wait_for_mix() -> void:
	OS.delay_msec(MIX_WAIT_MSEC)


static func loop_stream(player: AudioStreamPlayer) -> void:
	## Imported music defaults to play-once; the import flag lives in editor
	## caches, so the checkpoint enables the loop in code instead. Full
	## stream, from the first sample, until the player stops.
	var stream: AudioStreamOggVorbis = player.stream as AudioStreamOggVorbis
	if stream != null:
		stream.loop = true
