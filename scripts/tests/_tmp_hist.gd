extends SceneTree

func _initialize() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start_before/f00000005.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start/f00000005.png"))
	var regions := {
		"title": Rect2i(0, 100, 540, 115),
		"egg": Rect2i(0, 400, 540, 158),
		"shadow": Rect2i(0, 558, 540, 22),
		"prompt+buttons": Rect2i(0, 850, 540, 60),
		"footer": Rect2i(0, 915, 540, 40),
	}
	for name: String in regions:
		var region: Rect2i = regions[name]
		var n02 := 0
		var n10 := 0
		var n50 := 0
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
				if d > 0.02:
					n02 += 1
				if d > 0.1:
					n10 += 1
				if d > 0.5:
					n50 += 1
		print("%-16s total=%d  d>0.02=%d  d>0.1=%d  d>0.5=%d" % [name, region.size.x * region.size.y, n02, n10, n50])
	quit(0)
