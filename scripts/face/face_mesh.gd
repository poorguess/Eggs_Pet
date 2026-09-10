@tool
class_name PetFaceMesh
extends RefCounted

const Track = preload("res://scripts/face/face_track.gd")
const RINGS: int = 6
var reference := PackedVector2Array()
var vertices := PackedVector2Array()
var weights: Array[PackedFloat32Array] = []
var indices := PackedInt32Array()

func configure(contour: PackedVector2Array) -> void:
	reference = contour
	vertices.clear()
	weights.clear()
	indices.clear()
	var origin := Track.center(contour)
	vertices.append(origin)
	var n := contour.size()
	for ring: int in range(1, RINGS + 1):
		for point: Vector2 in contour:
			vertices.append(origin.lerp(point, float(ring) / RINGS))
	for point: Vector2 in vertices:
		weights.append(mean_value_weights(point, contour))
	for i: int in n:
		indices.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % n]))
	for ring: int in range(1, RINGS):
		var inner := 1 + (ring - 1) * n
		var outer := inner + n
		for i: int in n:
			var j := (i + 1) % n
			indices.append_array(PackedInt32Array([inner + i, outer + i, outer + j, inner + i, outer + j, inner + j]))

static func mean_value_weights(point: Vector2, contour: PackedVector2Array) -> PackedFloat32Array:
	var n := contour.size()
	var result := PackedFloat32Array()
	result.resize(n)
	for i: int in n:
		if point.distance_to(contour[i]) < 0.0001:
			result[i] = 1.0
			return result
	var half_tangents := PackedFloat32Array()
	for i: int in n:
		var a := contour[i] - point
		var b := contour[(i + 1) % n] - point
		half_tangents.append(tan(a.angle_to(b) * 0.5))
	var total := 0.0
	for i: int in n:
		result[i] = (half_tangents[(i + n - 1) % n] + half_tangents[i]) / point.distance_to(contour[i])
		total += result[i]
	for i: int in n:
		result[i] /= total
	return result

func deform(contour: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for row: PackedFloat32Array in weights:
		var point := Vector2.ZERO
		for i: int in contour.size():
			point += contour[i] * row[i]
		result.append(point)
	return result

func build(contour: PackedVector2Array, alignment: Transform2D) -> ArrayMesh:
	var positions := PackedVector3Array()
	for point: Vector2 in deform(contour):
		positions.append(Vector3(point.x, point.y, 0))
	var uv := PackedVector2Array()
	var inverse := alignment.affine_inverse()
	for point: Vector2 in vertices:
		uv.append(inverse * point)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
