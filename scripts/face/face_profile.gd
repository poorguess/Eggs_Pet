class_name PetFaceProfile
extends RefCounted

const PATH := "user://pet_face_profile.json"
var offset := Vector2.ZERO
var zoom: float = 1.0
var aspect: float = 1.0
var rotation: float = 0.0
var image_path: String = ""

func to_dict() -> Dictionary:
	return {"version": 1, "offset": [offset.x, offset.y], "zoom": zoom, "aspect": aspect, "rotation": rotation, "image_path": image_path}

func from_dict(data: Dictionary) -> void:
	var xy: Variant = data.get("offset", [0.0, 0.0])
	if xy is Array and xy.size() == 2:
		offset = Vector2(clampf(float(xy[0]), -160, 160), clampf(float(xy[1]), -160, 160))
	zoom = clampf(float(data.get("zoom", 1.0)), 0.25, 2.0)
	aspect = clampf(float(data.get("aspect", 1.0)), 0.5, 1.5)
	rotation = clampf(float(data.get("rotation", 0.0)), -PI / 4, PI / 4)
	image_path = String(data.get("image_path", ""))

func alignment(contour: PackedVector2Array) -> Transform2D:
	var bounds := Rect2(contour[0], Vector2.ZERO)
	for point: Vector2 in contour:
		bounds = bounds.expand(point)
	var base_size := minf(bounds.size.x, bounds.size.y) * 0.9 * zoom
	var dimensions := Vector2(base_size * aspect, base_size)
	var transform := Transform2D(rotation, dimensions, 0, bounds.get_center() + offset)
	transform.origin -= transform.basis_xform(Vector2(0.5, 0.5))
	return transform

func save_image(image: Image, path: String = PATH) -> Error:
	# Commit JSON last: a failed write cannot replace the previously referenced image.
	var next_image := path.get_base_dir().path_join("pet_features_%d.png" % Time.get_ticks_usec())
	var error := image.save_png(next_image)
	if error != OK:
		return error
	var previous := image_path
	image_path = next_image
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		image_path = previous
		DirAccess.remove_absolute(next_image)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		image_path = previous
		DirAccess.remove_absolute(next_image)
	elif previous.begins_with(path.get_base_dir().path_join("pet_features_")) and previous != next_image:
		DirAccess.remove_absolute(previous)
	return error

static func load_saved(path: String = PATH) -> PetFaceProfile:
	var profile := PetFaceProfile.new()
	if not FileAccess.file_exists(path):
		return profile
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		profile.from_dict(data)
	return profile

static func reset_saved(path: String = PATH) -> void:
	var profile := load_saved(path)
	if profile.image_path.begins_with(path.get_base_dir().path_join("pet_features_")):
		DirAccess.remove_absolute(profile.image_path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
