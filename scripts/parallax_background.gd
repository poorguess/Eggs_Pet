extends Node2D

# 浮空小岛背景：Sky（渐变铺满全屏）+ Island（地图等比适配）。
# 地图资产 3000x3626，竖屏 9:16 下 contain 适配会留出上下天空带，天空由 Sky 补足。

const FIT_CONTAIN := "contain"
const FIT_COVER := "cover"
# 覆盖 1920 画布高度，默认线性过滤下无色带
const GRADIENT_STEPS := 256

@export_enum("contain", "cover") var fit_mode: String = FIT_CONTAIN
@export_range(0.0, 1.0) var island_y_anchor: float = 0.5
@export var sky_top: Color = UiTheme.SKY_TOP
@export var sky_bottom: Color = UiTheme.SKY_BOTTOM

@onready var sky: TextureRect = $Sky
@onready var island: Sprite2D = $Island

func _ready() -> void:
	_apply_sky_gradient()
	_layout()
	get_viewport().size_changed.connect(_layout)

# 按导出色重建渐变，避免多实例共享场景内 SubResource 而互相污染。
func _apply_sky_gradient() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, sky_top)
	gradient.set_color(1, sky_bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = GRADIENT_STEPS
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	sky.texture = texture

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# Control 挂在 Node2D 下时锚点参照的父矩形为空（实测 1080x1920 视口下 Sky 尺寸仍是 0x0），
	# 铺满全屏改由脚本按视口写 offset；直接改 size 会触发引擎的锚点警告。
	sky.position = Vector2.ZERO
	sky.offset_right = viewport_size.x
	sky.offset_bottom = viewport_size.y

	if island.texture == null:
		return

	var texture_size := island.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var fit := minf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	if fit_mode == FIT_COVER:
		fit = maxf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)

	var island_size := texture_size * fit
	island.scale = Vector2.ONE * fit
	island.position = Vector2(
		(viewport_size.x - island_size.x) * 0.5,
		(viewport_size.y - island_size.y) * island_y_anchor
	)
