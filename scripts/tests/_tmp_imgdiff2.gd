extends SceneTree

func _initialize() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start_before/f00000005.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start/f00000005.png"))
	var rows := {}
	var big := 0
	var big_box := Rect2i(1 << 30, 1 << 30, 0, 0)
	var min_bx := 1 << 30
	var min_by := 1 << 30
	var max_bx := -1
	var max_by := -1
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			if d > 0.02:
				rows[y] = rows.get(y, 0) + 1
			if d > 0.5:
				big += 1
				min_bx = mini(min_bx, x)
				min_by = mini(min_by, y)
				max_bx = maxi(max_bx, x)
				max_by = maxi(max_by, y)
	print("pixels with delta>0.5: ", big, " bbox=", Rect2i(min_bx, min_by, max_bx - min_bx + 1, max_by - min_by + 1))
	var keys := rows.keys()
	keys.sort()
	for y: int in keys:
		if rows[y] > 3:
			print("  row ", y, " -> ", rows[y], " px")
	quit(0)
