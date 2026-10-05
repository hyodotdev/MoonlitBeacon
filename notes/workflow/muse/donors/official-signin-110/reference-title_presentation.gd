	var providers := ["google", "apple", "guest"]
	for index in providers.size():
		var provider: String = providers[index]
		game._login_button(game.title_menu, 24.0 + index * 72.0, index, "LOGIN_" + provider.to_upper(), provider, Color.WHITE)
		var button: Button = game.title_menu.get_node("Login_" + provider)
		button.position.x = 28
		button.size = Vector2(428, 60)
		button.pivot_offset = button.size * 0.5
		button.add_theme_font_size_override("font_size", 22)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if provider == "guest": UI.button(button, game.ui_font, true)
		button.add_theme_font_size_override("font_size", 22)
