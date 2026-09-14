class_name FaceTemplate
extends RefCounted
## 换脸模板：MediaPipe 478 关键点索引子集 -> 角色贴图像素坐标 的对应关系。
## 三角剖分在载入时基于 target_points 重建（Geometry2D.triangulate_delaunay），不落盘。

var name := ""
var canvas := Vector2i.ZERO
var source_indices := PackedInt32Array()
var target_points := PackedVector2Array()
var triangles := PackedInt32Array()

func rebuild_triangles() -> bool:
	triangles = Geometry2D.triangulate_delaunay(target_points)
	# 注意：triangulate_delaunay 不保证三角形 winding 方向；warp 只依赖逐三角形仿射，不受影响。
	return triangles.size() >= 3

func is_valid() -> bool:
	return (
		source_indices.size() == target_points.size()
		and source_indices.size() >= 3
		and triangles.size() >= 3
		and canvas.x > 0
		and canvas.y > 0
	)

func to_dict() -> Dictionary:
	var anchors: Array = []
	for i: int in source_indices.size():
		anchors.append({"index": source_indices[i], "point": [target_points[i].x, target_points[i].y]})
	return {
		"name": name,
		"canvas": [canvas.x, canvas.y],
		"anchors": anchors,
	}

func from_dict(data: Dictionary) -> void:
	name = data.get("name", name)
	var raw_canvas: Array = data.get("canvas", [canvas.x, canvas.y])
	if raw_canvas.size() == 2:
		canvas = Vector2i(int(raw_canvas[0]), int(raw_canvas[1]))
	source_indices = PackedInt32Array()
	target_points = PackedVector2Array()
	for anchor: Variant in data.get("anchors", []):
		if not (anchor is Dictionary):
			continue
		var point: Array = anchor.get("point", [])
		if point.size() != 2:
			continue
		source_indices.append(int(anchor.get("index", -1)))
		target_points.append(Vector2(float(point[0]), float(point[1])))
	rebuild_triangles()

static func load_from_json(path: String) -> FaceTemplate:
	var template := FaceTemplate.new()
	if not FileAccess.file_exists(path):
		push_warning("FaceTemplate: 模板不存在 %s" % path)
		return template
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("FaceTemplate: 无法读取 %s" % path)
		return template
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("FaceTemplate: JSON 解析失败 %s" % path)
		return template
	template.from_dict(parsed)
	if not template.is_valid():
		push_warning("FaceTemplate: 模板数据无效 %s" % path)
	return template
