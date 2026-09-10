extends SceneTree

const Track = preload("res://scripts/face/face_track.gd")

func _initialize() -> void:
	var track := Track.new()
	var texture := load("res://assets/pets/character1.png") as Texture2D
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	track.frame_size = Vector2(image.get_width() / 4, image.get_height() / 9)
	track.provenance = "由 character1.png 浅色面部区域径向采样生成的默认12点轮廓；非人工精修。点0额头顶部，顺时针同序。"
	for frame: int in 33:
		var offset := Vector2i(frame % 4, frame / 4) * Vector2i(track.frame_size)
		# Head cream region is disconnected from the white ears by the brown outline.
		var origin := Vector2(148, 210)
		var points := PackedVector2Array()
		for i: int in 12:
			var direction := Vector2.from_angle(-PI * 0.5 + TAU * i / 12)
			var edge := origin
			for distance: int in range(1, 160):
				var point := origin + direction * distance
				var c := image.get_pixelv(offset + Vector2i(point))
				if c.a < 0.8 or c.r < 0.8 or c.g < 0.66 or c.b < 0.60:
					break
				edge = point
			points.append(edge)
		track.frames[frame] = points
	var error := track.validate()
	if not error.is_empty():
		printerr(error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://assets/pets/face_tracks")
	var result := ResourceSaver.save(track, "res://assets/pets/face_tracks/character1_walk.tres")
	print("BAKE 33 FRAMES: ", result)
	quit(result)
