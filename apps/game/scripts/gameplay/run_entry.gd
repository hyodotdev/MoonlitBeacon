class_name RunEntry
extends RefCounted

## Tells the arena whether this run is **real play that started from the title**.
##
## The arena also comes up through other paths — regression tests `instantiate()`
## it, the store capture harness launches it to build a specific shot, and hero
## facing capture `add_child()`s it on `get_tree().root` then even sets
## `current_scene` to the arena.
##
## The story dialogue that opens a run pauses `get_tree()`. If that pause hits
## the paths above, combat simulation drifts and capture frames change. Guessing
## from the tree shape failed twice — looking only at `current_scene`, then at
## parents too, both still let hero facing capture through. Instead of inferring
## shape, **the caller says so itself**.
##
## Consumed once. Leaving a run and coming back, the title turns it on again.

static var from_title: bool = false


## Call just before leaving the title for the arena.
static func mark_from_title() -> void:
	from_title = true


## Arena calls this once when opening a run. If it was on, turn it off and return `true`.
static func consume_from_title() -> bool:
	if not from_title:
		return false
	from_title = false
	return true
