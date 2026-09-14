class_name FaceAnalyzer
extends RefCounted
## 端侧人脸关键点检测（GDMP / MediaPipe FaceLandmarker，静态图片 IMAGE 模式）。
## 全部走 ClassDB 动态访问：GDMP 库未加载的平台上脚本仍可解析运行，仅 is_available() 为 false。

const LANDMARKER_MODEL := "res://assets/models/face/face_landmarker.task"
const MIN_DETECTION_CONFIDENCE := 0.5
const MIN_PRESENCE_CONFIDENCE := 0.5
const MIN_TRACKING_CONFIDENCE := 0.5

static func is_available() -> bool:
	return ClassDB.class_exists(&"MediaPipeFaceLandmarker")

## 分析一张静态照片。返回字典：
##   ok: bool
##   error: String（ok == false 时填写）
##   landmarks: PackedVector2Array（478 点，照片像素坐标）
##   blendshapes: Dictionary（表情名 -> 权重 0..1，可能为空）
func analyze(image: Image) -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "GDMP 不可用：MediaPipe 类未注册"}
	if image == null or image.is_empty():
		return {"ok": false, "error": "输入图片为空"}
	var model_bytes := _read_file_bytes(LANDMARKER_MODEL)
	if model_bytes.is_empty():
		return {"ok": false, "error": "关键点模型缺失或为空：%s" % LANDMARKER_MODEL}
	# GPU delegate 仅在 Android/iOS/Linux 可靠（GDMP demo 在 Windows/macOS/Web 上禁用 GPU 选项）。
	var use_gpu := OS.get_name() in ["Android", "iOS", "Linux"]
	var result: Dictionary = _detect(image, model_bytes, use_gpu)
	if not result.get("ok", false) and use_gpu:
		# GPU 初始化/推理失败时回退 CPU；一次性处理对耗时不敏感（实测 CPU 约 88ms）。
		result = _detect(image, model_bytes, false)
	return result

func _detect(image: Image, model_bytes: PackedByteArray, use_gpu: bool) -> Dictionary:
	var work_image: Image = image.duplicate()
	# demo 约定：GPU delegate 用 RGBA8，CPU 用 RGB8。
	work_image.convert(Image.FORMAT_RGBA8 if use_gpu else Image.FORMAT_RGB8)
	var base_options: RefCounted = ClassDB.instantiate(&"MediaPipeTaskBaseOptions")
	if base_options == null:
		return {"ok": false, "error": "无法创建 MediaPipeTaskBaseOptions"}
	var delegate_gpu: int = ClassDB.class_get_integer_constant(&"MediaPipeTaskBaseOptions", &"DELEGATE_GPU")
	var delegate_cpu: int = ClassDB.class_get_integer_constant(&"MediaPipeTaskBaseOptions", &"DELEGATE_CPU")
	base_options.set("delegate", delegate_gpu if use_gpu else delegate_cpu)
	base_options.set("model_asset_buffer", model_bytes)
	var running_mode_image: int = ClassDB.class_get_integer_constant(&"MediaPipeVisionTask", &"RUNNING_MODE_IMAGE")
	var landmarker: RefCounted = ClassDB.instantiate(&"MediaPipeFaceLandmarker")
	if landmarker == null:
		return {"ok": false, "error": "无法创建 MediaPipeFaceLandmarker"}
	var initialized: bool = landmarker.initialize(
		base_options, running_mode_image, 1,
		MIN_DETECTION_CONFIDENCE, MIN_PRESENCE_CONFIDENCE, MIN_TRACKING_CONFIDENCE,
		true, false)
	if not initialized:
		return {"ok": false, "error": "FaceLandmarker 初始化失败（delegate=%s）" % ("GPU" if use_gpu else "CPU")}
	var mp_image: RefCounted = ClassDB.instantiate(&"MediaPipeImage")
	mp_image.set_image(work_image)
	var task_result: RefCounted = landmarker.detect(mp_image, Rect2(), 0)
	if task_result == null:
		return {"ok": false, "error": "detect() 返回空（delegate=%s）" % ("GPU" if use_gpu else "CPU")}
	var faces: Array = task_result.get_face_landmarks()
	if faces.is_empty():
		return {"ok": false, "error": "未检测到人脸"}
	var landmarks := PackedVector2Array()
	var first_face: RefCounted = faces[0]
	var width := float(work_image.get_width())
	var height := float(work_image.get_height())
	for point: RefCounted in first_face.get_landmarks():
		landmarks.append(Vector2(point.get_x() * width, point.get_y() * height))
	var blendshapes := {}
	if task_result.has_face_blendshapes():
		var shape_sets: Array = task_result.get_face_blendshapes()
		if not shape_sets.is_empty():
			for category: RefCounted in shape_sets[0].get_categories():
				if category.has_category_name():
					blendshapes[category.get("category_name")] = category.get("score")
	return {"ok": true, "error": "", "landmarks": landmarks, "blendshapes": blendshapes}

static func _read_file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())
