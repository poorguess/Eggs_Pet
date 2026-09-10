extends Node

func _ready() -> void:
	var ui := load("res://scenes/face_customizer.tscn").instantiate() as FaceCustomizer
	add_child(ui)
	var track := load("res://assets/pets/face_tracks/character1_walk.tres") as PetFaceTrack
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in 256:
		for x: int in 256:
			var p := Vector2(x, y)
			for eye: Vector2 in [Vector2(75, 95), Vector2(178, 95)]:
				if ((p - eye) / Vector2(20, 13)).length() < 1:
					image.set_pixel(x, y, Color.WHITE)
				if p.distance_to(eye + Vector2(-4, 0)) < 8:
					image.set_pixel(x, y, Color("373039"))
			if x > 62 and x < 88 and y > 67 and y < 71 or x > 165 and x < 191 and y > 67 and y < 71:
				image.set_pixel(x, y, Color("373039"))
			if x > 120 and x < 129 and y > 118 and y < 140:
				image.set_pixel(x, y, Color("79564a"))
			if x > 103 and x < 152 and absf(y - (164 + 0.009 * pow(x - 127, 2))) < 2:
				image.set_pixel(x, y, Color("8f4349"))
	ui.open(track, PetFaceProfile.new(), image)
	var service_preview := OS.get_cmdline_user_args().has("--service-config-preview")
	if service_preview:
		ui._open_service_configuration()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/face_service_preview.png" if service_preview else "res://build/face_customizer_preview.png")
	# Also capture the actual developer workbench at full viewport width.
	ui.queue_free()
	await get_tree().process_frame
	var dock := load("res://addons/face_track_editor/face_track_editor_dock.gd").new() as Control
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/face_track_editor_preview.png")
	print("FACE UI RENDERED")
	get_tree().quit()
