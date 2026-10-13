## Compile-only probe for course practice outputs.
## Loads every project script so a parse or type error in a file the title
## never reaches still fails verification. Runs as a scene so engine
## autoloads resolve; never shipped.
extends Node


func _ready() -> void:
	var files: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			files.append(arg.get_slice("=", 1))
	var passed: int = 0
	var failed: Array[String] = []
	for path in files:
		var loaded: Resource = load(path)
		if loaded == null:
			failed.append(path)
			push_error("compile_probe cannot load " + path)
		else:
			passed += 1
	print("COMPILE RESULT pass=", passed, " fail=", failed.size())
	for path in failed:
		print("COMPILE FAIL ", path)
	get_tree().quit(1 if failed.size() > 0 else 0)
