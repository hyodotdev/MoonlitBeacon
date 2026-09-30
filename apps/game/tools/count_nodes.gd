extends Node

## Count the arena's standing nodes per branch. A diagnostic for the late-game
## node budget (`test_late_game_performance`: at most 1200).
##
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")


func _count(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count(child)
	return total


func _ready() -> void:
	var arena: Node = ARENA.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	print("NODES total ", _count(arena))
	for child in arena.get_children():
		print("NODES   %-14s %d" % [child.name, _count(child)])
	var ui: Node = arena.get_node("Ui")
	for child in ui.get_children():
		print("NODES     Ui/%-16s %d" % [child.name, _count(child)])
	get_tree().quit(0)
