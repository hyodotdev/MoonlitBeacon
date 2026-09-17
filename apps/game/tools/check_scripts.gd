extends Node

## Compile every GDScript under `res://scripts`.
##
## **`pnpm game:check` misses some of this.** That check opens the main scene
## and quits immediately, so scripts the title screen never reaches are
## **never even compiled.** Arena, spirits, and projectiles are parsed only
## when a run actually starts.
##
## This has bitten us more than once. Headless checks were green, then the
## device died on boot with `Identifier "Room" not declared` and
## `Identifier "heat" not declared`. Building, installing, and launching an
## APK takes five minutes, so each of those minutes found one parse error.
##
## Here every file is `load()`ed. For GDScript, load is compile, so syntax
## errors, undeclared identifiers, and type mismatches show up here.
##
## What this does **not** catch is also explicit. It only checks that
## compile succeeds — not whether a scene has the node, whether an
## `@onready` path is right, or whether signals connect. That still needs a
## real run.
##
## Run this as a **scene**, not `--script`. `--script` mode has no autoloads,
## so every script that uses `Records` · `Settings` would fail as
## "Identifier not found". Opening a scene loads autoloads normally.

const ROOTS: Array[String] = ["res://scripts", "res://tools"]


func _ready() -> void:
	var files: Array[String] = []
	for root in ROOTS:
		_collect(root, files)
	files.sort()

	var failed: int = 0
	for path in files:
		# If `load()` fails, the engine already prints a detailed error.
		# Add one more line here that names the file.
		# Even on a parse error ResourceLoader can return a non-empty GDScript.
		# Checking `can_instantiate()` too avoids a false green that prints
		# errors and still exits success.
		var script: Script = load(path) as Script
		if script == null or not script.can_instantiate():
			printerr("  compile failed: ", path)
			failed += 1

	if failed > 0:
		printerr(failed, " scripts did not compile")
		get_tree().quit(1)
		return

	print("confirmed compile of ", files.size(), " scripts")
	get_tree().quit(0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
