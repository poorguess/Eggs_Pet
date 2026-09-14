class_name FaceWarpBaker
extends Node
## 逐三角形仿射 warp：把照片上的五官区域映射到角色脸部模板形状。
## GPU 路径：SubViewport + MeshInstance2D（顶点=目标位置，UV=照片采样位置），
##   依赖光栅管线而非 compute shader（移动端 compute 驱动风险见官方渲染架构文档）。
## CPU 路径：WorkerThreadPool 并行重心坐标采样，供 headless / GPU 不可用时降级。

## 协程：GPU 光栅 warp。调用方需 await。
## src_points/dst_points 均为像素坐标，一一对应；triangles 为 dst 侧的 Delaunay 索引。
func warp_gpu_async(
	src_texture: Texture2D,
	src_points: PackedVector2Array,
	dst_points: PackedVector2Array,
	triangles: PackedInt32Array,
	out_size: Vector2i
) -> Image:
	if src_texture == null or triangles.is_empty():
		return null
	var src_size := src_texture.get_size()
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in dst_points.size():
		positions.append(Vector3(dst_points[i].x, dst_points[i].y, 0.0))
		uvs.append(src_points[i] / src_size)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = out_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mesh_instance := MeshInstance2D.new()
	mesh_instance.mesh = mesh
	mesh_instance.texture = src_texture
	mesh_instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport.add_child(mesh_instance)
	add_child(viewport)
	# UPDATE_ONCE 下一帧渲染；等两个 frame_post_draw 保证帧真的走完。
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image

## CPU warp（同步）。WorkerThreadPool 按三角形分组并行；相邻三角形在共享边上的
## 双写会写出近似相同的采样值，竞争无害。
static func warp_cpu(
	src: Image,
	src_points: PackedVector2Array,
	dst_points: PackedVector2Array,
	triangles: PackedInt32Array,
	out_size: Vector2i
) -> Image:
	var out := Image.create_empty(out_size.x, out_size.y, false, Image.FORMAT_RGBA8)
	var src_rgba: Image = src
	if src.get_format() != Image.FORMAT_RGBA8:
		src_rgba = src.duplicate()
		src_rgba.convert(Image.FORMAT_RGBA8)
	var triangle_count := triangles.size() / 3
	var task := func(index: int) -> void:
		_warp_triangle(src_rgba, out, src_points, dst_points, triangles, index)
	if triangle_count > 0:
		var group_id := WorkerThreadPool.add_group_task(task, triangle_count, -1, true)
		WorkerThreadPool.wait_for_group_task_completion(group_id)
	return out

static func _warp_triangle(
	src: Image,
	out: Image,
	src_points: PackedVector2Array,
	dst_points: PackedVector2Array,
	triangles: PackedInt32Array,
	triangle_index: int
) -> void:
	var i0 := triangles[triangle_index * 3]
	var i1 := triangles[triangle_index * 3 + 1]
	var i2 := triangles[triangle_index * 3 + 2]
	var a := dst_points[i0]
	var b := dst_points[i1]
	var c := dst_points[i2]
	var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(den) < 0.0001:
		return
	var min_x := maxi(0, floori(minf(a.x, minf(b.x, c.x))))
	var min_y := maxi(0, floori(minf(a.y, minf(b.y, c.y))))
	var max_x := mini(out.get_width() - 1, ceili(maxf(a.x, maxf(b.x, c.x))))
	var max_y := mini(out.get_height() - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
	var sa := src_points[i0]
	var sb := src_points[i1]
	var sc := src_points[i2]
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
			var w1 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			out.set_pixel(x, y, _bilinear(src, sa * w0 + sb * w1 + sc * w2))

static func _bilinear(image: Image, p: Vector2) -> Color:
	var x := clampf(p.x - 0.5, 0.0, image.get_width() - 1.001)
	var y := clampf(p.y - 0.5, 0.0, image.get_height() - 1.001)
	var x0 := int(x)
	var y0 := int(y)
	var fx := x - x0
	var fy := y - y0
	var c00 := image.get_pixel(x0, y0)
	var c10 := image.get_pixel(x0 + 1, y0)
	var c01 := image.get_pixel(x0, y0 + 1)
	var c11 := image.get_pixel(x0 + 1, y0 + 1)
	return c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)
