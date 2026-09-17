extends Control

const ISLAND_SCENE := "res://scenes/main_island.tscn"

const BUTTON_SIZE := Vector2(320.0, 88.0)
const DIALOG_SIZE := Vector2(640.0, 420.0)
const DIALOG_TITLE_TOP := 56.0
const DIALOG_BODY_BASELINE := 150.0
const DIALOG_FROSTING_HEIGHT := 12.0

@onready var _title: Label = $Title
@onready var _tagline: Label = $Tagline
@onready var _blurb: Label = $Blurb
@onready var _egg: Sprite2D = $Egg
@onready var _shadow: Polygon2D = $EggShadow
@onready var _save_prompt: Label = $SavePrompt
@onready var _fresh_prompt: Label = $FreshPrompt
@onready var _secondary_button: Button = $SecondaryButton
@onready var _primary_button: Button = $PrimaryButton
@onready var _start_button: Button = $StartButton
@onready var _footer: Label = $Footer
@onready var _overlay: Control = $ConfirmOverlay
@onready var _dialog: Panel = $ConfirmOverlay/DialogPanel
@onready var _frosting: Panel = $ConfirmOverlay/DialogPanel/Frosting
@onready var _dialog_title: Label = $ConfirmOverlay/DialogPanel/DialogTitle
@onready var _dialog_body: Label = $ConfirmOverlay/DialogPanel/DialogBody
@onready var _cancel_button: Button = $ConfirmOverlay/DialogPanel/CancelButton
@onready var _confirm_button: Button = $ConfirmOverlay/DialogPanel/ConfirmButton

var has_save := false
var confirm_reset := false
var dialog_anim := 1.0

var _float_clock := 0.0
var _dialog_tween: Tween


func _ready() -> void:
	has_save = FileAccess.file_exists(SaveService.PATH)
	_start_button.pressed.connect(_open_island)
	_primary_button.pressed.connect(_open_island)
	_secondary_button.pressed.connect(_show_reset_confirm)
	_confirm_button.pressed.connect(_do_reset)
	_cancel_button.pressed.connect(_cancel_reset)
	resized.connect(_layout)
	_apply_state()
	_layout()


func _exit_tree() -> void:
	if _dialog_tween:
		_dialog_tween.kill()


func _process(delta: float) -> void:
	_float_clock += delta
	_place_egg()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_SPACE] and not confirm_reset:
			_open_island()
		if event.keycode == KEY_ESCAPE and confirm_reset:
			_cancel_reset()


func _layout() -> void:
	var canvas := size
	var m := _safe_margins()

	var header := canvas.y * 0.16
	_place_baseline(_title, header)
	_place_baseline(_tagline, header + 52.0)
	_place_baseline(_blurb, header + 96.0)

	_place_egg()

	var row_y := canvas.y - m.w - 96.0 - 88.0
	_secondary_button.position = Vector2(canvas.x * 0.5 - 16.0 - BUTTON_SIZE.x, row_y)
	_primary_button.position = Vector2(canvas.x * 0.5 + 16.0, row_y)
	_start_button.position = Vector2(canvas.x * 0.5 - BUTTON_SIZE.x * 0.5, row_y)
	for button: Button in [_secondary_button, _primary_button, _start_button]:
		button.size = BUTTON_SIZE
	_place_baseline(_save_prompt, row_y - 32.0)
	_place_baseline(_fresh_prompt, row_y - 32.0)
	_place_baseline(_footer, canvas.y - m.w - 40.0)

	_dialog.position = (canvas - DIALOG_SIZE) * 0.5
	_dialog.size = DIALOG_SIZE
	_dialog.pivot_offset = DIALOG_SIZE * 0.5
	_frosting.size = Vector2(DIALOG_SIZE.x, DIALOG_FROSTING_HEIGHT)
	_place_baseline(_dialog_title, DIALOG_TITLE_TOP + _ascent(_dialog_title))
	_place_baseline(_dialog_body, DIALOG_BODY_BASELINE)
	# 弹窗正文是两行：把矩形下边补到能容纳第二行，避免编辑器里看起来被裁切。
	_dialog_body.offset_bottom += _line_step(_dialog_body)
	var dialog_button_y := DIALOG_SIZE.y - 40.0 - 88.0
	_cancel_button.position = Vector2(48.0, dialog_button_y)
	_confirm_button.position = Vector2(DIALOG_SIZE.x - 48.0 - 260.0, dialog_button_y)
	for button: Button in [_cancel_button, _confirm_button]:
		button.size = Vector2(260.0, 88.0)

	_apply_dialog_anim()


# 原 _draw() 用 draw_string 的 baseline 定位，Control 需要换算成矩形上下边。
func _place_baseline(label: Label, baseline_y: float) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	label.offset_top = baseline_y - font.get_ascent(font_size)
	label.offset_bottom = baseline_y + font.get_descent(font_size)


func _ascent(label: Label) -> float:
	var font := label.get_theme_font("font")
	return font.get_ascent(label.get_theme_font_size("font_size"))


# 一行占的高度（含 line_spacing），与原 draw_multiline_string 的换行步进一致。
func _line_step(label: Label) -> float:
	var font := label.get_theme_font("font")
	return font.get_height(label.get_theme_font_size("font_size")) + label.get_theme_constant("line_spacing")


func _place_egg() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5 + sin(_float_clock * PI) * 3.0)
	_egg.position = center
	_shadow.position = Vector2(size.x * 0.5, center.y + _egg.texture.get_height() * _egg.scale.y * 0.5 + 20.0)


func _apply_state() -> void:
	_start_button.visible = not has_save
	_primary_button.visible = has_save
	_secondary_button.visible = has_save
	_save_prompt.visible = has_save
	_fresh_prompt.visible = not has_save
	_overlay.visible = confirm_reset
	_egg.visible = not confirm_reset


func _apply_dialog_anim() -> void:
	var s := 0.8 + 0.2 * dialog_anim
	_dialog.scale = Vector2(s, s)
	_dialog.modulate.a = clampf(dialog_anim, 0.0, 1.0)


func _open_island() -> void:
	get_tree().change_scene_to_file(ISLAND_SCENE)


func _show_reset_confirm() -> void:
	confirm_reset = true
	if _dialog_tween:
		_dialog_tween.kill()
	dialog_anim = 0.0
	_dialog_tween = create_tween()
	_dialog_tween.tween_method(_set_dialog_anim, 0.0, 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_apply_state()


func _cancel_reset() -> void:
	confirm_reset = false
	_apply_state()


func _do_reset() -> void:
	SaveService.reset()
	has_save = false
	confirm_reset = false
	_apply_state()


func _set_dialog_anim(value: float) -> void:
	dialog_anim = value
	_apply_dialog_anim()


# Vector4(left, top, right, bottom)，canvas 单位，每边至少 16。
func _safe_margins() -> Vector4:
	var canvas := size
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
