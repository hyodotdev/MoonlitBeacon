extends Node

## Measure how wide the right HUD row gets in its worst case, per locale.
##
## The panel pins a minimum width so it never jumps when digits change. That
## number has to cover the widest real content, so measure it instead of
## guessing: deep cycle (wave label shown), big level, six-digit kills, and the
## longest timer, in every shipped language.
##
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const HUD: PackedScene = preload("res://scenes/ui/hud.tscn")
const LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]


func _ready() -> void:
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud: Control = HUD.instantiate() as Control
	layer.add_child(hud)
	await get_tree().process_frame

	var panel: PanelContainer = hud.get_node("RightPanel") as PanelContainer
	# Unpin so the measurement is the content's own width, not the pin.
	panel.custom_minimum_size = Vector2(0, 26)
	var worst: float = 0.0
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		hud.call("set_cycle", 99)
		hud.call("set_beacons", 3, 3)
		hud.call("set_level", 999)
		hud.call("set_kills", 999999)
		hud.call("set_survived", 35999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var width: float = panel.get_combined_minimum_size().x
		worst = maxf(worst, width)
		print("MEASURE right HUD %-6s %6.1f" % [locale, width])
	print("MEASURE worst %.1f" % worst)
	get_tree().quit(0)
