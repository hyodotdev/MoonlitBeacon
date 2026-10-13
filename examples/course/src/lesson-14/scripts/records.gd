## Best score on this device. An autoload so every scene reads one holder.
## No class_name on purpose: the autoload singleton already owns the name.
extends Node

const SAVE_PATH: String = "user://records.cfg"
const SECTION: String = "records"

var best_score: int = 0


func _ready() -> void:
	load_best()


func load_best() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = int(cfg.get_value(SECTION, "best_score", 0))


func save_best(score: int) -> bool:
	if score <= best_score:
		return false
	best_score = score
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "best_score", best_score)
	if cfg.save(SAVE_PATH) != OK:
		push_error("records cannot save " + SAVE_PATH)
		return false
	return true
