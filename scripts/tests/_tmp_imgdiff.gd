extends SceneTree

func _initialize() -> void:
	var dir_a := "res://build/w3start_before/"
	var dir_b := "res://build/w3start/"
	for i in [3, 5, 10, 20]:
		var name := "f%08d.png" % i
		var a := Image.load_from_file(ProjectSettings.globalize_path(dir_a + name))
		var b := Image.load_from_file(ProjectSettings.globalize_path(dir_b + name))
		if a == null or b == null:
			print(name, " load failed")
			continue
		if a.get_size() != b.get_size():
			print(name, " size differs ", a.get_size(), " vs ", b.get_size())
			continue
		var diff := 0
		var min_x := 1 << 30
		var min_y := 1 << 30
		var max_x := -1
		var max_y := -1
		var max_delta := 0.0
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
				if d > 0.004:
					diff += 1
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
					max_delta = maxf(max_delta, d)
		print(name, " diff_px=", diff, " bbox=", Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if diff > 0 else Rect2i(), " max_delta=", snappedf(max_delta, 0.001))
	quit(0)
