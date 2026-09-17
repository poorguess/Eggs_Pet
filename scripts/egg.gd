class_name Egg
extends Node2D

# 蛋阶段：精灵表切帧 + 按动作名播放（设计红线 6，换帧动画资产不改照护逻辑）。
# 本场景只管呈现；存档、care / growth、何时孵化、何时切换宠物全部由 main_island 决定。

const IDLE_SHEET := "res://assets/eggs_pics/Eggidle.png"
const BROKEN_SHEET := "res://assets/eggs_pics/Eggbroken.png"
const SHEET_COLUMNS := 4
const IDLE_ROWS := 14
const BROKEN_ROWS := 15
const IDLE_FPS := 8.0
const BROKEN_FPS := 12.0

const ACTION_IDLE := &"idle"
const ACTION_BROKEN := &"broken"

# 蛋在画布中的落点：中心上移 70，给底部照护 UI 留空间（沿用原 main_island）。
const CENTER_OFFSET := Vector2(0.0, -70.0)
const BOB_AMPLITUDE := 3.0

signal animation_finished(anim_name: StringName)

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hatch_glow: HatchGlow = $HatchGlow

var _elapsed := 0.0

func _ready() -> void:
	sprite.sprite_frames = _build_animations()
	sprite.animation_finished.connect(_on_sprite_animation_finished)
	_layout()
	play(ACTION_IDLE)
	get_viewport().size_changed.connect(_layout)

func _process(delta: float) -> void:
	_elapsed += delta
	if sprite.animation == ACTION_IDLE:
		sprite.position.y = sin(_elapsed * PI) * BOB_AMPLITUDE
	else:
		sprite.position.y = 0.0

# 按动作名播放。重复请求同一动作时保留当前进度，避免调用方每帧调用把动画钉在第 0 帧。
func play(action: StringName) -> void:
	if not sprite.sprite_frames.has_animation(action):
		push_error("Unknown egg action: %s" % action)
		return
	if sprite.animation == action and sprite.is_playing():
		return
	sprite.play(action)

# 蛋壳本体可见性；破壳光晕不随之隐藏（孵化后仍要在宠物阶段把闪光播完）。
func set_shell_visible(shell_visible: bool) -> void:
	sprite.visible = shell_visible

func play_hatch_glow() -> void:
	hatch_glow.play_burst()

func _layout() -> void:
	# 节点已出树、queue_free 还没执行时仍会收到 size_changed，那时 get_viewport() 是 null。
	if not is_inside_tree():
		return
	position = get_viewport().get_visible_rect().size * 0.5 + CENTER_OFFSET

func _on_sprite_animation_finished() -> void:
	animation_finished.emit(sprite.animation)

func _build_animations() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_sheet_animation(frames, ACTION_IDLE, IDLE_SHEET, IDLE_ROWS, IDLE_FPS, true)
	_add_sheet_animation(frames, ACTION_BROKEN, BROKEN_SHEET, BROKEN_ROWS, BROKEN_FPS, false)
	return frames

func _add_sheet_animation(frames: SpriteFrames, name: StringName, path: String, rows: int, fps: float, loop: bool) -> void:
	var sheet := load(path) as Texture2D
	if sheet == null:
		push_error("Could not load egg animation sheet: " + path)
		return
	frames.add_animation(name)
	frames.set_animation_speed(name, fps)
	frames.set_animation_loop(name, loop)
	var frame_width := sheet.get_width() / SHEET_COLUMNS
	var frame_height := float(sheet.get_height()) / rows
	for row in range(rows):
		for column in range(SHEET_COLUMNS):
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(column * frame_width, row * frame_height, frame_width, frame_height)
			frames.add_frame(name, frame)
