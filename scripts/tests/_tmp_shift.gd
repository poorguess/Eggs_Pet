extends SceneTree

func _diff_count(a: Image, b: Image, region: Rect2i, dx: int, dy: int) -> int:
	var n := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var ax := x + dx
			var ay := y + dy
			if ax < 0 or ay < 0 or ax >= a.get_width() or ay >= a.get_height():
				continue
			var ca := a.get_pixel(ax, ay)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.02:
				n += 1
	return n


func _initialize() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start_before/f00000005.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://build/w3start/f00000005.png"))
	var regions := {
		"title": Rect2i(174, 100, 200, 115),
		"egg": Rect2i(174, 400, 200, 170),
		"shadow": Rect2i(180, 556, 190, 28),
		"buttons": Rect2i(100, 850, 350, 65),
		"footer": Rect2i(180, 920, 190, 30),
	}
	for name: String in regions:
		var region: Rect2i = regions[name]
		var best := ""
		var best_n := 1 << 30
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var n := _diff_count(a, b, region, dx, dy)
				if n < best_n:
					best_n = n
					best = "dx=%d dy=%d" % [dx, dy]
		print(name, " best=", best, " diff=", best_n, " (dx=0,dy=0 -> ", _diff_count(a, b, region, 0, 0), ")")
	quit(0)
