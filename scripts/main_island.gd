extends Node2D

const EGG_TEXTURE := "res://assets/eggs_pics/egg1.png"
const FACE_SAVE_PATH := "user://face.png"
const PET_LOOK_SAVE_PATH := "user://pet_look.png"
const CAMERA_ICON := "res://assets/ui/camera.png"
const CHECK_ICON := "res://assets/ui/check.png"
const CROSS_ICON := "res://assets/ui/cross.png"

var care := CareState.new()
var growth := GrowthState.new()
var stage := "egg"
var toast := "安静的小岛，正在等你。"
var toast_time := 3.5
var save_clock := 0.0
var hatch_flash := 0.0
var pet_bounce := 0.0
var egg_sprite: Sprite2D
var font: Font
var camera_icon: Texture2D
var check_icon: Texture2D
var cross_icon: Texture2D
var face_mode := ""
var face_error := ""
var face_texture: ImageTexture
var pet_look_texture: ImageTexture
var pending_texture: ImageTexture
var preview_texture: ImageTexture
var face_camera: FaceCamera
var face_api: FaceApi
var pet: Pet
var face_overlay: Sprite2D
var detail_open := false
var created_at := 0.0
var hatched_at := 0.0
var _press_target := ""
var _press_amount := 0.0
var _round_scale := 1.0
var _dialog_anim := 1.0
var _ready_notified := false
var _press_tween: Tween
var _dialog_tween: Tween

func _ready() -> void:
	font = ThemeDB.fallback_font
	var background := Node2D.new()
	background.set_script(load("res://scripts/parallax_background.gd"))
	background.z_index = -10
	add_child(background)
	move_child(background, 0)
	face_api = FaceApi.new()
	add_child(face_api)
	face_api.completed.connect(_on_face_completed)
	face_api.failed.connect(_on_face_failed)
	face_camera = FaceCamera.new()
	add_child(face_camera)
	face_camera.preview_frame.connect(_on_face_preview_frame)
	face_camera.permission_denied.connect(_on_face_permission_denied)
	face_camera.unavailable.connect(_open_face_file_dialog)
	if ResourceLoader.exists(CAMERA_ICON):
		camera_icon = load(CAMERA_ICON)
	if ResourceLoader.exists(CHECK_ICON):
		check_icon = load(CHECK_ICON)
	if ResourceLoader.exists(CROSS_ICON):
		cross_icon = load(CROSS_ICON)
	_load_save()
	_create_egg_sprite()
	_ensure_pet()
	_sync_pet_visibility()
	queue_redraw()

func _create_egg_sprite() -> void:
	egg_sprite = Sprite2D.new()
	egg_sprite.texture = load(EGG_TEXTURE)
	egg_sprite.position = Vector2(575, 285)
	egg_sprite.scale = Vector2(0.24, 0.24)
	egg_sprite.z_index = -1
	add_child(egg_sprite)

func _ensure_pet() -> void:
	if pet:
		return
	pet = Pet.new()
	add_child(pet)

func _sync_pet_visibility() -> void:
	if pet:
		pet.visible = stage == "pet" and pet_look_texture == null and face_mode == "" and not detail_open
	_sync_face_overlay()

# 降级模式（角色参考图缺失时）：把漫画头像叠到程序化宠物的头部，保证结果可见。
const FACE_OVERLAY_CANVAS_RADIUS := 44.0
const FACE_OVERLAY_CANVAS_OFFSET := Vector2(0, -12.0)

func _sync_face_overlay() -> void:
	if pet == null:
		return
	var show := face_texture != null and pet_look_texture == null and stage == "pet"
	if face_overlay == null:
		if not show:
			return
		face_overlay = Sprite2D.new()
		face_overlay.z_index = 1
		pet.add_child(face_overlay)
	face_overlay.visible = show
	if show:
		face_overlay.texture = face_texture
		# pet 的缩放会传导给子节点，换算回画布尺寸。
		face_overlay.position = FACE_OVERLAY_CANVAS_OFFSET / pet.pet_scale
		face_overlay.scale = Vector2.ONE * (FACE_OVERLAY_CANVAS_RADIUS * 2.0 / (pet.pet_scale * face_texture.get_width()))

static func _circle_avatar(image: Image, size: int = 256) -> Image:
	var side := mini(image.get_width(), image.get_height())
	var squared := image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	if side != size:
		squared.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if squared.get_format() != Image.FORMAT_RGBA8:
		squared.convert(Image.FORMAT_RGBA8)
	var center := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - center, y - center).length()
			if d > center:
				squared.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > center - 1.5:
				var px := squared.get_pixel(x, y)
				px.a *= (center - d) / 1.5
				squared.set_pixel(x, y, px)
	return squared

func _exit_tree() -> void:
	if _press_tween:
		_press_tween.kill()
	if _dialog_tween:
		_dialog_tween.kill()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		queue_redraw()

