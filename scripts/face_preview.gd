class_name FacePreview
extends Control

# 自拍取景覆盖层。相机画面用 TextureRect 的 KEEP_ASPECT_COVERED 复刻原
# main_island.gd `_draw_face_preview()` 的 draw_texture_rect_region 中心裁切：
# 两者都是「取源图中央一块与视口同宽高比的区域，等比缩放到铺满视口」。

signal shutter_pressed
signal close_pressed

const SHUTTER_SIZE := 176.0
const SHUTTER_INSET := 40.0
const SHUTTER_SHADOW_DROP := 8.0
const CLOSE_SIZE := 96.0
const CLOSE_INSET := 32.0
const HINT_HEIGHT := 40.0
const HINT_GAP := 64.0
# 环心在视口高度的 42% 处，半径取短边的 32%。
const RING_CENTER_Y_RATIO := 0.42
const RING_RADIUS_RATIO := 0.32
const DEFAULT_MARGINS := Vector4(16.0, 16.0, 16.0, 16.0)

@onready var _backdrop: ColorRect = $Backdrop
@onready var _camera: TextureRect = $Camera
@onready var _viewfinder: Control = $Viewfinder
@onready var _hint: Label = $Hint
@onready var _shutter_shadow: Panel = $ShutterShadow
@onready var _shutter: Button = $Shutter
@onready var _close_button: Button = $Close

var _margins := DEFAULT_MARGINS
var _shutter_tween: Tween

func _ready() -> void:
	_backdrop.color = UiTheme.INK.darkened(0.55)
	_viewfinder.draw.connect(_on_viewfinder_draw)
	_shutter.pressed.connect(func() -> void: shutter_pressed.emit())
	_close_button.pressed.connect(func() -> void: close_pressed.emit())
	_shutter.button_down.connect(_on_shutter_down)
	_shutter.button_up.connect(_on_shutter_up)
	resized.connect(_relayout)
	_relayout()
	close()

func set_frame(texture: ImageTexture) -> void:
	_camera.texture = texture

func open() -> void:
	_relayout()
	visible = true

func close() -> void:
	visible = false

func set_safe_margins(m: Vector4) -> void:
	_margins = m
	_relayout()

func _relayout() -> void:
	var shutter_pos := Vector2((size.x - SHUTTER_SIZE) * 0.5, size.y - _margins.w - SHUTTER_INSET - SHUTTER_SIZE)
	_shutter.position = shutter_pos
	_shutter.pivot_offset = Vector2(SHUTTER_SIZE, SHUTTER_SIZE) * 0.5
	# 阴影相对快门下移 8px；轴心同步上移，使缩放仍以快门圆心为中心（同原绘制）。
	_shutter_shadow.position = shutter_pos + Vector2(0.0, SHUTTER_SHADOW_DROP)
	_shutter_shadow.pivot_offset = Vector2(SHUTTER_SIZE, SHUTTER_SIZE) * 0.5 - Vector2(0.0, SHUTTER_SHADOW_DROP)
	_close_button.position = Vector2(_margins.x + CLOSE_INSET, _margins.y + CLOSE_INSET)
	var hint_y := shutter_pos.y - HINT_GAP
	_hint.offset_top = hint_y
	_hint.offset_bottom = hint_y + HINT_HEIGHT
	_viewfinder.queue_redraw()

func _on_viewfinder_draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * RING_CENTER_Y_RATIO)
	var radius := minf(size.x, size.y) * RING_RADIUS_RATIO
	_viewfinder.draw_arc(center, radius + 8.0, 0.0, TAU, 96, UiTheme.fade(UiTheme.INK, 0.25), 14.0)
	_viewfinder.draw_arc(center, radius, 0.0, TAU, 96, UiTheme.fade(UiTheme.CREAM, 0.9), 4.0)

func _on_shutter_down() -> void:
	_scale_shutter(UiTheme.PRESS_SCALE, 0.12, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)

func _on_shutter_up() -> void:
	_scale_shutter(1.0, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT)

func _scale_shutter(target: float, time: float, trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	if _shutter_tween != null:
		_shutter_tween.kill()
	_shutter_tween = create_tween().set_parallel()
	var parts: Array[Control] = [_shutter, _shutter_shadow]
	for part in parts:
		_shutter_tween.tween_property(part, "scale", Vector2(target, target), time).set_trans(trans).set_ease(ease)
