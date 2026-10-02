extends Node

## Count the standing nodes of each place's room. A diagnostic for the late-game node budget
## (`test_late_game_performance`: at most 1200): the classic forest is the heaviest room the budget
## was measured on, so no other place may cost more than it does.
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
	var room: Room = arena.get("_room") as Room
	for terrain in Expedition.TERRAINS:
		var kind: RoomKind = load(str(terrain["room"])) as RoomKind
		room.build(kind, 730_421)
		await get_tree().process_frame
		print("ROOM %-8s %4d nodes  (%d structures)" % [
			terrain["id"], _count(room), room.terrain_obstacle_count()])
	get_tree().quit(0)
