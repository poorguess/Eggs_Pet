extends Node
## 端侧换脸管线（FaceTemplate/FaceWarpBaker/FaceCompositor/定制器本机模式）的 headless 测试。
## 不依赖 GDMP 原生库：MediaPipe 检测步骤在无库平台只验证优雅降级，真机验证关键点质量。

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	_test_template()
	_test_warp_cpu()
	_test_compositor_statics()
	_test_patch_bake()
	_test_bake_into_sheet()
	_test_analyzer_fallback()
	_test_customizer_composite_ui()
	print("PIPELINE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_template() -> void:
	var template := FaceTemplate.load_from_json("res://assets/face_templates/shell_pudding.json")
	check(template.is_valid(), "shell_pudding template valid")
	check(template.source_indices.size() == 21, "template carries 21 anchors")
	check(template.triangles.size() >= 3, "delaunay triangles rebuilt on load")
	var roundtrip := FaceTemplate.new()
	roundtrip.from_dict(template.to_dict())
	check(roundtrip.is_valid() and roundtrip.source_indices == template.source_indices and roundtrip.target_points == template.target_points, "template dict roundtrip")
	var missing := FaceTemplate.load_from_json("res://assets/face_templates/not_exist.json")
	check(not missing.is_valid(), "missing template flagged invalid")
	var broken := FaceTemplate.new()
	broken.from_dict({"name": "x", "canvas": [64, 64], "anchors": [{"index": 1, "point": [5, 5]}, {"index": 2}]})
	check(broken.source_indices.size() == 1, "malformed anchors skipped")
	check(not broken.is_valid(), "too few anchors invalid")

func _test_warp_cpu() -> void:
	var src := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y: int in 4:
		for x: int in 4:
			src.set_pixel(x, y, Color(x / 4.0, y / 4.0, 0.5, 1.0))
	var quad := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var tris := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var identity := FaceWarpBaker.warp_cpu(src, quad, quad, tris, Vector2i(4, 4))
	check(identity.get_pixel(2, 2) == src.get_pixel(2, 2), "identity warp preserves pixel color")
	check(absf(identity.get_pixel(3, 3).r - src.get_pixel(3, 3).r) < 0.01, "identity warp preserves corner pixel within quantization")
	var shifted := PackedVector2Array([Vector2(2, 0), Vector2(6, 0), Vector2(6, 4), Vector2(2, 4)])
	var moved := FaceWarpBaker.warp_cpu(src, quad, shifted, tris, Vector2i(8, 4))
	check(moved.get_pixel(0, 0).a == 0.0, "uncovered canvas stays transparent")
	check(moved.get_pixel(3, 2) == src.get_pixel(1, 2), "translated warp samples shifted source")
	var degenerate := FaceWarpBaker.warp_cpu(src, quad, quad, PackedInt32Array([0, 0, 1]), Vector2i(4, 4))
	check(degenerate.get_size() == Vector2i(4, 4) and degenerate.get_pixel(2, 2).a == 0.0, "degenerate triangle skipped without crash")
	var empty := FaceWarpBaker.warp_cpu(src, quad, quad, PackedInt32Array(), Vector2i(4, 4))
	check(empty.get_size() == Vector2i(4, 4), "empty triangle list yields sized empty image")

func _test_compositor_statics() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var doubled := FaceCompositor._expand_polygon(square, 2.0)
	check(doubled[0].is_equal_approx(Vector2(-5, -5)), "polygon expands from centroid")
	var smoothed := FaceCompositor._smooth_hull(square, 1)
	check(smoothed.size() == square.size() * 2, "chaikin doubles vertex count")
	var mask := FaceCompositor._build_mask(square, Vector2i(16, 16))
	check(mask.get_pixel(5, 5).r > 0.5, "mask fills hull interior")
	check(mask.get_pixel(15, 15).r < 0.5, "mask leaves exterior empty")

	var base := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	base.fill(Color(0.5, 0.5, 0.5, 1.0))
	var dark := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.25, 0.25, 0.25, 1.0))
	var full := FaceCompositor._build_mask(PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)]), Vector2i(4, 4))
	check(FaceCompositor._estimate_gain(base, dark, full).is_equal_approx(Vector3(2.0, 2.0, 2.0)), "gain reaches upper clamp at ratio")
	check(FaceCompositor._estimate_gain(dark, base, full).is_equal_approx(Vector3(0.5, 0.5, 0.5)), "gain reaches lower clamp at ratio")
	var blank := Image.create_empty(4, 4, false, Image.FORMAT_R8)
	check(FaceCompositor._estimate_gain(base, dark, blank) == Vector3.ONE, "empty mask yields unit gain")

	var hull := PackedVector2Array([Vector2(2, 2), Vector2(14, 2), Vector2(14, 14), Vector2(2, 14)])
	var canvas := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 1.0, 1.0))
	var paint := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	paint.fill(Color(1.0, 0.0, 0.0, 1.0))
	var blended := FaceCompositor._blend_cpu(canvas, paint, hull, Vector3.ONE)
	check(blended.get_pixel(8, 8).r > 0.85 and blended.get_pixel(8, 8).b < 0.15, "blend interior takes warped color")
	check(blended.get_pixel(15, 15).b > 0.99, "blend exterior keeps base color")
	var edge := blended.get_pixel(2, 8)
	check(edge.r > 0.02 and edge.b > 0.8, "blend feathers hull edge")

