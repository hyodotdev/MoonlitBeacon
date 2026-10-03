func _login_button(parent: Control, y: float, _atlas_index: int, text_value: String, provider: String, _text_color: Color) -> void:
	var button := Button.new()
	button.name = "Login_" + provider
	button.set_meta("provider", provider)
	button.position = Vector2(0, y)
	button.size = Vector2(360, 52)
	button.text = text_value
	button.pivot_offset = button.size * 0.5
	_brand_login_button(button, provider)
	button.pressed.connect(_request_login.bind(provider))
	parent.add_child(button)

func _brand_login_button(button: Button, provider: String) -> void:
	# Google and Apple require their official marks on equal-size controls.
	# Guest uses the same pill geometry so the row is one set.
	var fill := Color.WHITE
	var border := Color("#747775")
	var ink := Color("#1f1f1f")
	if provider == "apple":
		fill = Color("#000000")
		border = Color("#000000")
		ink = Color.WHITE
	elif provider == "guest":
		fill = Color("#f4efe6")
		border = Color("#c9b89a")
		ink = Color("#8b271e")
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill.lightened(0.04) if state in ["hover", "focus"] else fill
		if state == "pressed":
			box.bg_color = fill.darkened(0.08)
		box.border_color = border
		box.set_border_width_all(1)
		box.set_corner_radius_all(8)
		box.content_margin_left = 18
		box.content_margin_right = 18
		button.add_theme_stylebox_override(state, box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_constant_override("outline_size", 0)
	if provider == "google":
		button.icon = preload("res://assets/ui/generated/google_g.png")
	elif provider == "apple":
		button.icon = preload("res://assets/ui/generated/apple_logo.png")
	if provider != "guest":
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_constant_override("h_separation", 12)
