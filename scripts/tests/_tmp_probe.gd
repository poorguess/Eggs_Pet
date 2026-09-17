extends SceneTree

func _initialize() -> void:
	var f: Font = ThemeDB.fallback_font
	print("font=", f)
	for s in [96, 56, 46, 30, 24]:
		print("  size=", s, " ascent=", f.get_ascent(s), " descent=", f.get_descent(s), " height=", f.get_height(s))
	var tex: Texture2D = load("res://assets/eggs_pics/Newegg.png")
	print("Newegg size=", tex.get_size(), " *0.28=", tex.get_size() * 0.28)
	print("theme font=", (load("res://ui/theme.tres") as Theme).default_font)
	print("save exists=", FileAccess.file_exists("user://egg_pet_save.json"))
	quit(0)
