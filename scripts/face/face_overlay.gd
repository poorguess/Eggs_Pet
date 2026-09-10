class_name PetFaceOverlay
extends Node2D

const MeshBuilder = preload("res://scripts/face/face_mesh.gd")
var target: Sprite2D
var track: PetFaceTrack
var profile: PetFaceProfile
var texture: Texture2D
var _builder := MeshBuilder.new()
var _mesh: ArrayMesh
var _frame: int = -1

func configure(sprite: Sprite2D, data: PetFaceTrack, face: Texture2D, settings: PetFaceProfile) -> String:
	var error := data.validate()
	if not error.is_empty():
		visible = false
		return error
	target = sprite
	track = data
	texture = face
	profile = settings
	_builder.configure(track.get_contour(0))
	_frame = -1
	sync()
	return ""

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	if target == null or track == null or texture == null:
		return
	visible = target.visible and not track.hidden_frames.has(target.frame)
	scale = Vector2(-1 if target.flip_h else 1, -1 if target.flip_v else 1)
	position = target.offset * scale
	if target.centered:
		position -= track.frame_size * 0.5 * scale
	if _frame != target.frame:
		_frame = target.frame
		_mesh = _builder.build(track.get_contour(_frame), profile.alignment(track.get_contour(0)))
		queue_redraw()

func _draw() -> void:
	if _mesh != null and texture != null:
		draw_mesh(_mesh, texture)
