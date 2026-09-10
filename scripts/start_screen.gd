extends Node2D

const EGG_TEXTURE := "res://assets/eggs_pics/Newegg.png"

var font: Font
var egg: Sprite2D
var has_save := false
var confirm_reset := false
var press_target := ""
var press := 0.0
var press_tween: Tween
var dialog_anim := 1.0
var dialog_tween: Tween
var float_clock := 0.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	has_save = FileAccess.file_exists(SaveService.PATH)
	egg = Sprite2D.new()
	egg.texture = load(EGG_TEXTURE)
	egg.scale = Vector2(0.28, 0.28)
	add_child(egg)
	queue_redraw()

func _exit_tree() -> void:
	if press_tween:
		press_tween.kill()
	if dialog_tween:
		dialog_tween.kill()

func _process(delta: float) -> void:
	float_clock += delta
	var size := get_viewport().get_visible_rect().size
	egg.position = Vector2(size.x * 0.5, size.y * 0.5 + sin(float_clock * PI) * 3.0)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_SPACE] and not confirm_reset:
			_open_island()
		if event.keycode == KEY_ESCAPE and confirm_reset:
			confirm_reset = false
			egg.visible = true
			queue_redraw()

func _press(point: Vector2) -> void:
	var target := ""
	if confirm_reset:
		if _confirm_button(0).has_point(point):
			target = "confirm_yes"
		elif _confirm_button(1).has_point(point):
			target = "confirm_no"
	elif has_save:
		if _primary_button_rect().has_point(point):
			target = "start"
		elif _secondary_button_rect().has_point(point):
			target = "reset"
	elif _start_button_rect().has_point(point):
		target = "start"
	if target == "":
		return
	press_target = target
	if press_tween:
		press_tween.kill()
	press_tween = create_tween()
	press_tween.tween_property(self, "press", 1.0, 0.12)

