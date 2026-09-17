extends Node

## Capture the hero detail screen at the real resolution (808×360). For inspection.
##
## This screen shows pixel art in two places — a small portrait in the header
## and a large body in the center. If either scale drifts from the source, it
## smears only there. That is hard to measure by eye, so take one shot and
## fix from it. Output lands under builds/, so it is not committed.

const PANEL: PackedScene = preload("res://scenes/ui/hero_preview_panel.tscn")
const HEROES: Array[String] = [
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/warden.tres",
]


func _ready() -> void:
	TranslationServer.set_locale("ko")
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var out: String = ProjectSettings.globalize_path("res://../../builds/shots")
	DirAccess.make_dir_recursive_absolute(out)

	for index in HEROES.size():
		var layer := CanvasLayer.new()
		add_child(layer)
		var panel: Control = PANEL.instantiate() as Control
		layer.add_child(panel)
		var hero: Hero = load(HEROES[index]) as Hero
		panel.open_hero(hero, HEROES[index])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		shot.save_png("%s/hero_panel_%d.png" % [out, index])
		layer.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)
