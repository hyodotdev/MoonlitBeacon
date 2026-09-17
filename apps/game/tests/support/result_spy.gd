extends Control

## Result panel stand-in for inspecting the Arena result route.
## Observes only the return-to-result call after the ladder panel closes.

var reopen_calls: int = 0
var persistence_refresh_calls: int = 0
var last_persistence_best: bool = false
var last_persistence_shards: int = 0


func reopen_after_failed_continue() -> void:
	visible = true
	reopen_calls += 1


func refresh_persistence(is_best: bool, run_shards: int) -> void:
	persistence_refresh_calls += 1
	last_persistence_best = is_best
	last_persistence_shards = run_shards
