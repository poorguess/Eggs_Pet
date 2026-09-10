extends Node

const Track = preload("res://scripts/face/face_track.gd")
const Builder = preload("res://scripts/face/face_mesh.gd")
const ImageProcessor = preload("res://scripts/face/face_image.gd")
const Profile = preload("res://scripts/face/face_profile.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var scene := Node.new()
	add_child(scene)
	var contour := PackedVector2Array([Vector2(20, 20), Vector2(120, 20), Vector2(120, 120), Vector2(20, 120)])
	var track := Track.new()
	track.frames = {0: contour, 2: shifted(contour, Vector2(10, 20))}
	check(track.validate().is_empty(), "valid ordered contour")
	check(track.get_contour(1)[0].is_equal_approx(Vector2(25, 30)), "missing frame interpolates")
	check(track.get_contour(32)[0].is_equal_approx(Vector2(30, 40)), "last missing frame holds")
	var mesh := Builder.new()
	mesh.configure(contour)
	var same := mesh.deform(contour)
	var moved := mesh.deform(shifted(contour, Vector2(13, -7)))
	var identity_ok := true
	var translation_ok := true
	for i: int in same.size():
		identity_ok = identity_ok and same[i].distance_to(mesh.vertices[i]) < 0.001
		translation_ok = translation_ok and moved[i].distance_to(mesh.vertices[i] + Vector2(13, -7)) < 0.001
	check(identity_ok, "identity preserves every mesh vertex")
	check(translation_ok, "translation preserves five-feature spacing")
	var crossed := PackedVector2Array([contour[0], contour[2], contour[1], contour[3]])
	check(not Track.contour_error(crossed).is_empty(), "crossed polygon rejected")
	track.frames[2] = PackedVector2Array([Vector2.ZERO])
	check(not track.validate().is_empty(), "mismatched point count rejected")
	var defaults := load("res://assets/pets/face_tracks/character1_walk.tres") as PetFaceTrack
	check(defaults.validate().is_empty() and defaults.frames.size() == 33, "33 baked frames validate")
	var profile := Profile.new()
	var alignment := profile.alignment(defaults.get_contour(0))
	check(is_equal_approx(alignment.x.length(), alignment.y.length()), "default alignment preserves square texture proportions")
	profile.offset = Vector2(7, 9)
	profile.zoom = 0.8
	var restored := Profile.new()
	restored.from_dict(profile.to_dict())
	check(restored.offset == profile.offset and restored.zoom == profile.zoom, "profile roundtrip")
	var fixture := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.MAGENTA)
	fixture.fill_rect(Rect2i(16, 20, 10, 6), Color.WHITE)
	fixture.fill_rect(Rect2i(38, 20, 10, 6), Color.BLACK)
	fixture.fill_rect(Rect2i(25, 42, 14, 3), Color.RED)
	var output := ImageProcessor.prepare(fixture)
	check(String(output.error).is_empty(), "magenta key accepted")
	if output.has("image"):
		var prepared: Image = output.image
		check(prepared.get_pixel(16, 20) == Color.WHITE, "eye white preserved")
		check(prepared.get_pixel(0, 0).a == 0, "chroma becomes transparent")
		var path := "res://build/face_test_profile.json"
		check(profile.save_image(prepared, path) == OK, "atomic profile save")
		check(Profile.load_saved(path).offset == profile.offset, "disk profile roundtrip")
		profile.offset.x = 11
		check(profile.save_image(prepared, path) == OK, "atomic replace existing profile")
	fixture.fill(Color.TRANSPARENT)
	check(not String(ImageProcessor.prepare(fixture).error).is_empty(), "empty alpha rejected")
	fixture.fill(Color(0.9, 0.8, 0.7))
	check(not String(ImageProcessor.prepare(fixture).error).is_empty(), "opaque skin panel rejected")
	var ui := load("res://scenes/face_customizer.tscn").instantiate() as FaceCustomizer
	scene.add_child(ui)
	ui.open(defaults, profile, null)
	ui.draft.offset.x = 50
	check(profile.offset.x == 11, "UI draft does not mutate saved profile")
	ui.set_result(output.image)
	check(not ui._apply.disabled, "result enables apply")
	var cutout_path := ProjectSettings.globalize_path("res://build/face_import_fixture.png")
	var cutout: Image = output.image
	cutout.save_png(cutout_path)
	ui.import_cutout(cutout_path)
	check(ui.image != null and not ui._apply.disabled, "local cutout loads without photo or API")
	check(ui.image.get_width() == ui.image.get_height(), "local cutout receives square transparent padding")
	var accepted: Image = ui.image
	fixture.save_png(cutout_path)
	ui.import_cutout(cutout_path)
	check(ui.image == accepted, "opaque import preserves previous draft")
	var service := load("res://scripts/face/face_service_config.gd")
	check(service.normalize_url(" https://huniuai.token6688.com/v1/images/edits/ ") == "https://huniuai.token6688.com/v1", "service URL normalizes full endpoint")
	check(not service.validate(service.DEFAULT_URL, "", "image-model").is_empty(), "service config rejects missing key")
	check(not service.validate(service.DEFAULT_URL, "test-only-key", "").is_empty(), "service config rejects missing model")
	var config_path := "res://build/face_config_test.cfg"
	check(service.save_config(service.DEFAULT_URL, "test-only-key", "test-image-model", config_path).is_empty(), "service config saves locally")
	var saved_config := ConfigFile.new()
	saved_config.load(config_path)
	check(saved_config.get_value("api", "endpoint") == "https://huniuai.token6688.com/v1/images/edits", "service config stores image edit endpoint")
	ui._open_service_configuration()
	check(ui._service_dialog._key.secret, "API key field masks input")
	ui._service_dialog.hide()
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/pets/character1.png")
	sprite.hframes = 4
	sprite.vframes = 9
	scene.add_child(sprite)
	var overlay := PetFaceOverlay.new()
	sprite.add_child(overlay)
	check(overlay.configure(sprite, defaults, ImageTexture.create_from_image(output.image), profile).is_empty(), "overlay configured")
	sprite.frame = 12
	sprite.flip_h = true
	overlay.sync()
	check(overlay._frame == 12 and overlay.scale.x == -1, "frame and flip synchronized")
	check(overlay.position == Vector2(160, -197.5), "centered sprite local coordinates mirror correctly")
	var dock := load("res://addons/face_track_editor/face_track_editor_dock.gd").new() as Control
	scene.add_child(dock)
	check(dock.get_child_count() > 0, "editor dock constructed")
	print("FACE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func shifted(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point + offset)
	return result