func _process(delta: float) -> void:
	care.tick(delta, false)
	growth.tick(delta, care.is_comfortable())
	pet_bounce += delta
	toast_time = maxf(0.0, toast_time - delta)
	hatch_flash = maxf(0.0, hatch_flash - delta)
	save_clock += delta
	if save_clock >= 15.0:
		save_clock = 0.0
		_save()
	if stage == "egg" and growth.hatch_ready and not _ready_notified:
		_ready_notified = true
		toast = "蛋壳裂开了一道缝，点「迎接破壳」吧。"
		toast_time = 4.0
		_save()
	if stage == "egg":
		egg_sprite.visible = true
		egg_sprite.position.y = 285.0 + sin(pet_bounce * PI) * 3.0
	else:
		egg_sprite.visible = false
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at(event.position)
		else:
			_release_at(event.position)
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_at(event.position)
		else:
			_release_at(event.position)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H and stage == "egg" and not growth.hatch_ready:
			growth.hatch_progress = 99.0
			toast = "Hatch preview: almost ready."
			toast_time = 2.0
		if event.keycode == KEY_ESCAPE:
			if detail_open:
				detail_open = false
				_sync_pet_visibility()
			elif face_mode != "":
				_cancel_face_flow()
			queue_redraw()

func _press_at(point: Vector2) -> void:
	var target := ""
	if detail_open:
		if _detail_close_rect().has_point(point):
			target = "close_detail"
	elif face_mode == "":
		if stage == "egg" and _hatch_boost_rect().has_point(point):
			target = "hatch" if growth.hatch_ready else "boost"
		elif _face_button_rect().has_point(point):
			target = "fab"
		elif _creature_hit_rect().has_point(point) or _status_panel_rect(_canvas_size(), _safe_margins()).has_point(point):
			target = "detail"
	else:
		match face_mode:
			"preview":
				if _shutter_rect().has_point(point):
					target = "shutter"
				elif _preview_close_rect().has_point(point):
					target = "close_preview"
			"processing":
				pass
			_:
				if _face_dialog_button(0).has_point(point):
					target = "dialog0"
				elif _face_dialog_button(1).has_point(point):
					target = "dialog1"
				elif _face_close_rect().has_point(point):
					target = "close"
	if target == "":
		return
	_press_target = target
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	if target in ["fab", "shutter"]:
		_press_tween.tween_property(self, "_round_scale", UiTheme.PRESS_SCALE, 0.12)
	else:
		_press_tween.tween_property(self, "_press_amount", 1.0, 0.12)

