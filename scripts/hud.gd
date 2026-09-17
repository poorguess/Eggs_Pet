class_name Hud
extends Control

# 常驻主岛 UI。所有尺寸/位置由 scenes/hud.tscn 提供，脚本只做状态同步与信号转发。
# SafeArea(MarginContainer) 承载 Android 挖孔安全区，节点坐标一律相对安全区，
# 因此 1 个 Control 单位 = 1 个 canvas 单位（stretch/mode=canvas_items）。

signal hatch_pressed
signal face_button_pressed
signal status_pressed

const PRESS_SCALE := UiTheme.PRESS_SCALE
const PRESS_DOWN_TIME := 0.12
const PRESS_UP_TIME := 0.18

const STAT_ROWS := 4
const TOAST_DEFAULT_SECONDS := 3.0
# 原 UiTheme.draw_icon 把相机图标画在 66x66 的框里（_draw_face_button 的
# Rect2(center - Vector2(33, 33), Vector2(66, 66))）。
# Button.icon 是按纹理原始尺寸参与 get_combined_minimum_size() 的 —— camera.png 有 147x148，
# 直接挂上去会把 120x120 的 FAB 撑到 147x148；改用 expand_icon 则会让图标铺满整块按钮、
# 盖掉 StyleBoxFlat_fab 的奶油圆与粉环。所以照 draw_face_button 的比例预缩。
const FACE_ICON_SIZE := 66.0

var _margins := Vector4(16, 16, 16, 16)
var _bars: Array[ProgressBar] = []
var _values: Array[Label] = []
var _toast_left := 0.0
var _action_style_key := ""
var _press_tween: Tween

@onready var _safe_area: MarginContainer = $SafeArea
@onready var _subtitle: Label = $SafeArea/Layout/Title/Sub
@onready var _status_panel: PanelContainer = $SafeArea/Layout/StatusPanel
@onready var _creature_name: Label = $SafeArea/Layout/StatusPanel/Rows/CreatureName
@onready var _toast: Panel = $SafeArea/Layout/Toast
@onready var _toast_label: Label = $SafeArea/Layout/Toast/Label
@onready var _hatch_panel: Panel = $SafeArea/Layout/HatchPanel
@onready var _hatch_caption: Label = $SafeArea/Layout/HatchPanel/Content/Caption
@onready var _hatch_percent: Label = $SafeArea/Layout/HatchPanel/Content/Percent
@onready var _hatch_action: Button = $SafeArea/Layout/HatchPanel/Content/Action
@onready var _hatching_panel: Panel = $SafeArea/Layout/HatchingPanel
@onready var _face_button: Button = $SafeArea/Layout/FaceButton

func _ready() -> void:
	for i in range(STAT_ROWS):
		var row := _status_panel.get_node("Rows/StatRow%d" % i)
		_bars.append(row.get_node("Bar") as ProgressBar)
		_values.append(row.get_node("ValueBox/Value") as Label)
	_apply_margins()
	_fit_face_icon()
	_status_panel.gui_input.connect(_on_status_panel_gui_input)
	_hatch_action.pressed.connect(_on_hatch_action_pressed)
	_face_button.pressed.connect(_on_face_button_pressed)
	_face_button.button_down.connect(_on_face_button_down)
	_face_button.button_up.connect(_on_face_button_up)
	_face_button.resized.connect(_sync_face_button_pivot)
	_sync_face_button_pivot()

func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	if _toast_left <= 0.0:
		_toast.visible = false

# Vector4(left, top, right, bottom)，canvas 单位，来自 main_island._safe_margins()。
func set_safe_margins(m: Vector4) -> void:
	_margins = m
	_apply_margins()

func set_subtitle(text: String) -> void:
	_subtitle.text = text

func set_creature_name(text: String) -> void:
	_creature_name.text = text

# 形参刻意留成无元素类型的 Array：调用方常直接传字面量或未标注的变量，
# 而 Godot 运行时不接受 Array → Array[float] 的隐式转换（实测报 "does not have the same element type"）。
func set_stats(values: Array) -> void:
	var count := mini(values.size(), _bars.size())
	for i in range(count):
		var v := float(values[i])
		_bars[i].value = v
		_values[i].text = str(int(round(v)))

