class_name FaceDialogs
extends Control

# 自拍换脸弹窗：consent / confirm / processing / error 四态。
# 几何沿用原 main_island.gd 的 _draw_face_overlay 系列 —— 面板 760x560 居中，
# 内容坐标以面板左上角为原点，与 _draw_face_consent 等函数的 panel.position 偏移一一对应。

signal consent_accepted
signal cancelled
signal confirm_accepted
signal confirm_retake
signal error_retry
signal error_closed

const MODE_CONSENT := "consent"
const MODE_CONFIRM := "confirm"
const MODE_PROCESSING := "processing"
const MODE_ERROR := "error"

const PANEL_SIZE := Vector2(760.0, 560.0)
# 原实现入场缩放 s = 0.8 + 0.2 * _dialog_anim。
const ENTRY_SCALE := 0.8
const ENTRY_TIME := 0.25
# 原实现把说明文字的首行基线放在面板内 y=160 处（标题的 64 已直接写进 tscn 的 offset_top）。
const HINT_BASELINE := 160.0
const PROCESSING_TEXT := "正在融合你的五官"
# 原 UiTheme.draw_icon 把按钮图标按比例塞进 36 x (按钮高 - 底边) 的框里。
# Button.icon 是按「纹理原始尺寸」参与 get_combined_minimum_size() 的，直接用上百像素的源图
# 会把 280x88 的按钮撑到 351x193 并溢出面板，所以这里先按与 draw_icon 相同的比例预缩，
# 顺带避免每帧 GPU 缩图的锯齿。
const ICON_BOX_WIDTH := 36.0
const ICON_BOX_HEIGHT := 84.0
# processing 态旋转弧：半径 36、线宽 10、扫过 4.2 rad、24 段。
const SPIN_RADIUS := 36.0
const SPIN_WIDTH := 10.0
const SPIN_SWEEP := 4.2
const SPIN_SEGMENTS := 24

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _frosting: Panel = $Panel/Body/Frosting
@onready var _close_button: Button = $Panel/Body/CloseButton
@onready var _consent: Control = $Panel/Body/Consent
@onready var _confirm: Control = $Panel/Body/Confirm
@onready var _processing: Control = $Panel/Body/Processing
@onready var _error: Control = $Panel/Body/Error
@onready var _consent_hint: Label = $Panel/Body/Consent/Hint
@onready var _confirm_photo: TextureRect = $Panel/Body/Confirm/Photo
@onready var _error_title: Label = $Panel/Body/Error/Title
@onready var _error_hint: Label = $Panel/Body/Error/Hint
@onready var _processing_spinner: Control = $Panel/Body/Processing/Spinner
@onready var _processing_text: Label = $Panel/Body/Processing/Text

var _mode := ""
var _entry_tween: Tween

func _ready() -> void:
	_dim.color = UiTheme.DIM
	# 原 _draw_face_error 的标题用 DANGER，其余态用 INK（theme 默认）。
	_error_title.add_theme_color_override("font_color", UiTheme.DANGER)
	_align_baselines()
	_fit_icon($Panel/Body/Confirm/Primary)
	_fit_icon($Panel/Body/Confirm/Secondary)
	_processing_spinner.draw.connect(_on_spinner_draw)
	$Panel/Body/Consent/Primary.pressed.connect(_on_consent_primary)
	$Panel/Body/Consent/Secondary.pressed.connect(_on_cancelled)
	$Panel/Body/Confirm/Primary.pressed.connect(_on_confirm_primary)
	$Panel/Body/Confirm/Secondary.pressed.connect(_on_confirm_retake)
	$Panel/Body/Error/Primary.pressed.connect(_on_error_retry)
	$Panel/Body/Error/Secondary.pressed.connect(_on_error_closed)
	_close_button.pressed.connect(_on_close_pressed)
	hide_dialog()

# 与 UiTheme.draw_icon 同式：按比例缩到 36 x 84 的框内，正方形源图得到 36x36。
func _fit_icon(button: Button) -> void:
	if button.icon == null:
		return
	var source := Vector2(button.icon.get_size())
	var fit := minf(ICON_BOX_WIDTH / source.x, ICON_BOX_HEIGHT / source.y)
	var target := (source * fit).round()
	if target == source:
		return
	var image := button.icon.get_image()
	image.resize(int(target.x), int(target.y), Image.INTERPOLATE_LANCZOS)
	button.icon = ImageTexture.create_from_image(image)

