extends Node2D
class_name Pet

const SHEET := preload("res://assets/pets/character1.png")
const HFRAMES := 4
const VFRAMES := 9
const FRAME_COUNT := 33

@export var roam_center := Vector2(960, 400)
@export var roam_radius := Vector2(520, 190)
@export var pet_scale := 0.45
@export var default_faces_left := true
@export var walk_speed_min := 60.0
@export var walk_speed_max := 90.0
@export var idle_fps := 8.0
@export var walk_fps := 10.0

var sprite: Sprite2D
var features: PetFaceOverlay
var _state := "idle"
var _fps := 8.0
var _frame_clock := 0.0
var _wait := 0.0
var _target := Vector2.ZERO
var _speed := 70.0

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = SHEET
	sprite.hframes = HFRAMES
	sprite.vframes = VFRAMES
	sprite.frame = 0
	add_child(sprite)
	scale = Vector2.ONE * pet_scale
	position = roam_center
	play_idle()

func _process(delta: float) -> void:
	_frame_clock += delta
	var step := 1.0 / _fps
	while _frame_clock >= step:
		_frame_clock -= step
		sprite.frame = (sprite.frame + 1) % FRAME_COUNT
	if _state == "walk":
		var to_target := _target - position
		var move := _speed * delta
		if to_target.length() <= move:
			position = _target
			play_idle()
		else:
			position += to_target.normalized() * move
			var d := _ellipse_distance(position)
			if d >= 1.0:
				position = roam_center + (position - roam_center) / d
				play_walk()
	else:
		_wait -= delta
		if _wait <= 0.0:
			play_walk()

func _ellipse_distance(p: Vector2) -> float:
	return ((p - roam_center) / roam_radius).length()

# 换脸烘焙结果只替换纹理像素；帧网格、帧动画、漫游、转向逻辑全部不变。
# 烘焙表与原始 SHEET 同尺寸，Sprite2D 的帧切分区域无需任何调整。
func apply_look_sheet(sheet_image: Image) -> void:
	sprite.texture = ImageTexture.create_from_image(sheet_image)

# 五官贴层取代烘焙外观时，恢复默认精灵表纹理。
func reset_look() -> void:
	sprite.texture = SHEET

func play_idle() -> void:
	_state = "idle"
	_fps = idle_fps
	_wait = randf_range(1.0, 3.0)

func play_walk() -> void:
	var angle := randf() * TAU
	var reach := randf_range(0.3, 0.85)
	_target = roam_center + Vector2(cos(angle) * roam_radius.x, sin(angle) * roam_radius.y) * reach
	_speed = randf_range(walk_speed_min, walk_speed_max)
	sprite.flip_h = (_target.x > position.x) == default_faces_left
	_state = "walk"
	_fps = walk_fps

func apply_features(texture: Texture2D, profile: PetFaceProfile, track: PetFaceTrack) -> String:
	if features == null:
		features = PetFaceOverlay.new()
		sprite.add_child(features)
	return features.configure(sprite, track, texture, profile)
