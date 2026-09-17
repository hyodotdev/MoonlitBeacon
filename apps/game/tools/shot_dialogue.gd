extends Node

## Capture one dialogue shot at the real resolution (808×360). For inspection.
##
## Dialogue and layout have to be fixable without running eight cycles just
## to see how this screen looks. Output lands under builds/, so it is not
## committed.

const DIALOGUE: PackedScene = preload("res://scenes/ui/dialogue_scene.tscn")
const HEROES: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/keeper.tres",
]
const LINES: Array[String] = ["STORY_CYCLE_1_A", "STORY_CYCLE_8_B"]


func _ready() -> void:
	# Headless defaults to en. Inspection should use the Korean players actually read.
	TranslationServer.set_locale("ko")
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var out: String = "res://../../builds/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	for index in HEROES.size():
		var layer := CanvasLayer.new()
		add_child(layer)
		var scene: Control = DIALOGUE.instantiate() as Control
		layer.add_child(scene)
		var hero: Hero = load(HEROES[index]) as Hero
		scene.play(hero, [tr(LINES[index])] as Array[String])
		# Look at the fully typed state.
		scene.call("_advance")
		# Opening fades in over 0.18s. Capture after it has fully appeared.
		for _wait in 24:
			await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		shot.save_png("%s/dialogue_%d.png" % [
			ProjectSettings.globalize_path(out), index])
		layer.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)
