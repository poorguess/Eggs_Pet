class_name FaceCamera
extends Node

signal preview_frame(texture: ImageTexture)
signal permission_denied
signal unavailable

# 低分辨率预览足够取景，全屏显示时由 GPU 放大；更小缓冲 = 更低 JNI/纹理上传开销。
const PREVIEW_WIDTH := 640
const PREVIEW_HEIGHT := 480

var _camera: NativeCamera
var _latest: Image
var _texture: ImageTexture

func native_available() -> bool:
	return OS.get_name() in ["Android", "iOS"] and Engine.has_singleton("NativeCameraPlugin")

func start() -> void:
	if not native_available():
		unavailable.emit()
		return
	_camera = NativeCamera.new()
	_camera.frame_width = PREVIEW_WIDTH
	_camera.frame_height = PREVIEW_HEIGHT
	_camera.frames_to_skip = 2
	_camera.mirror_horizontal = true
	_camera.auto_upright = true
	add_child(_camera)
	_camera.camera_permission_granted.connect(_on_permission_granted)
	_camera.camera_permission_denied.connect(func() -> void: permission_denied.emit())
	_camera.frame_available.connect(_on_frame_available)
	if _camera.has_camera_permission():
		_on_permission_granted()
	else:
		_camera.request_camera_permission()

func stop() -> void:
	if _camera:
		_camera.stop()
		_camera.queue_free()
		_camera = null
	_latest = null
	_texture = null

func capture() -> Image:
	return _latest

func _on_permission_granted() -> void:
	var request := _camera.create_feed_request()
	for info in _camera.get_all_cameras():
		if info.is_front_facing():
			request.set_camera_id(info.get_camera_id())
			break
	_camera.start(request)

func _on_frame_available(info: FrameInfo) -> void:
	_latest = info.get_image()
	if _texture == null:
		_texture = ImageTexture.create_from_image(_latest)
	else:
		_texture.update(_latest)
	preview_frame.emit(_texture)
