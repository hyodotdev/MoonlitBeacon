extends RefCounted

## One composed `extension_list.cfg` for iOS exports.
##
## Every GDExtension in the game must be named in the exported
## `res://.godot/extension_list.cfg`, or the exported game never loads it.
## Each export plugin stages its own descriptor, but the list itself is a
## single file: if two plugins each write only their own entry, the last
## writer silently drops the other extension.
##
## Both export plugins (godot-iap and MoonlitIdentity) therefore write this
## composed union instead of their own entry. Composition reads the
## on-disk descriptor sources, so every writer produces the same complete
## list no matter which plugin's `_export_begin` runs first, and a missing
## descriptor is omitted exactly as its own plugin's warning path does.

const EXTENSION_LIST_PATH: String = "res://.godot/extension_list.cfg"

const KNOWN_DESCRIPTORS: Array = [
	{
		"source": "res://addons/godot-iap/bin/godot_iap.gdextension.ios",
		"export": "res://addons/godot-iap/bin/godot_iap.gdextension",
	},
	{
		"source": "res://addons/moonlit-identity/ios/moonlit_identity.gdextension.ios",
		"export": "res://addons/moonlit-identity/bin/moonlit_identity.gdextension",
	},
]


static func extension_list_path() -> String:
	return EXTENSION_LIST_PATH


static func compose() -> String:
	var lines: Array[String] = []
	for entry in KNOWN_DESCRIPTORS:
		var source: String = str((entry as Dictionary).get("source", ""))
		var export: String = str((entry as Dictionary).get("export", ""))
		if source.is_empty() or export.is_empty():
			continue
		if FileAccess.file_exists(source):
			lines.append(export)
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"