# 原实现用 draw_string / draw_multiline_string 定位文本「基线」，Label 定位的是行框顶端：
#   - 标题：原式传的是 `64 + font.get_ascent()`，即 Label 顶端正好落在 64，无需补偿；
#   - 说明：原式传的是 160（首行基线），Label 顶端要上移一个 ascent。
func _align_baselines() -> void:
	_align_baseline(_consent_hint, HINT_BASELINE)
	_align_baseline(_error_hint, HINT_BASELINE)

func _align_baseline(label: Label, baseline_y: float) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	label.position.y = baseline_y - font.get_ascent(font_size)

func show_consent() -> void:
	_show(MODE_CONSENT)

func show_confirm(photo: Texture2D) -> void:
	_confirm_photo.texture = photo
	_show(MODE_CONFIRM)

func show_processing() -> void:
	_show(MODE_PROCESSING)

func show_error(message: String) -> void:
	_error_hint.text = message + "\n检查网络后可以重试。"
	_show(MODE_ERROR)

func hide_dialog() -> void:
	_mode = ""
	visible = false
	set_process(false)
	if _entry_tween != null:
		_entry_tween.kill()

func _show(mode: String) -> void:
	# 与原 _set_face_mode 一致：同模式重复调用只更新内容，不重播入场动画。
	if _mode == mode and visible:
		return
	_mode = mode
	_consent.visible = mode == MODE_CONSENT
	_confirm.visible = mode == MODE_CONFIRM
	_processing.visible = mode == MODE_PROCESSING
	_error.visible = mode == MODE_ERROR
	_close_button.visible = mode != MODE_PROCESSING
	_apply_frosting(mode)
	set_process(mode == MODE_PROCESSING)
	if mode == MODE_PROCESSING:
		_refresh_processing()
	visible = true
	_play_entry()

func _apply_frosting(mode: String) -> void:
	var tint := UiTheme.CANDY_PINK
	match mode:
		MODE_PROCESSING:
			tint = UiTheme.SKY
		MODE_ERROR:
			tint = UiTheme.DANGER
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	# 只有上沿需要跟着面板圆角，下沿是直线。
	style.corner_radius_top_left = int(UiTheme.RADIUS_PANEL)
	style.corner_radius_top_right = int(UiTheme.RADIUS_PANEL)
	_frosting.add_theme_stylebox_override("panel", style)

func _play_entry() -> void:
	if _entry_tween != null:
		_entry_tween.kill()
	_panel.pivot_offset = PANEL_SIZE * 0.5
	_panel.scale = Vector2(ENTRY_SCALE, ENTRY_SCALE)
	_panel.modulate.a = 0.0
	_entry_tween = create_tween().set_parallel()
	_entry_tween.tween_property(_panel, "scale", Vector2.ONE, ENTRY_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_panel, "modulate:a", 1.0, ENTRY_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	_refresh_processing()

func _refresh_processing() -> void:
	var msec := Time.get_ticks_msec()
	_processing_text.text = PROCESSING_TEXT + ".".repeat(int(msec / 400) % 4)
	_processing_spinner.queue_redraw()

func _on_spinner_draw() -> void:
	var spin := Time.get_ticks_msec() / 300.0
	_processing_spinner.draw_arc(_processing_spinner.size * 0.5, SPIN_RADIUS, spin, spin + SPIN_SWEEP, SPIN_SEGMENTS, UiTheme.SKY, SPIN_WIDTH)

func _on_consent_primary() -> void:
	consent_accepted.emit()

func _on_confirm_primary() -> void:
	confirm_accepted.emit()

func _on_confirm_retake() -> void:
	confirm_retake.emit()

func _on_error_retry() -> void:
	error_retry.emit()

func _on_cancelled() -> void:
	cancelled.emit()

func _on_error_closed() -> void:
	error_closed.emit()

# × 在 error 态等价于「取消」按钮（原 _close_face_error），其余态等价于取消整条流程。
func _on_close_pressed() -> void:
	if _mode == MODE_ERROR:
		error_closed.emit()
	else:
		cancelled.emit()
