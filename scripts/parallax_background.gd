extends Node2D

@export var base_speed := 80.0
@export var viewport_padding := 24.0

var _layers: Array[Dictionary] = []
var _elapsed_time := 0.0

func _ready() -> void:
	_layers = [
		{
			"path": "res://assets/background/BackGround.png",
			"motion": "scroll",
			"speed": 0.18,
			"z_index": 0,
			"y_anchor": 0.5,
		},
		{
			"path": "res://assets/background/Middle.png",
			"motion": "float",
			"speed": 0.0,
			"float_amplitude": 5.0,
			"float_cycle_seconds": 6.4,
			"z_index": 1,
			"y_anchor": 0.5,
		},
		{
			"path": "res://assets/background/low.png",
			"motion": "float",
			"speed": 0.0,
			"float_amplitude": 8.0,
			"float_cycle_seconds": 3.6,
			"z_index": 2,
			"y_anchor": 0.5,
		},
	]

	_build_layers()
	get_viewport().size_changed.connect(_layout_layers)

func _process(delta: float) -> void:
	_elapsed_time += delta

	for layer in _layers:
		if not layer.has("sprites") or not layer.has("width"):
			continue

		var motion_type := String(layer["motion"])
		var sprites: Array = layer["sprites"]

		if motion_type == "float":
			_float_layer(layer, sprites)
			continue
		if motion_type != "scroll":
			continue

		var width: float = layer["width"]
		var speed_multiplier := float(layer["speed"])
		var motion: float = base_speed * speed_multiplier * delta

		for sprite in sprites:
			sprite.position.x += motion

		if sprites[1].position.x >= width:
			sprites[1].position.x = sprites[0].position.x - width
			sprites.reverse()

func _float_layer(layer: Dictionary, sprites: Array) -> void:
	var cycle_seconds: float = max(float(layer["float_cycle_seconds"]), 0.1)
	var phase: float = _elapsed_time / cycle_seconds * TAU
	var y_offset: float = sin(phase) * float(layer["float_amplitude"])

	for sprite in sprites:
		sprite.position.y = float(layer["base_y"]) + y_offset

func _build_layers() -> void:
	for layer in _layers:
		var texture := _load_texture(layer["path"])
		if texture == null:
			push_error("Missing parallax texture: %s" % layer["path"])
			continue

		var sprites: Array[Sprite2D] = []
		for index in range(2):
			var sprite := Sprite2D.new()
			sprite.name = "%s_%d" % [layer["path"].get_file().get_basename(), index + 1]
			sprite.centered = false
			sprite.texture = texture
			sprite.z_index = layer["z_index"]
			add_child(sprite)
			sprites.append(sprite)

		layer["sprites"] = sprites

	_layout_layers()

func _load_texture(path: String) -> Texture2D:
	var imported_texture := load(path) as Texture2D
	if imported_texture != null:
		return imported_texture

	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		return null

	return ImageTexture.create_from_image(image)

func _layout_layers() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	for layer in _layers:
		if not layer.has("sprites"):
			continue

		var sprites: Array = layer["sprites"]
		var texture_size: Vector2 = sprites[0].texture.get_size()
		var scale_factor: float = max(
			(viewport_size.x + viewport_padding) / texture_size.x,
			(viewport_size.y + viewport_padding) / texture_size.y
		)
		var layer_width: float = texture_size.x * scale_factor
		var layer_height: float = texture_size.y * scale_factor
		var y: float = (viewport_size.y - layer_height) * float(layer["y_anchor"])

		layer["width"] = layer_width
		layer["base_y"] = y

		for index in range(sprites.size()):
			sprites[index].scale = Vector2.ONE * scale_factor
			sprites[index].position = Vector2((index - 1) * layer_width, y)
