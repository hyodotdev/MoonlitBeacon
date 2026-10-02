extends Node

## Photograph the combat HUD at the real resolution (808x360), twice.
##
## Shot 0 is the moment a value changes — every line at full brightness, which
## is what the old HUD looked like *all the time*. Shot 1 is a few seconds
## later, once the secondary lines have settled to rest. The pair is the whole
## point of the change, and neither frame can be judged from a diff.
##
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const HUD: PackedScene = preload("res://scenes/ui/hud.tscn")


func _ready() -> void:
	TranslationServer.set_locale("ko")
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var out: String = ProjectSettings.globalize_path("res://../../builds/shots/hud")
	DirAccess.make_dir_recursive_absolute(out)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud: Control = HUD.instantiate() as Control
	layer.add_child(hud)

	# A believable mid-run state: hurt, mid-cycle, carrying a build.
	hud.set_max_health(6)
	hud.set_health(4)
	hud.set_beacons(2, 3)
	hud.set_level(20)
	hud.set_kills(37)
	hud.set_survived(184.0)
	hud.set_world("WORLD_CAMP", "TIME_NIGHT")
	hud.set_moonfire(0.6, false, false)
	hud.set_evolution(Relic.Family.FULL_MOON, 3, 0, 6)
	hud.set_missile_power(8, 8, 2, 2, false)
	hud.set_missile_recovery(4.0, Vector2.RIGHT, true)

	for _wait in 4:
		await RenderingServer.frame_post_draw
	var loud: Image = get_viewport().get_texture().get_image()
	loud.save_png("%s/hud_on_change.png" % out)

	# Past QUIET_HOLD_SECONDS plus the fade. Nothing changes in between, so the
	# secondary lines fall back on their own. The count is generous because this
	# window is not vsync-throttled — 260 frames turned out to be 2.1s, which
	# landed on the first frame of the fade rather than after it.
	for _wait in 420:
		await RenderingServer.frame_post_draw
	var calm: Image = get_viewport().get_texture().get_image()
	calm.save_png("%s/hud_at_rest.png" % out)

	get_tree().quit(0)
