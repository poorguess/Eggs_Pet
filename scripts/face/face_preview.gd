extends Control

const MeshBuilder = preload("res://scripts/face/face_mesh.gd")
var track: PetFaceTrack
var profile: PetFaceProfile
var face: Texture2D
# 本机合成的整帧成品图；设置后优先于"底帧 + 五官贴层"显示。
var composite: Texture2D
var _builder := MeshBuilder.new()
var _body: Texture2D
var _mesh: ArrayMesh

func configure(data: PetFaceTrack, settings: PetFaceProfile, texture: Texture2D) -> void:
	track = data
	profile = settings
	face = texture
	composite = null
	_body = track.frame_texture(0)
	_builder.configure(track.get_contour(0))
	refresh()

func refresh() -> void:
	if track != null:
		_mesh = _builder.build(track.get_contour(0), profile.alignment(track.get_contour(0)))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("e5e9ed"))
	if composite != null:
		var frame := composite.get_size()
		var factor := minf((size.x - 40) / frame.x, (size.y - 40) / frame.y)
		var origin := (size - frame * factor) * 0.5
		draw_set_transform(origin, 0, Vector2.ONE * factor)
		draw_texture_rect(composite, Rect2(Vector2.ZERO, frame), false)
		draw_set_transform(Vector2.ZERO)
		return
	if _body == null:
		return
	var factor := minf((size.x - 40) / track.frame_size.x, (size.y - 40) / track.frame_size.y)
	var origin := (size - track.frame_size * factor) * 0.5
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	draw_texture_rect(_body, Rect2(Vector2.ZERO, track.frame_size), false)
	if face != null and _mesh != null:
		draw_mesh(_mesh, face)
	draw_set_transform(Vector2.ZERO)
