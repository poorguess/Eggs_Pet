@tool
extends Control

signal edited(points: PackedVector2Array)
var texture: Texture2D
var points := PackedVector2Array()
var active: int = 0
var move_all: bool = false
var _dragging: bool = false
var _last := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(300, 360)
	resized.connect(queue_redraw)

func image_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var factor := minf(size.x / texture.get_width(), size.y / texture.get_height())
	var dimensions := texture.get_size() * factor
	return Rect2((size - dimensions) * 0.5, dimensions)

func _gui_input(event: InputEvent) -> void:
	if texture == null or points.is_empty():
		return
	var rect := image_rect()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and rect.has_point(event.position)
		if _dragging:
			_last = (event.position - rect.position) / rect.size * texture.get_size()
			if not move_all:
				var nearest := -1
				var distance := 14.0
				for i: int in points.size():
					var screen := rect.position + points[i] / texture.get_size() * rect.size
					if screen.distance_to(event.position) < distance:
						distance = screen.distance_to(event.position)
						nearest = i
				if nearest >= 0:
					active = nearest
				else:
					points[active] = _last
					edited.emit(points)
			queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var point: Vector2 = ((event.position - rect.position) / rect.size * texture.get_size()).clamp(Vector2.ZERO, texture.get_size() - Vector2.ONE)
		if move_all:
			for i: int in points.size():
				points[i] += point - _last
		else:
			points[active] = point
		_last = point
		edited.emit(points)
		queue_redraw()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("303945"))
	if texture == null:
		return
	var rect := image_rect()
	draw_texture_rect(texture, rect, false)
	var polygon := PackedVector2Array()
	for point: Vector2 in points:
		polygon.append(rect.position + point / texture.get_size() * rect.size)
	if polygon.size() > 2:
		polygon.append(polygon[0])
		draw_polyline(polygon, Color.CYAN, 2, true)
	for i: int in points.size():
		var point := polygon[i]
		draw_circle(point, 5, Color.YELLOW if i == active else Color.CYAN)
		draw_string(ThemeDB.fallback_font, point + Vector2(7, -7), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