func _release_at(point: Vector2) -> void:
	var target := _press_target
	_press_target = ""
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.set_parallel()
	_press_tween.tween_property(self, "_round_scale", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(self, "_press_amount", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if target != "" and _target_hit(target, point):
		_activate(target)

func _target_hit(target: String, point: Vector2) -> bool:
	match target:
		"fab":
			return not detail_open and face_mode == "" and _face_button_rect().has_point(point)
		"boost":
			return not detail_open and face_mode == "" and stage == "egg" and not growth.hatch_ready and _hatch_boost_rect().has_point(point)
		"hatch":
			return not detail_open and face_mode == "" and stage == "egg" and growth.hatch_ready and _hatch_boost_rect().has_point(point)
		"detail":
			return not detail_open and face_mode == "" and (_creature_hit_rect().has_point(point) or _status_panel_rect(_canvas_size(), _safe_margins()).has_point(point))
		"close_detail":
			return detail_open and _detail_close_rect().has_point(point)
		"shutter":
			return face_mode == "preview" and _shutter_rect().has_point(point)
		"close_preview":
			return face_mode == "preview" and _preview_close_rect().has_point(point)
		"close":
			return face_mode in ["consent", "confirm", "error"] and _face_close_rect().has_point(point)
		"dialog0":
			return face_mode in ["consent", "confirm", "error"] and _face_dialog_button(0).has_point(point)
		"dialog1":
			return face_mode in ["consent", "confirm", "error"] and _face_dialog_button(1).has_point(point)
	return false

func _activate(target: String) -> void:
	match target:
		"fab":
			_set_face_mode("consent")
		"boost":
			growth.accelerate()
			toast = "蛋壳里传来轻快的动静。"
			toast_time = 1.6
			_save()
		"hatch":
			_do_hatch()
		"detail":
			_open_detail()
		"close_detail":
			detail_open = false
			_sync_pet_visibility()
		"shutter":
			var photo := face_camera.capture()
			if photo:
				_on_photo_ready(photo)
		"close_preview":
			_cancel_face_flow()
		"close":
			match face_mode:
				"confirm":
					pending_texture = null
					_set_face_mode("")
				"error":
					_close_face_error()
				_:
					_set_face_mode("")
		"dialog0":
			_activate_dialog_button(true)
		"dialog1":
			_activate_dialog_button(false)
	queue_redraw()

func _activate_dialog_button(primary: bool) -> void:
	match face_mode:
		"consent":
			if primary:
				_on_face_consent()
			else:
				_set_face_mode("")
		"confirm":
			if primary:
				_apply_face_photo()
			else:
				_retake_face_photo()
		"error":
			if primary:
				_retry_face_photo()
			else:
				_close_face_error()

func _do_hatch() -> void:
	growth.hatch()
	if not growth.hatched:
		return
	stage = "pet"
	growth.intimacy_points = maxf(growth.intimacy_points, 4.0)
	hatched_at = Time.get_unix_time_from_system()
	hatch_flash = 1.2
	_ensure_pet()
	_sync_pet_visibility()
	toast = "壳壳布丁来到岛上了。"
	toast_time = 3.0
	_save()

func _open_detail() -> void:
	detail_open = true
	_sync_pet_visibility()
	if _dialog_tween:
		_dialog_tween.kill()
	_dialog_anim = 0.0
	_dialog_tween = create_tween()
	_dialog_tween.tween_property(self, "_dialog_anim", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_face_mode(mode: String) -> void:
	if face_mode == mode:
		return
	face_mode = mode
	if mode == "preview":
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	_sync_pet_visibility()
	if _dialog_tween:
		_dialog_tween.kill()
	if mode in ["consent", "confirm", "processing", "error"]:
		_dialog_anim = 0.0
		_dialog_tween = create_tween()
		_dialog_tween.tween_property(self, "_dialog_anim", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_dialog_anim = 1.0
	queue_redraw()

func _on_face_consent() -> void:
	if face_camera.native_available():
		_set_face_mode("preview")
		face_camera.start()
	else:
		_set_face_mode("")
		_open_face_file_dialog()

func _open_face_file_dialog() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("选择一张自拍照片", "", "", true, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"]), _on_face_file_selected)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"])
	dialog.size = Vector2i(900, 600)
	dialog.file_selected.connect(func(path: String) -> void:
		_on_face_file_selected(true, PackedStringArray([path]), 0)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _on_face_file_selected(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if not status or paths.is_empty():
		return
	var image := Image.new()
	if image.load(paths[0]) != OK:
		toast = "这张照片读取失败，换一张试试。"
		toast_time = 3.0
		queue_redraw()
		return
	_on_photo_ready(image)

func _on_photo_ready(photo: Image) -> void:
	if face_camera.native_available():
		face_camera.stop()
	print("[FaceFlow] photo ready %dx%d" % [photo.get_width(), photo.get_height()])
	pending_texture = ImageTexture.create_from_image(FaceApi.crop_square(photo))
	_set_face_mode("confirm")

func _apply_face_photo() -> void:
	if pending_texture == null:
		_set_face_mode("")
		return
	_set_face_mode("processing")
	face_api.process_photo(pending_texture.get_image())

func _retake_face_photo() -> void:
	pending_texture = null
	if face_camera.native_available():
		_set_face_mode("preview")
		face_camera.start()
	else:
		_set_face_mode("")
		_open_face_file_dialog()

func _retry_face_photo() -> void:
	if pending_texture == null:
		_set_face_mode("")
		return
	_set_face_mode("processing")
	face_api.process_photo(pending_texture.get_image())

func _close_face_error() -> void:
	if pending_texture:
		_set_face_mode("confirm")
	else:
		_set_face_mode("")

func _cancel_face_flow() -> void:
	face_camera.stop()
	face_api.cancel()
	pending_texture = null
	_set_face_mode("")

func _on_face_completed(image: Image, full_character: bool) -> void:
	print("[FaceFlow] completed full_character=%s image=%dx%d" % [full_character, image.get_width(), image.get_height()])
	if full_character:
		var look := FaceApi.cutout_character(image)
		pet_look_texture = ImageTexture.create_from_image(look)
		look.save_png(PET_LOOK_SAVE_PATH)
		_sync_pet_visibility()
		toast = "壳壳布丁换上了你的脸。"
	else:
		face_texture = ImageTexture.create_from_image(_circle_avatar(image))
		image.save_png(FACE_SAVE_PATH)
		_sync_face_overlay()
		toast = "新脸已就位，壳壳布丁变样了。"
	pending_texture = null
	_set_face_mode("")
	toast_time = 3.0
	_save()
	queue_redraw()

func _on_face_failed(message: String) -> void:
	print("[FaceFlow] failed: %s" % message)
	face_error = message
	_set_face_mode("error")

func _on_face_preview_frame(texture: ImageTexture) -> void:
	preview_texture = texture
	if face_mode == "preview":
		queue_redraw()

func _on_face_permission_denied() -> void:
	_set_face_mode("")
	toast = "没有相机权限，无法自拍。可以在系统设置里开启。"
	toast_time = 4.0
	queue_redraw()

func _debug_apply_face_from_path(path: String) -> void:
	var image := Image.new()
	if image.load(path) == OK:
		_on_photo_ready(image)
		_apply_face_photo()

func _draw() -> void:
	var viewport := _canvas_size()
	var m := _safe_margins()
	if face_mode == "preview":
		_draw_face_preview(viewport, m)
		return
	_draw_title(m)
	_draw_status(viewport, m)
	if stage == "pet":
		_draw_pet()
	if stage == "egg":
		_draw_hatch_timer(viewport, m)
	if face_mode == "":
		_draw_face_button()
	else:
		_draw_face_overlay(viewport, m)
	if detail_open:
		_draw_detail(viewport)
	if toast_time > 0.0:
		_draw_toast(viewport, m)

func _draw_title(m: Vector4) -> void:
	var x := m.x + 40.0
	var y := m.y + 40.0
	draw_string(font, Vector2(x + 2, y + font.get_ascent(UiTheme.FONT_TITLE) + 2), "蛋岛", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, UiTheme.SHADOW_WARM)
	draw_string(font, Vector2(x, y + font.get_ascent(UiTheme.FONT_TITLE)), "蛋岛", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, UiTheme.INK)
	draw_string(font, Vector2(x, y + 84.0), "浮空小岛  /  第一天", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, UiTheme.INK_SOFT)

func _draw_toast(viewport: Vector2, m: Vector4) -> void:
	var width := minf(720.0, viewport.x - m.x - m.z - 80.0)
	var rect := Rect2((viewport.x - width) * 0.5, m.y + 32.0, width, 64)
	UiTheme.draw_panel(self, rect, UiTheme.CREAM, rect.size.y * 0.5, 0.96)
	UiTheme.draw_label_centered(self, font, rect, toast, UiTheme.FONT_HINT, UiTheme.INK)

func _draw_status(viewport: Vector2, m: Vector4) -> void:
	var panel := _status_panel_rect(viewport, m)
	UiTheme.draw_panel(self, panel, UiTheme.CREAM, UiTheme.RADIUS_PANEL, 0.92)
	var name_text := "壳壳布丁  ·  " + _intimacy_level_cn() if stage == "pet" else "一颗蛋  ·  孵化中"
	if stage == "egg" and growth.hatch_ready:
		name_text = "一颗蛋  ·  即将破壳"
	draw_string(font, panel.position + Vector2(24, 24 + font.get_ascent(UiTheme.FONT_BODY)), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_BODY, UiTheme.INK)
	_draw_stat_rows(panel.position + Vector2(0, 76))

func _draw_stat_rows(origin: Vector2, alpha: float = 1.0) -> void:
	var values := [care.temperature, care.hunger, care.cleanliness, care.mood]
	var chars := ["温", "饱", "洁", "心"]
	var colors := [UiTheme.STATUS_TEMPERATURE, UiTheme.STATUS_HUNGER, UiTheme.STATUS_CLEANLINESS, UiTheme.STATUS_MOOD]
	for i in range(4):
		var cy := origin.y + i * 46.0 + 16.0
		var dot_center := Vector2(origin.x + 38.0, cy)
		draw_circle(dot_center, 14, UiTheme.fade(colors[i], alpha))
		UiTheme.draw_label_centered(self, font, Rect2(dot_center - Vector2(14, 14), Vector2(28, 28)), chars[i], 20, UiTheme.fade(UiTheme.CREAM, alpha))
		var bar := Rect2(origin.x + 68.0, cy - 11.0, 220, 22)
		UiTheme.draw_status_bar(self, bar, values[i] / 100.0, colors[i], alpha)
		draw_string(font, Vector2(bar.end.x + 16.0, cy + font.get_ascent(UiTheme.FONT_HINT) * 0.35), str(int(round(values[i]))), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, UiTheme.fade(UiTheme.INK, alpha))

func _draw_pet() -> void:
	var p := Vector2(575, 292 + sin(pet_bounce * 2.0) * 4.0)
	if hatch_flash > 0.0:
		draw_circle(p, 106.0 * (1.2 - hatch_flash * 0.15), UiTheme.fade(UiTheme.LEMON, hatch_flash * 0.22))
	if pet_look_texture:
		var squish := 1.0 + sin(pet_bounce * 3.0) * 0.035
		draw_set_transform(p, 0.0, Vector2(squish, 1.0 / squish))
		var tex_size := pet_look_texture.get_size()
		var fit := 260.0 / tex_size.y
		var draw_size := tex_size * fit
		draw_texture_rect(pet_look_texture, Rect2(Vector2(-draw_size.x * 0.5, -draw_size.y * 0.6), draw_size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hatch_timer(viewport: Vector2, m: Vector4) -> void:
	var panel := _hatch_panel_rect(viewport, m)
	UiTheme.draw_panel(self, panel, UiTheme.CREAM, UiTheme.RADIUS_PANEL)
	if growth.hatch_ready:
		UiTheme.draw_label_centered(self, font, Rect2(panel.position + Vector2(0, 24), Vector2(panel.size.x, 32)), "可以破壳了", UiTheme.FONT_HINT, UiTheme.INK_SOFT)
		UiTheme.draw_string_outlined(self, font, Vector2(panel.position.x, panel.position.y + 134.0), "100%", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, UiTheme.FONT_COUNTDOWN, UiTheme.LEMON, UiTheme.INK, 2)
		var ready_press := _press_amount if _press_target == "hatch" else 0.0
		UiTheme.draw_candy_button(self, _hatch_boost_rect(), "迎接破壳", font, UiTheme.CANDY_PINK, UiTheme.CANDY_PINK_DARK, ready_press)
	else:
		UiTheme.draw_label_centered(self, font, Rect2(panel.position + Vector2(0, 24), Vector2(panel.size.x, 32)), "孵化中", UiTheme.FONT_HINT, UiTheme.INK_SOFT)
		var number := "%d%%" % int(floor(growth.hatch_progress))
		UiTheme.draw_string_outlined(self, font, Vector2(panel.position.x, panel.position.y + 134.0), number, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, UiTheme.FONT_COUNTDOWN, UiTheme.LEMON, UiTheme.INK, 2)
		var press := _press_amount if _press_target == "boost" else 0.0
		UiTheme.draw_candy_button(self, _hatch_boost_rect(), "加速 -5s", font, UiTheme.SKY, UiTheme.SKY_DARK, press)

func _draw_face_button() -> void:
	var rect := _face_button_rect()
	var center := rect.get_center()
	var s := _round_scale
	draw_circle(center + Vector2(0, 6), 60, UiTheme.SHADOW_WARM)
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	draw_circle(center, 60, UiTheme.CREAM)
	draw_arc(center, 57, 0, TAU, 64, UiTheme.CANDY_PINK, 6.0)
	if camera_icon:
		UiTheme.draw_icon(self, camera_icon, Rect2(center - Vector2(33, 33), Vector2(66, 66)))
	else:
		UiTheme.draw_label_centered(self, font, rect, "拍", UiTheme.FONT_BODY, UiTheme.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_face_overlay(viewport: Vector2, m: Vector4) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport), UiTheme.DIM)
	var panel := _face_panel_rect()
	var s := 0.8 + 0.2 * _dialog_anim
	var a := clampf(_dialog_anim, 0.0, 1.0)
	var center := panel.get_center()
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	var frosting := UiTheme.CANDY_PINK
	match face_mode:
		"processing":
			frosting = UiTheme.SKY
		"error":
			frosting = UiTheme.DANGER
	UiTheme.draw_panel(self, panel, UiTheme.CREAM, UiTheme.RADIUS_PANEL, a)
	UiTheme.draw_frosting(self, panel, frosting, a)
	match face_mode:
		"consent":
			_draw_face_consent(panel, a)
		"confirm":
			_draw_face_confirm(panel, a)
		"processing":
			_draw_face_processing(panel, a)
		"error":
			_draw_face_error(panel, a)
	if face_mode != "processing":
		_draw_close_button(a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_face_consent(panel: Rect2, a: float) -> void:
	var ink := UiTheme.fade(UiTheme.INK, a)
	var soft := UiTheme.fade(UiTheme.INK_SOFT, a)
	draw_string(font, panel.position + Vector2(56, 64 + font.get_ascent(UiTheme.FONT_TITLE)), "自拍换脸", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, ink)
	draw_multiline_string(font, panel.position + Vector2(56, 160), "拍一张正面自拍，AI 会把你的五官融到壳壳布丁的脸上。\n照片仅用于生成形象，生成后可以随时重拍替换。", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 112, UiTheme.FONT_HINT, 8, soft)
	_draw_dialog_buttons("同意并拍照", null, "取消", null, a)

func _draw_face_confirm(panel: Rect2, a: float) -> void:
	draw_string(font, panel.position + Vector2(56, 64 + font.get_ascent(UiTheme.FONT_TITLE)), "用这张脸吗？", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, UiTheme.fade(UiTheme.INK, a))
	if pending_texture:
		var side := 260.0
		var photo := Rect2(panel.get_center() - Vector2(side * 0.5, side * 0.5 + 20), Vector2(side, side))
		draw_style_box(UiTheme.pill_style(UiTheme.fade(UiTheme.CREAM_DARK, a), 24), photo.grow(12))
		draw_texture_rect(pending_texture, photo, false, Color(1, 1, 1, a))
		var border := StyleBoxFlat.new()
		border.draw_center = false
		border.border_color = UiTheme.fade(UiTheme.CANDY_PINK, a)
		border.border_width_top = 4
		border.border_width_bottom = 4
		border.border_width_left = 4
		border.border_width_right = 4
		border.corner_radius_top_left = 12
		border.corner_radius_top_right = 12
		border.corner_radius_bottom_left = 12
		border.corner_radius_bottom_right = 12
		draw_style_box(border, photo)
	_draw_dialog_buttons("使用这张", check_icon, "重拍", cross_icon, a)

func _draw_face_processing(panel: Rect2, a: float) -> void:
	var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
	var center := panel.get_center()
	var spin := Time.get_ticks_msec() / 300.0
	draw_arc(center - Vector2(0, 40), 36, spin, spin + 4.2, 24, UiTheme.fade(UiTheme.SKY, a), 10.0)
	UiTheme.draw_label_centered(self, font, Rect2(panel.position.x, center.y + 24, panel.size.x, 48), "正在融合你的五官" + dots, UiTheme.FONT_BODY, UiTheme.fade(UiTheme.INK, a))

func _draw_face_error(panel: Rect2, a: float) -> void:
	draw_string(font, panel.position + Vector2(56, 64 + font.get_ascent(UiTheme.FONT_TITLE)), "出错了", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, UiTheme.fade(UiTheme.DANGER, a))
	draw_multiline_string(font, panel.position + Vector2(56, 160), face_error + "\n检查网络后可以重试。", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 112, UiTheme.FONT_HINT, 8, UiTheme.fade(UiTheme.INK_SOFT, a))
	_draw_dialog_buttons("重试", null, "取消", null, a)

func _draw_dialog_buttons(primary_label: String, primary_icon: Texture2D, secondary_label: String, secondary_icon: Texture2D, a: float) -> void:
	var primary_press := _press_amount if _press_target == "dialog0" else 0.0
	var secondary_press := _press_amount if _press_target == "dialog1" else 0.0
	UiTheme.draw_secondary_button(self, _face_dialog_button(1), secondary_label, font, secondary_press, a, secondary_icon)
	UiTheme.draw_candy_button(self, _face_dialog_button(0), primary_label, font, UiTheme.CANDY_PINK, UiTheme.CANDY_PINK_DARK, primary_press, a, primary_icon)

func _draw_close_button(a: float) -> void:
	var rect := _face_close_rect()
	draw_circle(rect.get_center(), 28, UiTheme.fade(UiTheme.CREAM_DARK, a))
	UiTheme.draw_label_centered(self, font, rect, "×", UiTheme.FONT_BODY, UiTheme.fade(UiTheme.INK, a))

func _draw_face_preview(viewport: Vector2, m: Vector4) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport), UiTheme.INK.darkened(0.55))
	if preview_texture:
		var tex_size := preview_texture.get_size()
		var fit := maxf(viewport.x / tex_size.x, viewport.y / tex_size.y)
		var src_size := Vector2(viewport.x / fit, viewport.y / fit)
		var src_rect := Rect2((tex_size - src_size) * 0.5, src_size)
		draw_texture_rect_region(preview_texture, Rect2(Vector2.ZERO, viewport), src_rect)
	var ring_center := Vector2(viewport.x * 0.5, viewport.y * 0.42)
	var ring_r := minf(viewport.x, viewport.y) * 0.32
	draw_arc(ring_center, ring_r + 8.0, 0, TAU, 96, UiTheme.fade(UiTheme.INK, 0.25), 14.0)
	draw_arc(ring_center, ring_r, 0, TAU, 96, UiTheme.fade(UiTheme.CREAM, 0.9), 4.0)
	var shutter := _shutter_rect()
	var hint := Rect2(0, shutter.position.y - 64, viewport.x, 40)
	UiTheme.draw_label_centered(self, font, hint, "把脸放进圆圈里，保持正面", UiTheme.FONT_HINT, UiTheme.CREAM)
	var center := shutter.get_center()
	var s := _round_scale
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	draw_circle(center + Vector2(0, 8), 88, UiTheme.SHADOW_WARM)
	draw_circle(center, 88, Color.WHITE)
	draw_arc(center, 66, 0, TAU, 64, UiTheme.CANDY_PINK, 12.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var close := _preview_close_rect()
	draw_circle(close.get_center(), 44, UiTheme.fade(UiTheme.CREAM, 0.92))
	UiTheme.draw_label_centered(self, font, close, "×", UiTheme.FONT_TITLE, UiTheme.INK)

func _draw_detail(viewport: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport), UiTheme.DIM)
	var panel := _detail_panel_rect()
	var s := 0.8 + 0.2 * _dialog_anim
	var a := clampf(_dialog_anim, 0.0, 1.0)
	var center := panel.get_center()
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	UiTheme.draw_panel(self, panel, UiTheme.CREAM, UiTheme.RADIUS_PANEL, a)
	UiTheme.draw_frosting(self, panel, UiTheme.CANDY_PINK, a)
	if stage == "egg":
		_draw_detail_egg(panel, a)
	else:
		_draw_detail_pet(panel, a)
	var close := _detail_close_rect()
	draw_circle(close.get_center(), 28, UiTheme.fade(UiTheme.CREAM_DARK, a))
	UiTheme.draw_label_centered(self, font, close, "×", UiTheme.FONT_BODY, UiTheme.fade(UiTheme.INK, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_detail_egg(panel: Rect2, a: float) -> void:
	var ink := UiTheme.fade(UiTheme.INK, a)
	var soft := UiTheme.fade(UiTheme.INK_SOFT, a)
	var x := panel.position.x + 48.0
	draw_string(font, Vector2(x, panel.position.y + 56.0 + font.get_ascent(UiTheme.FONT_TITLE)), "一颗蛋", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, ink)
	draw_string(font, Vector2(x, panel.position.y + 136.0), "普通蛋  ·  到家第 %d 天" % _days_since(created_at), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)
	var progress_text := "孵化进度  %d%%  ·  约 %ds 后破壳" % [int(floor(growth.hatch_progress)), int(ceil(growth.hatch_seconds_left()))]
	if growth.hatch_ready:
		progress_text = "孵化进度  100%  ·  可以破壳了"
	draw_string(font, Vector2(x, panel.position.y + 196.0), progress_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_BODY, ink)
	UiTheme.draw_status_bar(self, Rect2(x, panel.position.y + 216.0, panel.size.x - 96.0, 22), growth.hatch_progress / 100.0, UiTheme.LEMON, a)
	_draw_stat_rows(Vector2(x - 24.0, panel.position.y + 280.0), a)
	draw_string(font, Vector2(x, panel.position.y + 524.0), "把四项状态保持在 60 以上，蛋会舒服地长大。", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)
	if not growth.hatch_ready:
		draw_string(font, Vector2(x, panel.position.y + 560.0), "点下方「加速」可以让它早点破壳。", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)
	else:
		draw_string(font, Vector2(x, panel.position.y + 560.0), "点下方「迎接破壳」，见它第一面。", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)

func _draw_detail_pet(panel: Rect2, a: float) -> void:
	var ink := UiTheme.fade(UiTheme.INK, a)
	var soft := UiTheme.fade(UiTheme.INK_SOFT, a)
	var x := panel.position.x + 48.0
	draw_string(font, Vector2(x, panel.position.y + 56.0 + font.get_ascent(UiTheme.FONT_TITLE)), "壳壳布丁", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, ink)
	var sub := "Shell Pudding  ·  相伴第 %d 天" % _days_since(hatched_at)
	if hatched_at > 0.0:
		sub += "  ·  破壳于 " + _date_cn(hatched_at)
	draw_string(font, Vector2(x, panel.position.y + 136.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)
	draw_string(font, Vector2(x, panel.position.y + 196.0), "亲密度  %s" % _intimacy_level_cn(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_BODY, ink)
	UiTheme.draw_status_bar(self, Rect2(x, panel.position.y + 216.0, panel.size.x - 96.0, 22), growth.intimacy_progress(), UiTheme.CANDY_PINK, a)
	draw_string(font, Vector2(x, panel.position.y + 262.0), _intimacy_hint(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)
	_draw_stat_rows(Vector2(x - 24.0, panel.position.y + 304.0), a)
	var look := "默认样貌"
	if pet_look_texture:
		look = "已使用你的长相"
	elif face_texture:
		look = "漫画头像（简易模式）"
	draw_string(font, Vector2(x, panel.position.y + 548.0), "外貌：%s  ·  动作：继续照护可解锁新动作" % look, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_HINT, soft)

func _days_since(timestamp: float) -> int:
	if timestamp <= 0.0:
		return 1
	return maxi(1, int((Time.get_unix_time_from_system() - timestamp) / 86400.0) + 1)

func _date_cn(timestamp: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(timestamp))
	return "%d月%d日" % [dt.month, dt.day]

func _intimacy_hint() -> String:
	var level := growth.intimacy_level()
	if level == "Close":
		return "已达最高亲密度，它完全信任你。"
	var target := GrowthState.INTIMACY_COMFORTABLE if level == "Stranger" else GrowthState.INTIMACY_CLOSE
	var next := "安心" if level == "Stranger" else "亲近"
	return "再陪伴 +%d 点升到「%s」" % [int(ceil(target - growth.intimacy_points)), next]

func _intimacy_level_cn() -> String:
	return {"Stranger": "陌生", "Comfortable": "安心", "Close": "亲近"}.get(growth.intimacy_level(), "陌生")

func _canvas_size() -> Vector2:
	return get_viewport().get_visible_rect().size

# Vector4(left, top, right, bottom) in canvas units, at least 16px on every side.
func _safe_margins() -> Vector4:
	var canvas := _canvas_size()
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector4(16, 16, 16, 16)
	var area := DisplayServer.get_display_safe_area()
	var sx := canvas.x / window.x
	var sy := canvas.y / window.y
	return Vector4(
		maxf(16.0, area.position.x * sx),
		maxf(16.0, area.position.y * sy),
		maxf(16.0, (window.x - area.end.x) * sx),
		maxf(16.0, (window.y - area.end.y) * sy))

func _status_panel_rect(viewport: Vector2, m: Vector4) -> Rect2:
	return Rect2(viewport.x - m.z - 40.0 - 392.0, m.y + 40.0, 392.0, 76.0 + 4 * 46.0 + 24.0)

func _hatch_panel_rect(viewport: Vector2, m: Vector4) -> Rect2:
	return Rect2((viewport.x - 480.0) * 0.5, viewport.y - m.w - 40.0 - 260.0, 480.0, 260.0)

func _hatch_boost_rect() -> Rect2:
	var panel := _hatch_panel_rect(_canvas_size(), _safe_margins())
	return Rect2(panel.position.x + (panel.size.x - 280.0) * 0.5, panel.end.y - 16.0 - 88.0, 280.0, 88.0)

func _face_button_rect() -> Rect2:
	var size := _canvas_size()
	var m := _safe_margins()
	return Rect2(size.x - m.z - 40.0 - 120.0, size.y - m.w - 40.0 - 120.0, 120.0, 120.0)

func _face_panel_rect() -> Rect2:
	var size := _canvas_size()
	return Rect2((size.x - 760.0) * 0.5, (size.y - 560.0) * 0.5, 760.0, 560.0)

func _face_dialog_button(index: int) -> Rect2:
	var panel := _face_panel_rect()
	var y := panel.end.y - 40.0 - 88.0
	if index == 0:
		return Rect2(panel.end.x - 56.0 - 280.0, y, 280.0, 88.0)
	return Rect2(panel.position.x + 56.0, y, 280.0, 88.0)

func _face_close_rect() -> Rect2:
	var panel := _face_panel_rect()
	return Rect2(panel.end.x - 56.0 - 56.0, panel.position.y + 28.0, 56.0, 56.0)

func _preview_close_rect() -> Rect2:
	var m := _safe_margins()
	return Rect2(m.x + 32.0, m.y + 32.0, 96.0, 96.0)

func _shutter_rect() -> Rect2:
	var size := _canvas_size()
	var m := _safe_margins()
	return Rect2(size.x * 0.5 - 88.0, size.y - m.w - 40.0 - 176.0, 176.0, 176.0)

func _detail_panel_rect() -> Rect2:
	var size := _canvas_size()
	return Rect2((size.x - 860.0) * 0.5, (size.y - 680.0) * 0.5, 860.0, 680.0)

func _detail_close_rect() -> Rect2:
	var panel := _detail_panel_rect()
	return Rect2(panel.end.x - 48.0 - 56.0, panel.position.y + 28.0, 56.0, 56.0)

func _creature_hit_rect() -> Rect2:
	if pet_look_texture:
		return Rect2(445.0, 120.0, 280.0, 320.0)
	if pet and pet.visible:
		return Rect2(pet.position - Vector2(90, 110), Vector2(180, 220))
	return Rect2(445.0, 120.0, 280.0, 320.0)

func _load_save() -> void:
	var data := SaveService.apply_offline(SaveService.load_data())
	stage = String(data.get("stage", "egg"))
	care.from_dict(data.get("care", {}))
	growth.from_dict(data)
	if growth.hatched:
		stage = "pet"
	created_at = float(data.get("created_at", 0.0))
	if created_at <= 0.0:
		created_at = Time.get_unix_time_from_system()
	hatched_at = float(data.get("hatched_at", 0.0))
	if bool(data.get("has_face", false)) and FileAccess.file_exists(FACE_SAVE_PATH):
		var face_image := Image.new()
		if face_image.load(FACE_SAVE_PATH) == OK:
			face_texture = ImageTexture.create_from_image(_circle_avatar(face_image))
	if bool(data.get("has_pet_look", false)) and FileAccess.file_exists(PET_LOOK_SAVE_PATH):
		var look_image := Image.new()
		if look_image.load(PET_LOOK_SAVE_PATH) == OK:
			pet_look_texture = ImageTexture.create_from_image(look_image)

func _save() -> void:
	var data := {"stage": stage, "egg_type": "common_egg", "pet_species": "shell_pudding", "care": care.to_dict(), "has_face": face_texture != null, "has_pet_look": pet_look_texture != null, "created_at": created_at, "hatched_at": hatched_at}
	data.merge(growth.to_dict())
	SaveService.save_data(data)