func _test_patch_bake() -> void:
	var sheet := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.3, 1.0))
	sheet.fill_rect(Rect2i(8, 4, 16, 16), Color(0.95, 0.9, 0.85, 1.0))
	sheet.fill_rect(Rect2i(42, 4, 16, 16), Color(0.95, 0.9, 0.85, 1.0))
	var patch := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	patch.fill(Color(1.0, 0.0, 0.0, 1.0))
	var baked := FaceApi.bake_patch_into_sheet(patch, Rect2i(12, 8, 8, 8), Rect2i(8, 4, 16, 16), sheet, 2, 1, 2)
	check(not baked.is_empty(), "patch bake returns sheet")
	check(baked.get_pixel(14, 10).r > 0.9, "patch lands in frame 0 head")
	check(baked.get_pixel(47, 10).r > 0.9, "patch follows frame 1 head shift")
	check(baked.get_pixel(2, 25).r < 0.3, "body outside patch untouched")
	check(FaceApi.bake_patch_into_sheet(patch, Rect2i(12, 8, 8, 8), Rect2i(), sheet, 2, 1, 2).is_empty(), "invalid head rect rejected")

## 不跑 MediaPipe：手工构造 warp 中间产物，验证逐帧烘焙在主资产上的端到端行为。
func _test_bake_into_sheet() -> void:
	var base_tex: Texture2D = load("res://assets/pets/shell_pudding.png")
	var sheet_tex: Texture2D = load("res://assets/pets/character1.png")
	if base_tex == null or sheet_tex == null:
		check(false, "pet art assets load")
		return
	var base := base_tex.get_image()
	var sheet := sheet_tex.get_image()
	var template := FaceTemplate.load_from_json("res://assets/face_templates/shell_pudding.json")
	var warped := Image.create_empty(template.canvas.x, template.canvas.y, false, Image.FORMAT_RGBA8)
	var blob := Vector2(160, 190)
	for y: int in range(int(blob.y) - 40, int(blob.y) + 40):
		for x: int in range(int(blob.x) - 40, int(blob.x) + 40):
			if Vector2(x + 0.5, y + 0.5).distance_to(blob) <= 40.0:
				warped.set_pixel(x, y, Color(0.08, 0.05, 0.25, 1.0))
	var hull := Geometry2D.convex_hull(template.target_points)
	hull = FaceCompositor._smooth_hull(FaceCompositor._expand_polygon(hull, 1.08), 2)
	var compositor := FaceCompositor.new()
	compositor.last_intermediates = {"warped": warped, "gain": Vector3.ONE, "hull": hull}
	var baked := compositor.bake_into_sheet(base, sheet, 4, 9, 33)
	check(not baked.is_empty(), "bake_into_sheet fabricates full sheet")
	if not baked.is_empty():
		var cell := Vector2i(320, 395) # 帧 5（列 1 行 1）
		var face_px := baked.get_pixel(cell.x + 160, cell.y + 190)
		var src_px := sheet.get_pixel(cell.x + 160, cell.y + 190)
		check(src_px.r > 0.5 and face_px.r < 0.4, "dark face blob baked into frame 5 head")
		var body_dst := baked.get_pixel(cell.x + 30, cell.y + 370)
		var body_src := sheet.get_pixel(cell.x + 30, cell.y + 370)
		check(body_dst.is_equal_approx(body_src), "frame body outside hull untouched")
	var fresh := FaceCompositor.new()
	check(fresh.bake_into_sheet(base, sheet, 4, 9, 33).is_empty(), "bake without intermediates rejected")

func _test_analyzer_fallback() -> void:
	if FaceAnalyzer.is_available():
		return # GDMP 平台的关键点质量由真机验证覆盖
	var photo := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	photo.fill(Color(0.6, 0.5, 0.4, 1.0))
	var analysis: Dictionary = FaceAnalyzer.new().analyze(photo)
	check(not analysis.ok and String(analysis.error).length() > 0, "analyzer reports unavailable cleanly")
	var compositor := FaceCompositor.new()
	add_child(compositor)
	var failure := [""]
	compositor.failed.connect(func(message: String) -> void: failure[0] = message)
	var template := FaceTemplate.load_from_json("res://assets/face_templates/shell_pudding.json")
	compositor.process_photo(photo, photo, template)
	check(failure[0].length() > 0, "compositor fails fast without GDMP")

func _test_customizer_composite_ui() -> void:
	var ui := (load("res://scenes/face_customizer.tscn") as PackedScene).instantiate() as FaceCustomizer
	add_child(ui)
	var track := load("res://assets/pets/face_tracks/character1_walk.tres") as PetFaceTrack
	ui.open(track, PetFaceProfile.new(), null)
	check(ui._mode.get_item_count() == 2, "mode selector lists AI and local")
	check(ui._mode.is_item_disabled(1) == (not FaceAnalyzer.is_available()), "local mode gated by GDMP availability")
	ui._on_mode_changed(1)
	check(ui.local_mode and ui._service.disabled, "local mode disables service config entry")
	ui._on_mode_changed(0)
	check(not ui.local_mode and not ui._service.disabled, "AI mode restores service config entry")
	var composite := Image.create_empty(320, 395, false, Image.FORMAT_RGBA8)
	composite.fill(Color(0.9, 0.85, 0.8, 1.0))
	var got: Array = []
	ui.composite_applied.connect(func(img: Image) -> void: got.append(img))
	ui.set_composite_result(composite)
	check(not ui._apply.disabled, "composite result enables apply")
	check(not ui._sliders["x"].editable, "sliders parked for baked composite")
	ui._apply.pressed.emit()
	check(got.size() == 1 and got[0] == composite, "apply emits composite_applied with image")
	var features := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	ui.set_result(features)
	check(ui._sliders["x"].editable, "sliders resume for AI feature overlay")
	check(ui._composite == null, "AI result clears pending composite")
