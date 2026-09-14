extends Node
## 换脸管线验证场景（开发用，不进游戏流程）。
## 运行：Godot --headless --path . res://scenes/face_lab.tscn
## 产物输出到 user://face_lab/，可用 --cpu-warp 强制 CPU warp 路径。

const PHOTO_PATH := "res://Man.png"
const BASE_PATH := "res://assets/pets/shell_pudding.png"
const TEMPLATE_PATH := "res://assets/face_templates/shell_pudding.json"
const OUT_DIR := "user://face_lab"

var _compositor: FaceCompositor
var _photo: Image
var _base: Image
var _template: FaceTemplate
var _started := 0

func _ready() -> void:
	print("[face_lab] GDMP 可用: %s" % FaceAnalyzer.is_available())
	_photo = _load_image(PHOTO_PATH)
	_base = _load_image(BASE_PATH)
	if _photo == null or _base == null:
		push_error("[face_lab] 测试图片加载失败")
		get_tree().quit(1)
		return
	_template = FaceTemplate.load_from_json(TEMPLATE_PATH)
	if not _template.is_valid():
		push_error("[face_lab] 模板无效")
		get_tree().quit(1)
		return
	print("[face_lab] 模板锚点 %d 个，三角形 %d 个" % [_template.source_indices.size(), _template.triangles.size() / 3])
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_compositor = FaceCompositor.new()
	add_child(_compositor)
	_compositor.completed.connect(_on_completed)
	_compositor.failed.connect(_on_failed)
	_started = Time.get_ticks_msec()
	_compositor.process_photo(_photo, _base, _template)

func _on_completed(image: Image) -> void:
	var elapsed := Time.get_ticks_msec() - _started
	print("[face_lab] 管线完成，耗时 %d ms" % elapsed)
	_save(_photo, "00_photo.png")
	_save(_base, "00_base.png")
	var landmarks: PackedVector2Array = _compositor.last_intermediates.get("landmarks", PackedVector2Array())
	if not landmarks.is_empty():
		_save(_draw_overlay(landmarks, _template.source_indices), "01_landmarks_overlay.png")
	_save(_compositor.last_intermediates.get("warped"), "02_warp.png")
	_save(_compositor.last_intermediates.get("mask"), "03_mask.png")
	print("[face_lab] gain: %s" % _compositor.last_intermediates.get("gain"))
	var blendshapes: Dictionary = _compositor.last_intermediates.get("blendshapes", {})
	for key: String in blendshapes:
		if blendshapes[key] > 0.3:
			print("[face_lab] blendshape %s = %.2f" % [key, blendshapes[key]])
	_save(image, "04_blend.png")
	print("[face_lab] 产物目录: %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)

func _on_failed(message: String) -> void:
	push_error("[face_lab] 管线失败: %s" % message)
	get_tree().quit(1)

## 导出包内 Image.load("res://") 会静默失败，统一走 ResourceLoader。
static func _load_image(path: String) -> Image:
	var texture: Texture2D = ResourceLoader.load(path)
	if texture == null:
		return null
	return texture.get_image()

static func _save(image: Image, file_name: String) -> void:
	if image == null:
		print("[face_lab] 跳过 %s（无数据）" % file_name)
		return
	image.save_png(OUT_DIR.path_join(file_name))

## 关键点叠加图：全部 478 点画暗点，模板子集画亮点并连三角形边。
func _draw_overlay(landmarks: PackedVector2Array, subset: PackedInt32Array) -> Image:
	var overlay: Image = _photo.duplicate()
	overlay.convert(Image.FORMAT_RGBA8)
	for point: Vector2 in landmarks:
		_plot(overlay, point, Color(0.2, 0.5, 1.0, 0.6), 1)
	for index: int in subset:
		_plot(overlay, landmarks[index], Color.RED, 2)
	# triangles 索引指向 target_points 的位置；src/dst 按位置一一对应，取照片侧同名点。
	var triangles := _template.triangles
	for i: int in range(0, triangles.size(), 3):
		for edge: int in 3:
			var a := landmarks[subset[triangles[i + edge]]]
			var b := landmarks[subset[triangles[i + (edge + 1) % 3]]]
			_draw_line(overlay, a, b, Color(1.0, 0.8, 0.2, 0.5))
	return overlay

static func _plot(image: Image, center: Vector2, color: Color, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var x := int(center.x) + dx
			var y := int(center.y) + dy
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)

static func _draw_line(image: Image, a: Vector2, b: Vector2, color: Color) -> void:
	var steps := int(a.distance_to(b))
	for i: int in steps + 1:
		_plot(image, a.lerp(b, float(i) / maxi(steps, 1)), color, 1)
