extends Control

## Credits.
##
## **This screen is not here because we wanted extra UI.** Galmuri and Noto's
## OFL and Godot's MIT require attribution. Ninja Adventure and Kenney are CC0
## so there is no duty, but they are listed anyway.
##
## Copy here must match the "credit-screen wording" in
## `apps/docs/docs/assets/third-party.md`. When assets grow, change both places.

signal closed

## Left column (translated) and right column (proper names, not translated).
##
## Person names and pack names stay as-is in every language. Translate
## `Pixel-Boy` and the author can no longer be found.
const ROWS: Array = [
	["CREDITS_ENGINE", "Godot Engine 4.7.1\nMIT License"],
	["CREDITS_ART", "Moonlit Beacon\nOriginal assets"],
	[
		"CREDITS_SOUND",
		"Ninja Adventure Asset Pack\nPixel-Boy and AAA · CC0\n"
		+ "Kenney UI Audio\nKenney · CC0",
	],
	[
		"CREDITS_FONT",
		# Nexon recommends attributing Maplestory. Put the copyright notice
		# the license asks for here.
		"Maplestory · ⓒ NEXON Korea\nNoto Sans CJK SC · Google\n"
		+ "SIL Open Font License 1.1",
	],
	["CREDITS_IAP", "godot-iap 3.5.1\nOpenIAP contributors · MIT License"],
	["CREDITS_MADE_BY", "Hyo Dev"],
]

@onready var _roles: Label = $Roles
@onready var _names: Label = $Names


func _ready() -> void:
	$Back.pressed.connect(close)
	_redraw()


## The engine sends this notification to every `Control` when the language changes.
##
## Labels whose text lives in the scene redraw themselves. **Code-filled** spots
## like this must listen and redraw. Skip that and the old language stays until
## the settings window is closed and reopened.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_redraw()


func _redraw() -> void:
	if _roles == null:
		return                                   # not in the tree yet
	var roles: PackedStringArray = []
	var names: PackedStringArray = []
	for row in ROWS:
		var value: String = str(row[1])
		roles.append(tr(str(row[0])))
		names.append(value)
		# If the name is two lines, pad the left column to keep the rows aligned.
		for i in value.count("\n"):
			roles.append("")
	var store: Node = get_node_or_null("/root/IapStore")
	if store != null and store.owns(store.SUPPORTER):
		var supporter_name: String = str(Ladder.last_name).strip_edges()
		if supporter_name.is_empty():
			supporter_name = tr("LADDER_ANON")
		roles.append(tr("CREDITS_SUPPORTER"))
		names.append("★ " + supporter_name)
	_roles.text = "\n".join(roles)
	_names.text = "\n".join(names)


func open() -> void:
	_redraw()
	visible = true
	$Back.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
