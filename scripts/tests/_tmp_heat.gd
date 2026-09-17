extends SceneTree

func _initialize() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start_before/f00000005.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start/f00000005.png"))
	var region := Rect2i(170, 395, 200, 170)
	var out := Image.create(region.size.x, region.size.y, false, Image.FORMAT_RGB8)
	var rows := {}
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			out.set_pixel(x - region.position.x, y - region.position.y, Color(d * 4.0, d * 4.0, d * 4.0, 1.0))
			if d > 0.5:
				rows[y] = rows.get(y, 0) + 1
	out.resize(region.size.x * 3, region.size.y * 3, Image.INTERPOLATE_NEAREST)
	out.save_png(ProjectSettings.globalize_path("res://build/cmp_egg_heat.png"))
	print("wrote heat map; rows with d>0.5:")
	var keys := rows.keys()
	keys.sort()
	for y: int in keys:
		print("  row ", y, " -> ", rows[y])
	quit(0)