func set_stage(stage: String, hatch_progress: float, hatch_ready: bool) -> void:
	_hatch_panel.visible = stage == "egg"
	_hatching_panel.visible = stage == "hatching"
	if stage != "egg":
		return
	if hatch_ready:
		_hatch_caption.text = "可以破壳了"
		_hatch_percent.text = "100%"
		_hatch_action.text = "迎接破壳"
		_apply_action_style("ready", UiTheme.CANDY_PINK, UiTheme.CANDY_PINK_DARK)
	else:
		_hatch_caption.text = "孵化中"
		_hatch_percent.text = "%d%%" % int(floor(hatch_progress))
		_hatch_action.text = "加速 -5s"
		_apply_action_style("boost", UiTheme.SKY, UiTheme.SKY_DARK)

# duration 缺省 3s；main_island 传自己的 toast_time 即可复现原逐帧衰减的显隐时长。
func show_toast(text: String, duration: float = TOAST_DEFAULT_SECONDS) -> void:
	if duration <= 0.0:
		hide_toast()
		return
	_toast_label.text = text
	_toast.visible = true
	_toast_left = duration

func hide_toast() -> void:
	_toast_left = 0.0
	_toast.visible = false

func set_face_button_visible(shown: bool) -> void:
	_face_button.visible = shown

func _apply_margins() -> void:
	if _safe_area == null:
		return
	_safe_area.add_theme_constant_override("margin_left", int(round(_margins.x)))
	_safe_area.add_theme_constant_override("margin_top", int(round(_margins.y)))
	_safe_area.add_theme_constant_override("margin_right", int(round(_margins.z)))
	_safe_area.add_theme_constant_override("margin_bottom", int(round(_margins.w)))

# 状态面板整块可点（原文 _status_panel_rect().has_point() 命中即开详情）。
func _on_status_panel_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	if Rect2(Vector2.ZERO, _status_panel.size).has_point(event.position):
		status_pressed.emit()

func _on_hatch_action_pressed() -> void:
	hatch_pressed.emit()

func _on_face_button_pressed() -> void:
	face_button_pressed.emit()

func _sync_face_button_pivot() -> void:
	_face_button.pivot_offset = _face_button.size * 0.5

# 与 face_dialogs.gd 的 _fit_icon 同式：等比缩进正方形框内。
func _fit_face_icon() -> void:
	var icon := _face_button.icon
	if icon == null:
		return
	var source := Vector2(icon.get_size())
	var fit := FACE_ICON_SIZE / maxf(source.x, source.y)
	var target := (source * fit).round()
	if target == source:
		return
	var image := icon.get_image()
	image.resize(int(target.x), int(target.y), Image.INTERPOLATE_LANCZOS)
	_face_button.icon = ImageTexture.create_from_image(image)

func _on_face_button_down() -> void:
	_tween_face_button(PRESS_SCALE, PRESS_DOWN_TIME, Tween.TRANS_LINEAR)

func _on_face_button_up() -> void:
	_tween_face_button(1.0, PRESS_UP_TIME, Tween.TRANS_BACK)

func _tween_face_button(target: float, duration: float, trans: Tween.TransitionType) -> void:
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(_face_button, "scale", Vector2.ONE * target, duration) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)

# 按钮颜色随孵化状态切换（原 draw_candy_button 的 SKY / CANDY_PINK 两态）。
func _apply_action_style(key: String, fill: Color, edge: Color) -> void:
	if key == _action_style_key:
		return
	_action_style_key = key
	_hatch_action.add_theme_stylebox_override("normal", _candy_style(fill, edge, false))
	_hatch_action.add_theme_stylebox_override("hover", _candy_style(fill, edge, false))
	_hatch_action.add_theme_stylebox_override("pressed", _candy_style(fill, edge, true))
	_hatch_action.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# 与 ui/theme.tres 的 btn_normal / btn_pressed 同几何：药丸 + 底部 4px 深边，按下时文字下沉。
static func _candy_style(fill: Color, edge: Color, press: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_right = 999
	style.corner_radius_bottom_left = 999
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 22 if press else 18
	style.content_margin_bottom = 14 if press else 18
	if not press:
		style.border_width_bottom = int(UiTheme.BUTTON_EDGE)
		style.border_color = edge
	return style