func _release(point: Vector2) -> void:
	var target := press_target
	press_target = ""
	if press_tween:
		press_tween.kill()
	press_tween = create_tween()
	press_tween.tween_property(self, "press", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if target == "" or not _hit(target, point):
		return
	match target:
		"start":
			_open_island()
		"reset":
			_show_reset_confirm()
		"confirm_yes":
			_do_reset()
		"confirm_no":
			confirm_reset = false
			egg.visible = true
			queue_redraw()

func _hit(target: String, point: Vector2) -> bool:
	match target:
		"start":
			if confirm_reset:
				return false
			return _primary_button_rect().has_point(point) if has_save else _start_button_rect().has_point(point)
		"reset":
			return has_save and not confirm_reset and _secondary_button_rect().has_point(point)
		"confirm_yes":
			return confirm_reset and _confirm_button(0).has_point(point)
		"confirm_no":
			return confirm_reset and _confirm_button(1).has_point(point)
	return false

func _open_island() -> void:
	get_tree().change_scene_to_file("res://scenes/main_island.tscn")

func _show_reset_confirm() -> void:
	confirm_reset = true
	egg.visible = false
	if dialog_tween:
		dialog_tween.kill()
	dialog_anim = 0.0
	dialog_tween = create_tween()
	dialog_tween.tween_property(self, "dialog_anim", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _do_reset() -> void:
	SaveService.reset()
	has_save = false
	confirm_reset = false
	egg.visible = true
	queue_redraw()

func _start_button_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	return Rect2(size.x * 0.5 - 160.0, size.y - _margins().w - 96.0 - 88.0, 320.0, 88.0)

func _primary_button_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	return Rect2(size.x * 0.5 + 16.0, size.y - _margins().w - 96.0 - 88.0, 320.0, 88.0)

func _secondary_button_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	return Rect2(size.x * 0.5 - 16.0 - 320.0, size.y - _margins().w - 96.0 - 88.0, 320.0, 88.0)

func _confirm_panel_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	return Rect2((size.x - 640.0) * 0.5, (size.y - 420.0) * 0.5, 640.0, 420.0)

func _confirm_button(index: int) -> Rect2:
	var panel := _confirm_panel_rect()
	var y := panel.end.y - 40.0 - 88.0
	if index == 0:
		return Rect2(panel.end.x - 48.0 - 260.0, y, 260.0, 88.0)
	return Rect2(panel.position.x + 48.0, y, 260.0, 88.0)

func _margins() -> Vector4:
	var canvas := get_viewport().get_visible_rect().size
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

func _draw() -> void:
	var size := get_viewport().get_visible_rect().size
	var m := _margins()
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.CREAM)

	draw_string(font, Vector2(0, size.y * 0.16), "蛋岛", HORIZONTAL_ALIGNMENT_CENTER, size.x, 96, UiTheme.INK)
	draw_string(font, Vector2(0, size.y * 0.16 + 52.0), "一颗蛋，正在等你", HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.FONT_BODY, UiTheme.INK)
	draw_string(font, Vector2(0, size.y * 0.16 + 96.0), "在安静的小岛上，慢慢照顾它长大。", HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.FONT_HINT, UiTheme.INK_SOFT)

	var egg_bottom := egg.position.y + egg.texture.get_height() * egg.scale.y * 0.5
	_draw_shadow_ellipse(Vector2(size.x * 0.5, egg_bottom + 20.0), Vector2(150, 18), Color(UiTheme.INK, 0.10))

	if has_save:
		var start_press := press if press_target == "start" else 0.0
		var reset_press := press if press_target == "reset" else 0.0
		draw_string(font, Vector2(0, _primary_button_rect().position.y - 32.0), "欢迎回来，它一直在等你。", HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.FONT_HINT, UiTheme.INK_SOFT)
		UiTheme.draw_secondary_button(self, _secondary_button_rect(), "重新开始", font, reset_press)
		UiTheme.draw_candy_button(self, _primary_button_rect(), "继续游戏", font, UiTheme.CANDY_PINK, UiTheme.CANDY_PINK_DARK, start_press)
	else:
		var button := _start_button_rect()
		draw_string(font, Vector2(0, button.position.y - 32.0), "准备好了吗？", HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.FONT_HINT, UiTheme.INK_SOFT)
		UiTheme.draw_candy_button(self, button, "开始", font, UiTheme.CANDY_PINK, UiTheme.CANDY_PINK_DARK, press if press_target == "start" else 0.0)
	draw_string(font, Vector2(0, size.y - m.w - 40.0), "横屏体验 · 轻柔照护 · 随时回来", HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.FONT_HINT, UiTheme.INK_SOFT)

	if confirm_reset:
		_draw_reset_confirm(size)

func _draw_reset_confirm(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.DIM)
	var panel := _confirm_panel_rect()
	var s := 0.8 + 0.2 * dialog_anim
	var a := clampf(dialog_anim, 0.0, 1.0)
	var center := panel.get_center()
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	UiTheme.draw_panel(self, panel, UiTheme.CREAM, UiTheme.RADIUS_PANEL, a)
	UiTheme.draw_frosting(self, panel, UiTheme.DANGER, a)
	draw_string(font, panel.position + Vector2(48, 56 + font.get_ascent(UiTheme.FONT_TITLE)), "重新开始？", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_TITLE, UiTheme.fade(UiTheme.INK, a))
	draw_multiline_string(font, panel.position + Vector2(48, 150), "会清空当前的蛋、孵化进度和照片，\n回到第一天重新来过。", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 96, UiTheme.FONT_HINT, 8, UiTheme.fade(UiTheme.INK_SOFT, a))
	var yes_press := press if press_target == "confirm_yes" else 0.0
	var no_press := press if press_target == "confirm_no" else 0.0
	UiTheme.draw_secondary_button(self, _confirm_button(1), "取消", font, no_press, a)
	UiTheme.draw_candy_button(self, _confirm_button(0), "确定重置", font, UiTheme.DANGER, UiTheme.DANGER.darkened(0.15), yes_press, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
