class_name FaceCompositor
extends Node
## 换脸烘焙编排：照片 -> 关键点 -> 三角 warp -> 羽化混合 -> 成品贴图。
## 信号与 FaceApi 对齐（completed/failed），便于换脸界面在服务端 AI 与端侧管线间切换。

signal completed(image: Image)
signal failed(message: String)

const BLEND_SHADER := "res://assets/shaders/face_blend.gdshader"
const FEATHER_PX := 6.0

var analyzer := FaceAnalyzer.new()
var warp_baker := FaceWarpBaker.new()
# 调试/验证用：最近一次处理的中间产物（warp 层、遮罩、增益）。
var last_intermediates := {}

func _ready() -> void:
	add_child(warp_baker)

## 异步处理入口。base 为角色贴图（输出与其同尺寸），template 定义点位对应关系。
func process_photo(photo: Image, base: Image, template: FaceTemplate) -> void:
	last_intermediates.clear()
	if not template.is_valid():
		failed.emit("模板无效")
		return
	var analysis: Dictionary = analyzer.analyze(photo)
	if not analysis.ok:
		failed.emit(String(analysis.error))
		return
	var landmarks: PackedVector2Array = analysis.landmarks
	var max_index := landmarks.size() - 1
	var src_points := PackedVector2Array()
	for index: int in template.source_indices:
		if index < 0 or index > max_index:
			failed.emit("模板引用了不存在的关键点索引 %d" % index)
			return
		src_points.append(landmarks[index])
	var warped: Image = null
	if DisplayServer.get_name() != "headless":
		var photo_copy: Image = photo.duplicate()
		photo_copy.convert(Image.FORMAT_RGBA8)
		warped = await warp_baker.warp_gpu_async(
			ImageTexture.create_from_image(photo_copy),
			src_points, template.target_points, template.triangles, template.canvas)
	if warped == null:
		warped = FaceWarpBaker.warp_cpu(
			photo, src_points, template.target_points, template.triangles, template.canvas)
	var hull := Geometry2D.convex_hull(template.target_points)
	if hull.size() < 3:
		failed.emit("目标点集凸包退化")
		return
	hull = _smooth_hull(_expand_polygon(hull, 1.08), 2)
	var mask := _build_mask(hull, template.canvas)
	var gain := _estimate_gain(base, warped, mask)
	last_intermediates = {
		"landmarks": landmarks,
		"src_points": src_points,
		"warped": warped,
		"mask": mask,
		"hull": hull,
		"gain": gain,
		"blendshapes": analysis.blendshapes,
	}
	var result: Image = null
	if DisplayServer.get_name() != "headless":
		result = await _blend_gpu(base, warped, mask, gain)
	if result == null:
		result = _blend_cpu(base, warped, hull, gain)
	completed.emit(result)

## 凸包填充遮罩（R8 单通道）。
static func _build_mask(hull: PackedVector2Array, size: Vector2i) -> Image:
	var mask := Image.create_empty(size.x, size.y, false, Image.FORMAT_R8)
	var rect := Rect2()
	for point: Vector2 in hull:
		rect = rect.expand(point)
	var min_x := maxi(0, floori(rect.position.x))
	var min_y := maxi(0, floori(rect.position.y))
	var max_x := mini(size.x - 1, ceili(rect.end.x))
	var max_y := mini(size.y - 1, ceili(rect.end.y))
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), hull):
				mask.set_pixel(x, y, Color.WHITE)
	return mask

## 以质心为中心外扩多边形，避免五官（如眉毛）被遮罩边缘裁切。
static func _expand_polygon(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= points.size()
	var expanded := PackedVector2Array()
	for point: Vector2 in points:
		expanded.append(center + (point - center) * factor)
	return expanded

## Chaikin 角切平滑：消掉凸包的棱角，遮罩边缘更贴合脸部轮廓。
static func _smooth_hull(points: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var current := points
	for _iteration: int in iterations:
		var next := PackedVector2Array()
		for i: int in current.size():
			var a := current[i]
			var b := current[(i + 1) % current.size()]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		current = next
	return current

## 用遮罩内均值估肤色增益：底图均值 / 照片均值，逐通道并限幅，避免极端色偏。
static func _estimate_gain(base: Image, warped: Image, mask: Image) -> Vector3:
	var base_sum := Vector3.ZERO
	var warp_sum := Vector3.ZERO
	var count := 0.0
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			if mask.get_pixel(x, y).r < 0.5:
				continue
			var w := warped.get_pixel(x, y)
			if w.a < 0.5:
				continue
			var b := base.get_pixel(x, y)
			warp_sum += Vector3(w.r, w.g, w.b)
			base_sum += Vector3(b.r, b.g, b.b)
			count += 1.0
	if count < 1.0:
		return Vector3.ONE
	var warp_mean := warp_sum / count
	var base_mean := base_sum / count
	var gain := Vector3.ONE
	for channel: int in 3:
		if warp_mean[channel] > 0.01:
			gain[channel] = clampf(base_mean[channel] / warp_mean[channel], 0.5, 2.0)
	return gain

## GPU 混合：face_blend.gdshader 渲染进 SubViewport 后读回。
func _blend_gpu(base: Image, warped: Image, mask: Image, gain: Vector3) -> Image:
	var base_rgba: Image = base.duplicate()
	base_rgba.convert(Image.FORMAT_RGBA8)
	var shader: Shader = load(BLEND_SHADER)
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("warp_tex", ImageTexture.create_from_image(warped))
	material.set_shader_parameter("mask_tex", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("gain", gain)
	material.set_shader_parameter("feather_px", FEATHER_PX)
	material.set_shader_parameter("mask_size", Vector2(base_rgba.get_size()))
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = base_rgba.get_size()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(base_rgba)
	sprite.centered = false
	sprite.material = material
	viewport.add_child(sprite)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image

## CPU 混合（headless 降级）：以到凸包边的最近距离做羽化。
static func _blend_cpu(base: Image, warped: Image, hull: PackedVector2Array, gain: Vector3) -> Image:
	var out: Image = base.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	var rect := Rect2()
	for point: Vector2 in hull:
		rect = rect.expand(point)
	var min_x := maxi(0, floori(rect.position.x))
	var min_y := maxi(0, floori(rect.position.y))
	var max_x := mini(out.get_width() - 1, ceili(rect.end.x))
	var max_y := mini(out.get_height() - 1, ceili(rect.end.y))
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if not Geometry2D.is_point_in_polygon(p, hull):
				continue
			var w := warped.get_pixel(x, y)
			if w.a < 0.01:
				continue
			var distance := _distance_to_hull(p, hull)
			var m := clampf(distance / FEATHER_PX, 0.0, 1.0) * w.a
			var b := out.get_pixel(x, y)
			var rgb := Vector3(b.r, b.g, b.b).lerp(Vector3(w.r, w.g, w.b) * gain, m)
			out.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, maxf(b.a, w.a * m)))
	return out

static func _distance_to_hull(p: Vector2, hull: PackedVector2Array) -> float:
	var best := INF
	for i: int in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		best = minf(best, _distance_to_segment(p, a, b))
	return best

static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
