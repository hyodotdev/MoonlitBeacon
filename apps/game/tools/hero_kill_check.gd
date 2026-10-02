extends Node

## Do all six heroes kill the same things at the same pace when they stand still? Each hero faces the same
## spirits for the same seconds, invulnerable and motionless, and the kills are counted. A diagnostic; it
## lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const HERO_IDS: Array[String] = ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_physics_steps_per_frame = 32
	var seconds: float = 40.0
	for id in HERO_IDS:
		seed(77)
		var request: FileAccess = FileAccess.open("user://test_hero.request", FileAccess.WRITE)
		request.store_string("res://resources/heroes/%s.tres" % id)
		request.close()
		RunEntry.mark_from_title()
		var arena: Node2D = ARENA.instantiate() as Node2D
		add_child(arena)
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().paused = false
		(arena.get("_relic") as Control).visible = false
		arena.call("debug_shield")
		var dialogue: Control = arena.get("_dialogue") as Control
		if dialogue != null and bool(dialogue.call("is_open")):
			dialogue.call("_close")
		Engine.time_scale = 3.0
		var elapsed: float = 0.0
		var kills_at: Dictionary = {}
		while elapsed < seconds:
			await get_tree().physics_frame
			elapsed += 1.0 / 60.0
			for mark in [10.0, 20.0, 30.0, 40.0]:
				if elapsed >= mark and not kills_at.has(mark):
					kills_at[mark] = int(arena.get("_kills"))
			if bool(arena.get("_over")):
				break
			var relic: Control = arena.get("_relic") as Control
			if relic != null and relic.visible:
				relic.set("_choice_armed", true)
				relic.call("_on_card_pressed", 0)
		Engine.time_scale = 1.0
		print("HEROKILL %-8s kills at 10/20/30/40 s: %s   level %d" % [id, str(kills_at), int(arena.get("_level"))])
		arena.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(0)
