@tool
class_name PetFaceTrack
extends Resource

@export var format_version: int = 2
@export var animation_name: StringName = &"walk"
@export_file("*.png", "*.tres") var source_texture_path: String = "res://assets/pets/character1.png"
@export var source_columns: int = 4
@export var source_rows: int = 9
@export var source_frame_count: int = 33
@export var frame_size: Vector2 = Vector2(320, 395)
@export_multiline var provenance: String = ""
@export var frames: Dictionary = {}
@export var hidden_frames: PackedInt32Array = PackedInt32Array()

func marked_frames() -> Array[int]:
	var keys: Array[int] = []
	for key: Variant in frames:
		keys.append(int(key))
	keys.sort()
	return keys

func get_contour(frame: int) -> PackedVector2Array:
	if frames.has(frame):
		return PackedVector2Array(frames[frame])
	var keys := marked_frames()
	if keys.is_empty():
		return PackedVector2Array()
	var before: int = keys[0]
	var after: int = keys[-1]
	for key: int in keys:
		if key <= frame:
			before = key
		if key >= frame:
			after = key
			break
	var a := PackedVector2Array(frames[before])
	var b := PackedVector2Array(frames[after])
	if before == after or a.size() != b.size():
		return a
	var result := PackedVector2Array()
	var amount := clampf(float(frame - before) / (after - before), 0.0, 1.0)
	for i: int in a.size():
		result.append(a[i].lerp(b[i], amount))
	return result

static func center(points: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in points:
		result += point
	return result / maxi(1, points.size())

static func contour_error(points: PackedVector2Array) -> String:
	if points.size() < 4 or points.size() > 64:
		return "轮廓需要 4–64 个同序点。"
	var origin := center(points)
	for i: int in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		if not a.is_finite() or (a - origin).cross(b - origin) <= 0.01:
			return "轮廓须顺时针、无退化，并能从中心看到整个边界。"
		for j: int in range(i + 2, points.size()):
			if i == 0 and j == points.size() - 1:
				continue
			if Geometry2D.segment_intersects_segment(a, b, points[j], points[(j + 1) % points.size()]) != null:
				return "轮廓边发生交叉。"
	return ""

func validate() -> String:
	if format_version != 2 or not frames.has(0):
		return "需要版本 2 轨迹和第 0 帧基准轮廓。"
	if source_columns < 1 or source_rows < 1 or source_frame_count < 1 or source_frame_count > source_columns * source_rows:
		return "序列图行列或帧数无效。"
	if frame_size.x <= 0 or frame_size.y <= 0:
		return "单帧尺寸无效。"
	var count := PackedVector2Array(frames[0]).size()
	for frame: int in marked_frames():
		if frame < 0 or frame >= source_frame_count:
			return "帧号超出序列范围。"
		var points := PackedVector2Array(frames[frame])
		var error := contour_error(points)
		if not error.is_empty():
			return "帧 %d：%s" % [frame, error]
		if points.size() != count:
			return "所有帧必须使用相同数量和顺序的轮廓点。"
		for point: Vector2 in points:
			if not Rect2(Vector2.ZERO, frame_size).has_point(point):
				return "帧 %d：轮廓超出单帧范围。" % frame
	for frame: int in source_frame_count:
		var error := contour_error(get_contour(frame))
		if not error.is_empty():
			return "插值帧 %d：%s" % [frame, error]
	return ""

func frame_texture(frame: int) -> Texture2D:
	var source := load(source_texture_path)
	if source is SpriteFrames:
		if not source.has_animation(animation_name) or frame >= source.get_frame_count(animation_name):
			return null
		return source.get_frame_texture(animation_name, frame)
	if not source is Texture2D:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(Vector2(frame % source_columns, frame / source_columns) * frame_size, frame_size)
	return atlas
