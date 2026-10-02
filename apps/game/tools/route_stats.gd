extends SceneTree

## How often each place is offered across many seeds and cycles: a quick look at the route draw for
## uneven weighting. Diagnostic only; lives in `tools/`, which `_runtime_fingerprint()` excludes.

func _init() -> void:
	var starts: Dictionary = {}
	var options: Dictionary = {}
	var runs: int = 400
	for run_seed in runs:
		var previous: int = 0
		for cycle in range(3, 15):
			var start: int = Expedition.start_terrain(run_seed, cycle, previous)
			starts[start] = int(starts.get(start, 0)) + 1
			var route: Array[int] = [start, -1, -1]
			for zone in 2:
				var offered: Array[int] = Expedition.gate_options(run_seed, cycle, zone, route)
				for option in offered:
					options[option] = int(options.get(option, 0)) + 1
				route[zone + 1] = offered[run_seed % 2]
			previous = route[2]
	var names: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
	print("ROUTE opening place, share of cycles 3-14:")
	var total_starts: int = 0
	for key in starts:
		total_starts += int(starts[key])
	for index in names.size():
		print("ROUTE   %-7s %5.1f%%" % [names[index], 100.0 * float(int(starts.get(index, 0))) / float(total_starts)])
	var total_options: int = 0
	for key in options:
		total_options += int(options[key])
	print("ROUTE gate offers, share:")
	for index in names.size():
		print("ROUTE   %-7s %5.1f%%" % [names[index], 100.0 * float(int(options.get(index, 0))) / float(total_options)])
	quit(0)
