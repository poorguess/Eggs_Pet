class_name FaceApi
extends Node

signal completed(image: Image, full_character: bool)
signal failed(message: String)

const CONFIG_PATH_USER := "user://face_api.cfg"
const CONFIG_PATH_RES := "res://face_api.cfg"
# 保持在原链路已验证的输入像素限制内；只上传自拍。
const PHOTO_SIZE := 400
const FeaturePrompt = preload("res://scripts/face/face_prompt.gd")
const DEFAULT_PROMPT := FeaturePrompt.TEXT

var endpoint := ""
var base_url := ""
var api_key := ""
var model := ""
var prompt := DEFAULT_PROMPT
var image_size := ""
var quality := ""
var config_error := ""

# 网关上游不稳定（同一请求随机返回 400 "Upstream request failed"），自动重试几次再报错。
const MAX_ATTEMPTS := 5
# gpt-image 生成耗时长且网关可能挂起连接；HTTPRequest 无内置超时，用看门狗兜底，避免无限"处理中"。
const REQUEST_TIMEOUT := 180.0

var _http: HTTPRequest
var _fetch: HTTPRequest
var _last_full_character := false
var _attempt := 0
var _retry_parts: Array[PackedByteArray] = []
var _waiting := false
var _request_id := 0

func _ready() -> void:
	_http = HTTPRequest.new()
	_fetch = HTTPRequest.new()
	add_child(_http)
	add_child(_fetch)
	_http.request_completed.connect(_on_request_completed)
	_fetch.request_completed.connect(_on_fetch_completed)
	_load_config()

func _load_config() -> void:
	config_error = ""
	var config := ConfigFile.new()
	var loaded := false
	for path in [CONFIG_PATH_USER, CONFIG_PATH_RES]:
		if config.load(path) == OK:
			loaded = true
			break
	if loaded:
		base_url = String(config.get_value("api", "base_url", ""))
		endpoint = String(config.get_value("api", "endpoint", ""))
		api_key = String(config.get_value("api", "api_key", ""))
		model = String(config.get_value("api", "model", ""))
		prompt = DEFAULT_PROMPT # Output protocol cannot be overridden by old cfg prompts.
		image_size = String(config.get_value("api", "size", ""))
		quality = String(config.get_value("api", "quality", ""))
	if endpoint.is_empty() and not base_url.is_empty():
		endpoint = base_url.rstrip("/") + "/images/edits"
	if endpoint.is_empty() or api_key.is_empty():
		endpoint = ""
		config_error = "未配置图生图 API（face_api.cfg 缺失）。"
	print("[FaceApi] config loaded=%s model=%s key_set=%s" % [loaded, model, not api_key.is_empty()])
	if not config_error.is_empty():
		push_warning("FaceApi: " + config_error)

func reload_config() -> void:
	cancel()
	_load_config()

func process_photo(photo: Image) -> void:
	if photo == null or photo.is_empty():
		failed.emit("没有可用的照片。")
		return
	if _waiting:
		return
	if not config_error.is_empty():
		failed.emit(config_error)
		return
	_attempt = 0
	_request_cloud(photo)

static func crop_square(photo: Image) -> Image:
	var image := photo.duplicate()
	var side := mini(image.get_width(), image.get_height())
	var region := Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side)
	return image.get_region(region)


func _load_character_ref() -> Image:
	if character_ref.is_empty():
		return null
	var image := load_image_resource(character_ref)
	if image == null or image.is_empty():
		push_warning("FaceApi: 角色参考图加载失败（%s），退回单图漫画头像模式。" % character_ref)
		return null
	var longest := maxi(image.get_width(), image.get_height())
	if longest > 1024:
		var ratio := 1024.0 / longest
		image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	return image

static func _text_part(boundary: String, field: String, value: String) -> PackedByteArray:
	return ("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + field + "\"\r\n\r\n" + value + "\r\n").to_utf8_buffer()

static func _image_part(boundary: String, field: String, filename: String, png: PackedByteArray) -> PackedByteArray:
	var part := PackedByteArray()
	part.append_array(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + field + "\"; filename=\"" + filename + "\"\r\nContent-Type: image/png\r\n\r\n").to_utf8_buffer())
	part.append_array(png)
	part.append_array("\r\n".to_utf8_buffer())
	return part

func _send(parts: Array[PackedByteArray]) -> void:
	_retry_parts = parts
	_send_now()

func _send_now() -> void:
	var boundary := "GodotFaceApiBoundary7MA4YWxkTrZu0gW"
	var body := PackedByteArray()
	for part in _retry_parts:
		body.append_array(part)
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	print("[FaceApi] POST %s bytes=%d attempt=%d" % [endpoint, body.size(), _attempt + 1])
	var err := _http.request_raw(endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		failed.emit("请求发送失败（%d）。" % err)
		return
	_waiting = true
	_arm_timeout()

func _arm_timeout() -> void:
	_request_id += 1
	var id := _request_id
	get_tree().create_timer(REQUEST_TIMEOUT).timeout.connect(func() -> void:
		if not _waiting or id != _request_id:
			return
		_waiting = false
		_http.cancel_request()
		_fetch.cancel_request()
		_retry_or_fail("请求超时，网关 %d 秒无响应。" % int(REQUEST_TIMEOUT)))

func cancel() -> void:
	# 作废旧请求的看门狗与退避 continuation（它们按 _request_id 识别代际），并断开 HTTP。
	_request_id += 1
	_waiting = false
	_attempt = 0
	_retry_parts.clear()
	if _http:
		_http.cancel_request()
	if _fetch:
		_fetch.cancel_request()

func _retry_or_fail(message: String) -> void:
	_attempt += 1
	print("[FaceApi] attempt %d/%d failed: %s" % [_attempt, MAX_ATTEMPTS, message])
	if _attempt < MAX_ATTEMPTS and not _retry_parts.is_empty():
		_waiting = true
		var id := _request_id
		await get_tree().create_timer(1.5 * _attempt).timeout
		# 退避期间被 cancel() 或新流程取代时，旧重试链不再重发（否则会对忙的 _http 误报 ERR_BUSY）。
		if id != _request_id:
			return
		_send_now()
	else:
		_waiting = false
		failed.emit(message)

func _request_cloud(photo: Image) -> void:
	_last_full_character = false
	var image := crop_square(photo)
	image.resize(PHOTO_SIZE, PHOTO_SIZE, Image.INTERPOLATE_LANCZOS)
	var boundary := "GodotFaceApiBoundary7MA4YWxkTrZu0gW"
	image.resize(FALLBACK_AVATAR_SIZE, FALLBACK_AVATAR_SIZE, Image.INTERPOLATE_LANCZOS)
	_send([
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "model", model),
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "prompt", LEGACY_PROMPT),
		_image_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "image", "photo.png", image.save_png_to_buffer()),
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "background", "transparent"),
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "output_format", "png"),
	])

static func _fit_into(image: Image, box: Vector2i) -> Image:
	var scale := minf(float(box.x) / image.get_width(), float(box.y) / image.get_height())
	var w := maxi(1, int(image.get_width() * scale))
	var h := maxi(1, int(image.get_height() * scale))
	image.resize(w, h, Image.INTERPOLATE_LANCZOS)
	# blit_rect 要求与目标图格式一致；JPEG/相机帧是 RGB8，须统一转成合成图的 RGBA8。
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _build_composite(ref: Image, photo: Image) -> Image:
	var half := Vector2i(COMPOSITE_SIZE.x / 2, COMPOSITE_SIZE.y)
	var left := _fit_into(ref.duplicate(), half)
	var right := _fit_into(crop_square(photo), half)
	var composite := Image.create(COMPOSITE_SIZE.x, COMPOSITE_SIZE.y, false, Image.FORMAT_RGBA8)
	# 透明底输入会被上游 400 拒绝；白底已验证可用。blend_rect 按 alpha 混合，角色立绘的透明区不会击穿白底。
	composite.fill(Color.WHITE)
	composite.blend_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i((half.x - left.get_width()) / 2, (half.y - left.get_height()) / 2))
	composite.blend_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(half.x + (half.x - right.get_width()) / 2, (half.y - right.get_height()) / 2))
	return composite

# 当前网关总是返回不透明纯色底（实测为黑），且忽略 background=transparent：
# 缩到显示分辨率后从边缘洪泛抠掉四角取样的底色。四角颜色不一致（模型画了场景）时原样返回，不误伤。
const LOOK_MAX_SIZE := 512
const BG_KEY_TOLERANCE := 40.0

static func cutout_character(image: Image) -> Image:
	var longest := maxi(image.get_width(), image.get_height())
	if longest > LOOK_MAX_SIZE:
		var ratio := float(LOOK_MAX_SIZE) / longest
		image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.detect_alpha() != Image.ALPHA_NONE:
		return image
	var w := image.get_width()
	var h := image.get_height()
	var corners := [image.get_pixel(0, 0), image.get_pixel(w - 1, 0), image.get_pixel(0, h - 1), image.get_pixel(w - 1, h - 1)]
	var bg := Color.TRANSPARENT
	for c: Color in corners:
		bg += c
	bg = bg / corners.size()
	for c: Color in corners:
		if _channel_distance(c, bg) > BG_KEY_TOLERANCE:
			return image
	var visited := PackedByteArray()
	visited.resize(w * h)
	var queue: Array[int] = []
	var try_enqueue := func(x: int, y: int) -> void:
		var idx := y * w + x
		if visited[idx] == 1:
			return
		visited[idx] = 1
		if _channel_distance(image.get_pixel(x, y), bg) <= BG_KEY_TOLERANCE:
			queue.append(idx)
	for x in range(w):
		try_enqueue.call(x, 0)
		try_enqueue.call(x, h - 1)
	for y in range(h):
		try_enqueue.call(0, y)
		try_enqueue.call(w - 1, y)
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var x := idx % w
		var y := idx / w
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0:
			try_enqueue.call(x - 1, y)
		if x + 1 < w:
			try_enqueue.call(x + 1, y)
		if y > 0:
			try_enqueue.call(x, y - 1)
		if y + 1 < h:
			try_enqueue.call(x, y + 1)
	return image

static func _channel_distance(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0

# ---- 脸部烘焙：把换脸结果的五官差分提取出来，逐帧合成进精灵表 ----
# 这样换脸只替换 pet.sprite.texture 的像素，33 帧动画 / 漫游 / 转向逻辑全部原样保留。
# 校准依据（探针实测 shell_pudding.png 与 character1.png）：立绘与帧格同为 320x395，
# 帧 0 角色 bbox 与立绘完全一致；帧间 bbox 漂移仅 x±1 / y±7；头部是奶油白低饱和区域，
# 黄衣、蓝裤、深色描边都被下面的亮度条件排除，因此"原本是头部亮色的像素"即头部画布。
const HEAD_LIGHT_MIN := Color(0.9, 0.85, 0.8)
const FACE_DIFF_TOLERANCE := 45.0
const FACE_ALPHA_SOFT_START := 30.0
const FACE_ALPHA_SOFT_RANGE := 35.0
const FACE_BBOX_MARGIN := 0.16
const FACE_MIN_PIXELS := 60
# 对齐守护：整体 bbox 长宽比容差较松（容忍 AI 加的地面投影/留白），
# 头部亮区回退策略容差较严（防止把场景亮部当头）。
const BODY_ASPECT_TOLERANCE := 0.18
const HEAD_ASPECT_TOLERANCE := 0.25

# ---- 五官重拟合布局锚点（头部亮区归一化坐标）----
# 原版角色是无五官的空白奶油头；锚点实测自遵循提示词的 AI 输出（豆豆眼/细眉/ω嘴的位置），
# 即"这张脸的标准五官布局"。换脸五官按此重排，而不是照抄照片比例。
const CANON_EYE_L := Vector2(0.295, 0.610)
const CANON_EYE_R := Vector2(0.705, 0.610)
const CANON_MOUTH := Vector2(0.500, 0.764)
const CANON_BROW_DY := -0.094
const CANON_ZONE_W := 0.56
# 全脸重绘模式的五官搜索窗（归一化，盖住眉眼嘴、避开头发与下巴阴影）。
const FACE_WINDOW := Rect2(0.13, 0.40, 0.74, 0.50)
const SKIN_FG_TOLERANCE := 55.0
const SKIN_ALPHA_SOFT_START := 22.0
const SKIN_ALPHA_SOFT_RANGE := 60.0
const CLUSTER_DILATE_R := 2
const CLUSTER_MIN_PIXELS := 8

static func _opaque_bbox(image: Image, area: Rect2i) -> Rect2i:
	var min_x := area.end.x
	var min_y := area.end.y
	var max_x := area.position.x - 1
	var max_y := area.position.y - 1
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if image.get_pixel(x, y).a > 0.5:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# 头部亮区检测，步长 2 采样（bbox 精度 ±2px，足够锚定用）。
static func _light_region_bbox(image: Image, area: Rect2i) -> Rect2i:
	var min_x := area.end.x
	var min_y := area.end.y
	var max_x := area.position.x - 1
	var max_y := area.position.y - 1
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			var c := image.get_pixel(x, y)
			if c.a > 0.5 and c.r > HEAD_LIGHT_MIN.r and c.g > HEAD_LIGHT_MIN.g and c.b > HEAD_LIGHT_MIN.b:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# 把 look 的 src_rect 重映射进 ref 坐标系的 dst_rect，输出 ref 尺寸的对齐图（其余透明）。
static func _remap_to_ref(look_img: Image, src_rect: Rect2i, dst_rect: Rect2i, ref_size: Vector2i) -> Image:
	var region: Image = look_img.get_region(src_rect)
	region.resize(dst_rect.size.x, dst_rect.size.y, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(ref_size.x, ref_size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(region, Rect2i(Vector2i.ZERO, dst_rect.size), dst_rect.position)
	return out

# 策略 1：整体角色 bbox 对齐。身体/四肢保持最好，但怕 AI 添投影、改图幅。
static func _align_look_by_body(look_img: Image, ref_size: Vector2i, ref_bbox: Rect2i) -> Image:
	var look_bbox := _opaque_bbox(look_img, Rect2i(Vector2i.ZERO, look_img.get_size()))
	if look_bbox.size.x <= 0:
		return Image.new()
	var ref_aspect := float(ref_bbox.size.x) / ref_bbox.size.y
	var look_aspect := float(look_bbox.size.x) / look_bbox.size.y
	if absf(look_aspect - ref_aspect) / ref_aspect > BODY_ASPECT_TOLERANCE:
		print("[FaceApi] align-by-body rejected: look bbox=%s aspect %.3f vs ref %.3f" % [look_bbox.size, look_aspect, ref_aspect])
		return Image.new()
	return _remap_to_ref(look_img, look_bbox, ref_bbox, ref_size)

# 策略 2（回退）：头部亮区对齐。只重绘了脸（白头保留）的输出里，头是最稳的锚点，
# 对身体重构图、投影、留白免疫；头被整颗换掉（亮区不再是头）时由长宽比/面积守护拒绝。
static func _align_look_by_head(look_img: Image, ref_size: Vector2i, ref_head: Rect2i) -> Image:
	var full := Rect2i(Vector2i.ZERO, look_img.get_size())
	var look_head := _light_region_bbox(look_img, full)
	if look_head.size.x <= 0:
		return Image.new()
	var ref_aspect := float(ref_head.size.x) / ref_head.size.y
	var look_aspect := float(look_head.size.x) / look_head.size.y
	if absf(look_aspect - ref_aspect) / ref_aspect > HEAD_ASPECT_TOLERANCE:
		print("[FaceApi] align-by-head rejected: look head=%s aspect %.3f vs ref %.3f" % [look_head.size, look_aspect, ref_aspect])
		return Image.new()
	var area_frac := float(look_head.size.x * look_head.size.y) / float(full.size.x * full.size.y)
	if area_frac < 0.03 or area_frac > 0.8:
		print("[FaceApi] align-by-head rejected: head area fraction %.3f" % area_frac)
		return Image.new()
	return _remap_to_ref(look_img, look_head, ref_head, ref_size)

# ---- 五官重拟合：从对齐后的 look 分离五官，按 CANON_* 布局重排成单层贴片 ----

# 差分掩码（模式 1 用）：head 局部坐标，alpha 与旧贴片同公式。
static func _face_diff_mask(look_aligned: Image, ref_img: Image, head: Rect2i) -> Dictionary:
	var w := head.size.x
	var h := head.size.y
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(h):
		for x in range(w):
			var rp := ref_img.get_pixel(head.position.x + x, head.position.y + y)
			if rp.a < 0.5 or rp.r < HEAD_LIGHT_MIN.r or rp.g < HEAD_LIGHT_MIN.g or rp.b < HEAD_LIGHT_MIN.b:
				continue
			var lp := look_aligned.get_pixel(head.position.x + x, head.position.y + y)
			if lp.a > 0.5 and _channel_distance(lp, rp) > FACE_DIFF_TOLERANCE:
				mask[y * w + x] = 1
	return {"mask": mask, "w": w, "h": h}

# 肤区洪泛（模式 2 的核心）：窗口内 5x4 种子网格逐点洪泛，按"大小 × 居中 × 不触顶"打分选最优。
# 双判据：与种子 7x7 均色的全局锚定 ≤50（挡住深发/兜帽，防止渐变色漂移）＋与上一像素的局部步进 ≤28
# （允许皮肤自身的明暗渐变连续通过；眼镜框/发际/唇线等硬边被局部步进挡住，镜片始终是洞）。
const SKIN_REGION_TOLERANCE := 50.0
const SKIN_LOCAL_STEP := 28.0
const SKIN_REGION_MIN_FRACTION := 0.08

static func _skin_region_flood(img: Image, origin: Vector2i, size: Vector2i) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var center := Vector2(size) / 2.0
	var cols := 5
	var rows := 4
	for gy in range(rows):
		for gx in range(cols):
			var sx := int(size.x * (0.15 + 0.70 * gx / (cols - 1)))
			var sy := int(size.y * (0.15 + 0.70 * gy / (rows - 1)))
			if img.get_pixel(origin.x + sx, origin.y + sy).a < 0.5:
				continue
			var sum := Vector3.ZERO
			var n := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var px: int = sx + dx
					var py: int = sy + dy
					if px < 0 or px >= size.x or py < 0 or py >= size.y:
						continue
					var c0 := img.get_pixel(origin.x + px, origin.y + py)
					if c0.a < 0.5:
						continue
					sum += Vector3(c0.r, c0.g, c0.b)
					n += 1
			if n == 0:
				continue
			var tether := Color(sum.x / n, sum.y / n, sum.z / n)
			var region := PackedByteArray()
			region.resize(size.x * size.y)
			var queue: Array[int] = [sy * size.x + sx]
			region[sy * size.x + sx] = 1
			var count := 1
			var sum_pos := Vector2(sx, sy)
			var sum_col := Vector3(tether.r, tether.g, tether.b)
			var touches_top := sy <= 1
			var qi := 0
			while qi < queue.size():
				var cur := queue[qi]
				qi += 1
				var cx := cur % size.x
				var cy := cur / size.x
				var from_c := img.get_pixel(origin.x + cx, origin.y + cy)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = cx + d.x
					var ny: int = cy + d.y
					if nx < 0 or nx >= size.x or ny < 0 or ny >= size.y:
						continue
					var nidx := ny * size.x + nx
					if region[nidx] == 1:
						continue
					var c := img.get_pixel(origin.x + nx, origin.y + ny)
					if c.a < 0.5:
						continue
					if _channel_distance(c, tether) > SKIN_REGION_TOLERANCE:
						continue
					if _channel_distance(c, from_c) > SKIN_LOCAL_STEP:
						continue
					region[nidx] = 1
					count += 1
					sum_pos += Vector2(nx, ny)
					sum_col += Vector3(c.r, c.g, c.b)
					if ny <= 1:
						touches_top = true
					queue.append(nidx)
			if count < size.x * size.y * SKIN_REGION_MIN_FRACTION:
				continue
			var cen := sum_pos / count
			var score := float(count) * (1.0 - 0.55 * minf(1.0, cen.distance_to(center) / (size.x * 0.5)))
			if touches_top:
				score *= 0.15
			if score > best_score:
				best_score = score
				best = {"region": region, "skin": Color(sum_col.x / count, sum_col.y / count, sum_col.z / count), "count": count, "tether": tether, "touches_top": touches_top}
	# 连通域合并：墨镜/刘海会把脸物理截断成额头、脸颊、下巴等多个不连通肤块，
	# 锚色相近（≤50）的块并回主区——眼镜依旧被肤色四面包围，闭运算后仍是洞。
	if not best.is_empty():
		var merged: PackedByteArray = best.region
		var merged_count: int = best.count
		var base_tether: Color = best.tether
		for gy2 in range(rows):
			for gx2 in range(cols):
				var sx2 := int(size.x * (0.15 + 0.70 * gx2 / (cols - 1)))
				var sy2 := int(size.y * (0.15 + 0.70 * gy2 / (rows - 1)))
				if img.get_pixel(origin.x + sx2, origin.y + sy2).a < 0.5:
					continue
				var s2 := Vector3.ZERO
				var n2 := 0
				for dy2 in range(-3, 4):
					for dx2 in range(-3, 4):
						var px2: int = sx2 + dx2
						var py2: int = sy2 + dy2
						if px2 < 0 or px2 >= size.x or py2 < 0 or py2 >= size.y:
							continue
						var c2 := img.get_pixel(origin.x + px2, origin.y + py2)
						if c2.a < 0.5:
							continue
						s2 += Vector3(c2.r, c2.g, c2.b)
						n2 += 1
				if n2 == 0:
					continue
				var t2 := Color(s2.x / n2, s2.y / n2, s2.z / n2)
				if _channel_distance(t2, base_tether) > SKIN_REGION_TOLERANCE:
					continue
				# 锚色相近则把该种子的小洪泛并进主区（快速 BFS，复用双判据）
				var add := PackedByteArray()
				add.resize(size.x * size.y)
				var q2: Array[int] = [sy2 * size.x + sx2]
				add[sy2 * size.x + sx2] = 1
				var qi2 := 0
				while qi2 < q2.size():
					var cur2: int = q2[qi2]
					qi2 += 1
					var cx2 := cur2 % size.x
					var cy2 := cur2 / size.x
					var from2 := img.get_pixel(origin.x + cx2, origin.y + cy2)
					for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx2: int = cx2 + d2.x
						var ny2: int = cy2 + d2.y
						if nx2 < 0 or nx2 >= size.x or ny2 < 0 or ny2 >= size.y:
							continue
						var ni2 := ny2 * size.x + nx2
						if add[ni2] == 1 or merged[ni2] == 1:
							continue
						var cc := img.get_pixel(origin.x + nx2, origin.y + ny2)
						if cc.a < 0.5:
							continue
						if _channel_distance(cc, t2) > SKIN_REGION_TOLERANCE:
							continue
						if _channel_distance(cc, from2) > SKIN_LOCAL_STEP:
							continue
						add[ni2] = 1
						q2.append(ni2)
				var added := 0
				for i in range(size.x * size.y):
					if add[i] == 1 and merged[i] == 0:
						merged[i] = 1
						added += 1
				merged_count += added
		best.region = merged
		best.count = merged_count
	return best

# 矩形膨胀（可分离滑动窗口，比逐像素盖章快一个量级）。
static func _dilate_mask(src: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	for y in range(h):
		var run := 0
		for i in range(0, mini(r + 1, w)):
			if src[y * w + i] == 1:
				run += 1
		for x in range(w):
			if run > 0:
				tmp[y * w + x] = 1
			var out_x := x - r
			if out_x >= 0 and src[y * w + out_x] == 1:
				run -= 1
			var in_x := x + r + 1
			if in_x < w and src[y * w + in_x] == 1:
				run += 1
	var out := PackedByteArray()
	out.resize(w * h)
	for x in range(w):
		var run := 0
		for i in range(0, mini(r + 1, h)):
			if tmp[i * w + x] == 1:
				run += 1
		for y in range(h):
			if run > 0:
				out[y * w + x] = 1
			var out_y := y - r
			if out_y >= 0 and tmp[out_y * w + x] == 1:
				run -= 1
			var in_y := y + r + 1
			if in_y < h and tmp[in_y * w + x] == 1:
				run += 1
	return out

# 矩形腐蚀（开运算的前半：先腐蚀断开发际环与眼镜的细连接，取腐蚀后的成员做分类与提取基底）。
static func _erode_mask(src: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	var win_len := 2 * r + 1
	for y in range(h):
		var run := 0
		for i in range(0, mini(r + 1, w)):
			if src[y * w + i] == 1:
				run += 1
		for x in range(w):
			if run >= win_len:
				tmp[y * w + x] = 1
			var out_x := x - r
			if out_x >= 0 and src[y * w + out_x] == 1:
				run -= 1
			var in_x := x + r + 1
			if in_x < w and src[y * w + in_x] == 1:
				run += 1
	var out := PackedByteArray()
	out.resize(w * h)
	for x in range(w):
		var run := 0
		for i in range(0, mini(r + 1, h)):
			if tmp[i * w + x] == 1:
				run += 1
		for y in range(h):
			if run >= win_len:
				out[y * w + x] = 1
			var out_y := y - r
			if out_y >= 0 and tmp[out_y * w + x] == 1:
				run -= 1
			var in_y := y + r + 1
			if in_y < h and tmp[in_y * w + x] == 1:
				run += 1
	return out

# 半径 dilate_r 膨胀 + 8 连通聚类；过小的碎片丢弃。返回 [{pixels,bbox,centroid,area}]（局部坐标）。
static func _cluster_mask(mask: PackedByteArray, w: int, h: int, dilate_r := CLUSTER_DILATE_R) -> Array[Dictionary]:
	var dil := PackedByteArray()
	dil.resize(w * h)
	for y in range(h):
		for x in range(w):
			if mask[y * w + x] == 0:
				continue
			for dy in range(-dilate_r, dilate_r + 1):
				for dx in range(-dilate_r, dilate_r + 1):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and nx < w and ny >= 0 and ny < h:
						dil[ny * w + nx] = 1
	var labels := PackedInt32Array()
	labels.resize(w * h)
	labels.fill(-1)
	var clusters: Array[Dictionary] = []
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if dil[idx] == 0 or labels[idx] != -1:
				continue
			var cid := clusters.size()
			var queue: Array[int] = [idx]
			labels[idx] = cid
			var members := PackedInt32Array()
			var qi := 0
			while qi < queue.size():
				var cur := queue[qi]
				qi += 1
				if mask[cur] == 1:
					members.append(cur)
				var cx := cur % w
				var cy := cur / w
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx: int = cx + dx
						var ny: int = cy + dy
						if nx < 0 or nx >= w or ny < 0 or ny >= h:
							continue
						var nidx := ny * w + nx
						if dil[nidx] == 1 and labels[nidx] == -1:
							labels[nidx] = cid
							queue.append(nidx)
			if members.size() < CLUSTER_MIN_PIXELS:
				continue
			var min_x := w
			var min_y := h
			var max_x := -1
			var max_y := -1
			var sx := 0.0
			var sy := 0.0
			for m in members:
				var mx := m % w
				var my := m / w
				min_x = mini(min_x, mx)
				min_y = mini(min_y, my)
				max_x = maxi(max_x, mx)
				max_y = maxi(max_y, my)
				sx += mx
				sy += my
			clusters.append({
				"pixels": members,
				"bbox": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
				"centroid": Vector2(sx / members.size(), sy / members.size()),
				"area": members.size(),
			})
	return clusters

# 五官角色判定。eye_y_range 限定眼的纵向合法区间（局部归一化）。
static func _classify_features(clusters: Array[Dictionary], w: int, h: int, eye_y_min: float, eye_y_max: float) -> Dictionary:
	var roles := {"eye_l": -1, "eye_r": -1, "eye_zone": -1, "mouth": -1, "brow_l": -1, "brow_r": -1, "nose": -1}
	if clusters.size() < 2:
		return roles
	var fw := float(w)
	var fh := float(h)
	var local_area := fw * fh
	# 连通眼镜区：横跨中线、横条状、面积不足以是"整头重绘块"。
	for i in range(clusters.size()):
		var bb: Rect2i = clusters[i].bbox
		var cen: Vector2 = clusters[i].centroid
		if float(clusters[i].area) > local_area * 0.40:
			continue
		if float(bb.size.x) / fw > 0.42 and float(bb.position.x) < fw * 0.5 and float(bb.end.x) > fw * 0.5 \
			and cen.y > fh * eye_y_min and cen.y < fh * eye_y_max \
			and float(bb.size.x) / maxf(1.0, float(bb.size.y)) > 1.8:
			roles.eye_zone = i
			break
	# 双眼配对：纵向位置合法、非细长条（排除眉）、间距/水平对齐/面积相近，面积越大越优先。
	var best := -1.0
	for i in range(clusters.size()):
		if i == roles.eye_zone:
			continue
		for j in range(i + 1, clusters.size()):
			if j == roles.eye_zone:
				continue
			var a: Dictionary = clusters[i]
			var b: Dictionary = clusters[j]
			var ca: Vector2 = a.centroid
			var cb: Vector2 = b.centroid
			if ca.y < fh * eye_y_min or ca.y > fh * eye_y_max or cb.y < fh * eye_y_min or cb.y > fh * eye_y_max:
				continue
			var ba: Rect2i = a.bbox
			var bb2: Rect2i = b.bbox
			if float(ba.size.x) / maxf(1.0, float(ba.size.y)) > 2.5 or float(bb2.size.x) / maxf(1.0, float(bb2.size.y)) > 2.5:
				continue
			var dx := absf(ca.x - cb.x)
			if dx < fw * 0.10 or dx > fw * 0.60:
				continue
			var dy := absf(ca.y - cb.y)
			if dy > fh * 0.10:
				continue
			var ratio := minf(float(a.area), float(b.area)) / maxf(float(a.area), float(b.area))
			if ratio < 0.15:
				continue
			var sym := 1.0 - absf((ca.x + cb.x) / 2.0 - fw * 0.5) / (fw * 0.5)
			var score := ratio * (1.0 - dy / (fh * 0.10)) * (0.5 + 0.5 * sym) * minf(1.0, minf(float(a.area), float(b.area)) / (0.004 * local_area))
			if score > best:
				best = score
				if ca.x < cb.x:
					roles.eye_l = i
					roles.eye_r = j
				else:
					roles.eye_l = j
					roles.eye_r = i
	if roles.eye_l == -1 and roles.eye_zone == -1:
		return roles
	var eye_y := 0.0
	var mid_x := fw * 0.5
	if roles.eye_zone != -1:
		eye_y = clusters[roles.eye_zone].centroid.y
		mid_x = clusters[roles.eye_zone].centroid.x
	else:
		eye_y = (clusters[roles.eye_l].centroid.y + clusters[roles.eye_r].centroid.y) / 2.0
		mid_x = (clusters[roles.eye_l].centroid.x + clusters[roles.eye_r].centroid.x) / 2.0
	# 嘴：眼线下方、居中、面积合理、不触底（触底宽块是下巴阴影）。
	var mouth_best := 0.0
	for i in range(clusters.size()):
		if i in [roles.eye_l, roles.eye_r, roles.eye_zone]:
			continue
		var c: Dictionary = clusters[i]
		var cen: Vector2 = c.centroid
		var bb: Rect2i = c.bbox
		if cen.y < eye_y + fh * 0.05 or absf(cen.x - mid_x) > fw * 0.25:
			continue
		if float(c.area) > local_area * 0.12 or bb.end.y >= h - 1:
			continue
		if float(c.area) > mouth_best:
			mouth_best = c.area
			roles.mouth = i
	# 眉（眼上方横条）与鼻（眼嘴间中央小块）可选。
	for i in range(clusters.size()):
		if i in [roles.eye_l, roles.eye_r, roles.eye_zone, roles.mouth]:
			continue
		var c: Dictionary = clusters[i]
		var cen: Vector2 = c.centroid
		var bb: Rect2i = c.bbox
		var wide := float(bb.size.x) / maxf(1.0, float(bb.size.y)) > 1.6
		if cen.y < eye_y - fh * 0.02 and cen.y > eye_y - fh * 0.30 and wide and float(bb.size.x) / fw < 0.32:
			if cen.x < mid_x and roles.brow_l == -1:
				roles.brow_l = i
			elif cen.x >= mid_x and roles.brow_r == -1:
				roles.brow_r = i
		elif roles.mouth != -1 and cen.y > eye_y and cen.y < clusters[roles.mouth].centroid.y and absf(cen.x - mid_x) < fw * 0.10:
			if roles.nose == -1:
				roles.nose = i
	return roles

static func _roles_valid(roles: Dictionary) -> bool:
	return (roles.eye_zone != -1 or roles.eye_l != -1) and roles.mouth != -1

# 单五官子图：颜色取 look，alpha 按模式取差分软阈值（0）或肤色反差软阈值（1）。
# 提取范围 = 本集群成员像素膨胀 3 的闸门内（bbox 里混入的其他集群像素，如压到眼镜框的发梢，不会被带进来；
# 被五官包围的非前景像素，如嘴唇围住的牙齿，能被膨胀半径覆盖而保留）。
static func _feature_subimage(look_aligned: Image, ref_img: Image, head: Vector2i, cluster: Dictionary, mode: int, skin: Color) -> Image:
	var bb: Rect2i = cluster.bbox
	var stride: int = cluster.stride
	var gate := PackedByteArray()
	gate.resize(bb.size.x * bb.size.y)
	for m: int in cluster.pixels:
		var mx := m % stride - bb.position.x
		var my := m / stride - bb.position.y
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var gx: int = mx + dx
				var gy: int = my + dy
				if gx >= 0 and gx < bb.size.x and gy >= 0 and gy < bb.size.y:
					gate[gy * bb.size.x + gx] = 1
	var sub := Image.create(bb.size.x, bb.size.y, false, Image.FORMAT_RGBA8)
	if mode == 1:
		# 行向区间填充：把每行成员像素之间的区间填满，镜片/牙齿/口腔等被五官包围的内部得以保留；
		# 肤色像素由 alpha 软阈值自然归零，区间里混入的小异物（如发梢碎片）面积有限、可接受。
		var rows := {}
		for m: int in cluster.pixels:
			var mx: int = m % stride - bb.position.x
			var my: int = m / stride - bb.position.y
			if rows.has(my):
				rows[my][0] = mini(int(rows[my][0]), mx)
				rows[my][1] = maxi(int(rows[my][1]), mx)
			else:
				rows[my] = [mx, mx]
		for y: int in rows.keys():
			var span: Array = rows[y]
			for x in range(maxi(0, int(span[0])), mini(bb.size.x - 1, int(span[1])) + 1):
				var lp := look_aligned.get_pixel(head.x + bb.position.x + x, head.y + bb.position.y + y)
				if lp.a < 0.5:
					continue
				var a := clampf((_channel_distance(lp, skin) - SKIN_ALPHA_SOFT_START) / SKIN_ALPHA_SOFT_RANGE, 0.0, 1.0)
				if a > 0.0:
					sub.set_pixel(x, y, Color(lp.r, lp.g, lp.b, a))
		return sub
	for y in range(bb.size.y):
		for x in range(bb.size.x):
			if gate[y * bb.size.x + x] == 0:
				continue
			var lp := look_aligned.get_pixel(head.x + bb.position.x + x, head.y + bb.position.y + y)
			if lp.a < 0.5:
				continue
			var a := 0.0
			var rp := ref_img.get_pixel(head.x + bb.position.x + x, head.y + bb.position.y + y)
			if rp.a >= 0.5:
				a = clampf((_channel_distance(lp, rp) - FACE_ALPHA_SOFT_START) / FACE_ALPHA_SOFT_RANGE, 0.0, 1.0)
			if a > 0.0:
				sub.set_pixel(x, y, Color(lp.r, lp.g, lp.b, a))
	return sub

# 把分离出的五官按 CANON_* 布局缩放重排，输出头部局部坐标的单层贴片。
static func _compose_refit_patch(look_aligned: Image, ref_img: Image, head: Rect2i, clusters: Array[Dictionary], roles: Dictionary, mode: int, skin: Color) -> Dictionary:
	var hw := float(head.size.x)
	var hh := float(head.size.y)
	var zone_mode: bool = roles.eye_zone != -1
	var look_eye_mid: Vector2
	var look_eye_y := 0.0
	var s := 1.0
	if zone_mode:
		var zone: Dictionary = clusters[roles.eye_zone]
		look_eye_mid = zone.centroid
		look_eye_y = zone.centroid.y
		s = CANON_ZONE_W * hw / maxf(1.0, float(zone.bbox.size.x))
	else:
		var el: Dictionary = clusters[roles.eye_l]
		var er: Dictionary = clusters[roles.eye_r]
		look_eye_mid = (el.centroid + er.centroid) / 2.0
		look_eye_y = look_eye_mid.y
		s = (CANON_EYE_R.x - CANON_EYE_L.x) * hw / maxf(1.0, absf(er.centroid.x - el.centroid.x))
	s = clampf(s, 0.35, 2.5)
	var look_mouth_y: float = clusters[roles.mouth].centroid.y
	var canon_eye_l := Vector2(CANON_EYE_L.x * hw, CANON_EYE_L.y * hh)
	var canon_eye_r := Vector2(CANON_EYE_R.x * hw, CANON_EYE_R.y * hh)
	var canon_eye_mid := (canon_eye_l + canon_eye_r) / 2.0
	var canon_mouth := Vector2(CANON_MOUTH.x * hw, CANON_MOUTH.y * hh)
	var canvas := Image.create(int(hw), int(hh), false, Image.FORMAT_RGBA8)
	var head_origin := head.position
	for role in ["nose", "mouth", "brow_l", "brow_r", "eye_l", "eye_r", "eye_zone"]:
		var idx: int = roles[role]
		if idx == -1:
			continue
		var c: Dictionary = clusters[idx]
		var cen: Vector2 = c.centroid
		var target := canon_eye_mid
		match role:
			"eye_l":
				target = canon_eye_l
			"eye_r":
				target = canon_eye_r
			"eye_zone":
				target = canon_eye_mid
			"mouth":
				target = canon_mouth + Vector2((cen.x - look_eye_mid.x) * s, 0.0)
			"brow_l":
				target = canon_eye_l + Vector2((cen.x - clusters[roles.eye_l].centroid.x) * s if not zone_mode else (cen.x - look_eye_mid.x) * s, CANON_BROW_DY * hh)
			"brow_r":
				target = canon_eye_r + Vector2((cen.x - clusters[roles.eye_r].centroid.x) * s if not zone_mode else (cen.x - look_eye_mid.x) * s, CANON_BROW_DY * hh)
			"nose":
				var t := clampf((cen.y - look_eye_y) / maxf(1.0, look_mouth_y - look_eye_y), 0.0, 1.0)
				target = Vector2(canon_eye_mid.x + (cen.x - look_eye_mid.x) * s, lerpf(canon_eye_mid.y, canon_mouth.y, t))
		var sub := _feature_subimage(look_aligned, ref_img, head_origin, c, mode, skin)
		var sw := maxi(1, int(sub.get_width() * s))
		var sh := maxi(1, int(sub.get_height() * s))
		sub.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
		canvas.blend_rect(sub, Rect2i(Vector2i.ZERO, Vector2i(sw, sh)), Vector2i(int(target.x) - sw / 2, int(target.y) - sh / 2))
	var bb := _opaque_bbox(canvas, Rect2i(Vector2i.ZERO, canvas.get_size()))
	if bb.size.x < 12 or bb.size.y < 8:
		return {}
	var margin := Vector2i(int(bb.size.x * FACE_BBOX_MARGIN), int(bb.size.y * FACE_BBOX_MARGIN))
	bb = Rect2i(bb.position - margin, bb.size + margin * 2).intersection(Rect2i(Vector2i.ZERO, canvas.get_size()))
	print("[FaceApi] refit ok: mode=%d zone=%s scale=%.2f rect=%s" % [mode, zone_mode, s, bb])
	return {"patch": canvas.get_region(bb), "rect": Rect2i(bb.position + head.position, bb.size)}

# 二值掩码的包围盒。
static func _mask_bbox(mask: PackedByteArray, w: int, h: int) -> Rect2i:
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if mask[y * w + x] == 1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# 环形局部反差（模式 2）：像素与半径 5 环形邻域均色的色差 > 40 判为特征候选。
# 镜框/唇线/牙/鼻孔的局部色差大；皮肤明暗渐变是低频信号，环形均值跟随得到，反差小。
const CONTRAST_RING_R := 5
const CONTRAST_THRESHOLD := 40.0

static func _local_contrast_mask(img: Image, ref_img: Image, head: Rect2i, win: Rect2i, area: Rect2i) -> PackedByteArray:
	var fw := win.size.x
	var fh := win.size.y
	var mask := PackedByteArray()
	mask.resize(fw * fh)
	var ring: Array[Vector2i] = []
	for a in range(12):
		var ang := TAU * a / 12.0
		ring.append(Vector2i(int(round(cos(ang) * CONTRAST_RING_R)), int(round(sin(ang) * CONTRAST_RING_R))))
	var r := area.intersection(Rect2i(Vector2i.ZERO, Vector2i(fw, fh)))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := img.get_pixel(head.position.x + win.position.x + x, head.position.y + win.position.y + y)
			if p.a < 0.5:
				continue
			var rp := ref_img.get_pixel(head.position.x + win.position.x + x, head.position.y + win.position.y + y)
			if rp.a >= 0.5 and _channel_distance(p, rp) <= FACE_DIFF_TOLERANCE:
				continue
			var sum := Vector3.ZERO
			var n := 0
			for off in ring:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or nx >= fw or ny < 0 or ny >= fh:
					continue
				var c := img.get_pixel(head.position.x + win.position.x + nx, head.position.y + win.position.y + ny)
				if c.a < 0.5:
					continue
				sum += Vector3(c.r, c.g, c.b)
				n += 1
			if n < 6:
				continue
			if _channel_distance(p, Color(sum.x / n, sum.y / n, sum.z / n)) > CONTRAST_THRESHOLD:
				mask[y * fw + x] = 1
	return mask

# 带内特征并集（模式 2）：逐行取肤区左右端点之间（脸廓内，头发自然排除）的反差像素，
# 聚类后以最大簇为锚、并入纵向相近的簇——双镜片+镜桥并成眼区，唇+牙并成嘴，刘海/杂斑排除。
static func _band_features(feat: PackedByteArray, closed: PackedByteArray, fw: int, fh: int, band: Rect2i, min_px: int) -> Dictionary:
	var cand := PackedByteArray()
	cand.resize(fw * fh)
	for y in range(maxi(0, band.position.y), mini(fh, band.end.y)):
		var left := -1
		var right := -1
		for x in range(fw):
			if closed[y * fw + x] == 1:
				if left < 0:
					left = x
				right = x
		if left < 0 or right - left < 8:
			continue
		for x in range(left + 1, right):
			var idx := y * fw + x
			if feat[idx] == 1:
				cand[idx] = 1
	var clusters := _cluster_mask(cand, fw, fh)
	if clusters.is_empty():
		return {}
	clusters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.area) > int(b.area))
	var anchor: Dictionary = clusters[0]
	var anchor_cy: float = anchor.centroid.y
	var band_h := float(maxi(1, band.size.y))
	var pixels := PackedInt32Array()
	var bbox: Rect2i = anchor.bbox
	var sx := 0.0
	var sy := 0.0
	for c in clusters:
		if absf(c.centroid.y - anchor_cy) > band_h * 0.45:
			continue
		bbox = bbox.merge(c.bbox)
		pixels.append_array(c.pixels)
		sx += c.centroid.x * int(c.area)
		sy += c.centroid.y * int(c.area)
	if pixels.size() < min_px:
		return {}
	return {
		"pixels": pixels,
		"bbox": bbox,
		"centroid": Vector2(sx / pixels.size(), sy / pixels.size()),
		"area": pixels.size(),
	}


# 两阶段入口：稀疏差分（AI 只画五官）→ 全脸重绘（AI 改了肤色/头发，在五官窗内按肤色反差分离）。
static func _build_refit_patch(look_aligned: Image, ref_img: Image, head: Rect2i) -> Dictionary:
	var sparse := _face_diff_mask(look_aligned, ref_img, head)
	var clusters := _cluster_mask(sparse.mask, sparse.w, sparse.h)
	var roles := _classify_features(clusters, sparse.w, sparse.h, 0.35, 0.80)
	if _roles_valid(roles):
		for c: Dictionary in clusters:
			c["stride"] = sparse.w
		return _compose_refit_patch(look_aligned, ref_img, head, clusters, roles, 0, Color.WHITE)
	print("[FaceApi] refit sparse invalid: %d clusters, roles=%s" % [clusters.size(), roles])
	var hw := head.size.x
	var hh := head.size.y
	var win := Rect2i(int(FACE_WINDOW.position.x * hw), int(FACE_WINDOW.position.y * hh), int(FACE_WINDOW.size.x * hw), int(FACE_WINDOW.size.y * hh))
	win = win.intersection(Rect2i(Vector2i.ZERO, head.size))
	if win.size.x < 20 or win.size.y < 20:
		return {}
	var skin := Color.WHITE
	var flood := _skin_region_flood(look_aligned, head.position + win.position, win.size)
	if flood.is_empty():
		print("[FaceApi] refit full-face: no skin region found")
		return {}
	skin = flood.skin
	# 特征检测（v5）：肤区只负责定脸型框与脸内门控；五官本体用环形局部反差检测——
	# 镜框/唇/牙/鼻孔相对周边皮肤反差大，皮肤自身的明暗渐变与高光反差小，天然分离。
	var fw := win.size.x
	var fh := win.size.y
	var region: PackedByteArray = flood.region
	var closed := _erode_mask(_dilate_mask(region, fw, fh, 4), fw, fh, 4)
	var fbox := _mask_bbox(closed, fw, fh)
	if fbox.size.x < 20 or fbox.size.y < 20:
		print("[FaceApi] refit full-face: skin region bbox too small")
		return {}
	var feat := _local_contrast_mask(look_aligned, ref_img, head, win, fbox)
	# 脸型比例先验（"大多数脸型"的五官分布）：眼带/嘴带按肤区 bbox 划分，带内反差簇分别并成眼区与嘴。
	var eye_band := Rect2i(fbox.position + Vector2i(0, int(fbox.size.y * 0.28)), Vector2i(fbox.size.x, int(fbox.size.y * 0.34)))
	var mouth_band := Rect2i(fbox.position + Vector2i(int(fbox.size.x * 0.20), int(fbox.size.y * 0.62)), Vector2i(int(fbox.size.x * 0.60), int(fbox.size.y * 0.35)))
	var zone := _band_features(feat, closed, fw, fh, eye_band, 60)
	var mouth_c := _band_features(feat, closed, fw, fh, mouth_band, 30)
	if zone.is_empty() or mouth_c.is_empty():
		print("[FaceApi] refit full-face invalid: skin=%s region=%d fbox=%s zone=%d mouth=%d" % [skin, int(flood.count), fbox, int(zone.get("area", 0)), int(mouth_c.get("area", 0))])
		return {}
	var kept: Array[Dictionary] = [mouth_c, zone]
	var wroles := {"eye_l": -1, "eye_r": -1, "eye_zone": 1, "mouth": 0, "brow_l": -1, "brow_r": -1, "nose": -1}
	# 平移回头部局部坐标（pixel 索引按头部宽度重编码）。
	for c: Dictionary in kept:
		var rebased := PackedInt32Array()
		for m: int in c.pixels:
			var px: int = m % fw + win.position.x
			var py: int = m / fw + win.position.y
			rebased.append(py * hw + px)
		c["pixels"] = rebased
		c["bbox"] = Rect2i(c.bbox.position + win.position, c.bbox.size)
		c["centroid"] = c.centroid + Vector2(win.position)
		c["stride"] = hw
	return _compose_refit_patch(look_aligned, ref_img, head, kept, wroles, 1, skin)

# 失败返回空 Image，调用方走兜底。look 须已过 cutout_character（透明底）。
static func bake_face_into_sheet(look: Image, ref: Image, sheet: Image, hframes: int, vframes: int, frame_count: int) -> Image:
	if look == null or ref == null or sheet == null:
		return Image.new()
	# duplicate() 声明返回 Resource，显式标注回 Image 让下游 := 推断成立。
	var look_img: Image = look.duplicate()
	var ref_img: Image = ref.duplicate()
	var sheet_img: Image = sheet.duplicate()
	for img: Image in [look_img, ref_img, sheet_img]:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
	var ref_bbox := _opaque_bbox(ref_img, Rect2i(Vector2i.ZERO, ref_img.get_size()))
	if ref_bbox.size.x <= 0:
		return Image.new()
	var head := _light_region_bbox(ref_img, ref_bbox)
	if head.size.x <= 0:
		return Image.new()
	# 对齐：先按整体角色 bbox，被拒再按头部亮区；两种都失败说明输出不是预期的角色立绘。
	var look_aligned := _align_look_by_body(look_img, ref_img.get_size(), ref_bbox)
	if look_aligned.is_empty():
		look_aligned = _align_look_by_head(look_img, ref_img.get_size(), head)
	if look_aligned.is_empty():
		print("[FaceApi] bake aborted: no alignment strategy accepted")
		return Image.new()
	# 优先五官重拟合：从 look 分离五官、按角色标准布局（CANON_*）重排成单层贴片，
	# 避免"整脸贴纸"盖住角色。分离失败时回退整片差分贴片（旧路径），保证总有结果。
	var patch := Image.new()
	var face := Rect2i()
	var refit := _build_refit_patch(look_aligned, ref_img, head)
	if not refit.is_empty():
		patch = refit.patch
		face = refit.rect
	else:
		print("[FaceApi] refit failed, fallback to whole-patch diff")
		# 差分取脸：只在"ref 上是头部亮色、look 对应处不透明"的像素里找色差超阈的点。
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		for y in range(head.position.y, head.end.y):
			for x in range(head.position.x, head.end.x):
				var rp := ref_img.get_pixel(x, y)
				if rp.a < 0.5 or rp.r < HEAD_LIGHT_MIN.r or rp.g < HEAD_LIGHT_MIN.g or rp.b < HEAD_LIGHT_MIN.b:
					continue
				var lp := look_aligned.get_pixel(x, y)
				if lp.a > 0.5 and _channel_distance(lp, rp) > FACE_DIFF_TOLERANCE:
					xs.append(x)
					ys.append(y)
		if xs.size() < FACE_MIN_PIXELS:
			print("[FaceApi] bake aborted: only %d face diff pixels" % xs.size())
			return Image.new()
		# 2%..98% 分位裁剪掉离群噪点，再外扩余量包住腮红等弱信号。
		xs.sort()
		ys.sort()
		var lo := int(xs.size() * 0.02)
		var hi := mini(xs.size() - 1, int(xs.size() * 0.98))
		face = Rect2i(xs[lo], ys[lo], maxi(1, xs[hi] - xs[lo]), maxi(1, ys[hi] - ys[lo]))
		var margin := Vector2i(int(face.size.x * FACE_BBOX_MARGIN), int(face.size.y * FACE_BBOX_MARGIN))
		face = Rect2i(face.position - margin, face.size + margin * 2).intersection(head)
		# 脸部贴片：颜色取 look，alpha 由色差软阈值生成——只叠五官笔触，保留头部原有明暗。
		# ref 透明的像素（耳间空隙等）必须跳过：场景输出的对齐图在那里是不透明天空，没有这道闸会漏进贴片。
		patch = Image.create(face.size.x, face.size.y, false, Image.FORMAT_RGBA8)
		for y in range(face.size.y):
			for x in range(face.size.x):
				var rp := ref_img.get_pixel(face.position.x + x, face.position.y + y)
				var lp := look_aligned.get_pixel(face.position.x + x, face.position.y + y)
				var a := clampf((_channel_distance(lp, rp) - FACE_ALPHA_SOFT_START) / FACE_ALPHA_SOFT_RANGE, 0.0, 1.0)
				if rp.a < 0.5 or lp.a < 0.5:
					a = 0.0
				patch.set_pixel(x, y, Color(lp.r, lp.g, lp.b, a))
	# 脸部相对头部亮区的归一化位置，逐帧按该帧头部亮区还原（跟随帧间挤压/晃动）。
	var face_rel := Rect2(
		float(face.position.x - head.position.x) / head.size.x,
		float(face.position.y - head.position.y) / head.size.y,
		float(face.size.x) / head.size.x,
		float(face.size.y) / head.size.y)
	var cw := sheet_img.get_width() / hframes
	var ch := sheet_img.get_height() / vframes
	for i in range(frame_count):
		var cell := Rect2i((i % hframes) * cw, (i / hframes) * ch, cw, ch)
		var fhead := _light_region_bbox(sheet_img, cell)
		if fhead.size.x <= 0:
			# ref 与帧 0 的格内摆位一致，检测失败时按立绘头部矩形原位贴。
			fhead = Rect2i(cell.position + head.position, head.size)
		var local := fhead.position - cell.position
		var dst := Rect2i(
			local.x + int(face_rel.position.x * fhead.size.x),
			local.y + int(face_rel.position.y * fhead.size.y),
			maxi(1, int(face_rel.size.x * fhead.size.x)),
			maxi(1, int(face_rel.size.y * fhead.size.y)))
		var scaled: Image = patch.duplicate()
		scaled.resize(dst.size.x, dst.size.y, Image.INTERPOLATE_LANCZOS)
		sheet_img.blend_rect(scaled, Rect2i(Vector2i.ZERO, dst.size), cell.position + dst.position)
	return sheet_img

# 导出包里 res:// 纹理已导入为 .ctex，Image.load 读不到原始 PNG，必须走 ResourceLoader（编辑器与导出包通用）。
static func load_image_resource(path: String) -> Image:
	if ResourceLoader.exists(path):
		var tex := ResourceLoader.load(path) as Texture2D
		if tex:
			return tex.get_image()
	var image := Image.new()
	if image.load(path) == OK:
		return image
	return null

func _request_cloud_swap(photo: Image, ref: Image) -> void:
	_last_full_character = true
	var composite := _build_composite(ref, photo)
	var parts: Array[PackedByteArray] = [
		_text_part(boundary, "model", model),
		_text_part(boundary, "prompt", FeaturePrompt.TEXT),
		_image_part(boundary, "image", "photo.png", image.save_png_to_buffer()),
		_text_part(boundary, "output_format", "png"),
	]
	if not image_size.is_empty():
		parts.append(_text_part(boundary, "size", image_size))
	if not quality.is_empty():
		parts.append(_text_part(boundary, "quality", quality))
	_send(parts)

func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return "请求成功"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "响应数据长度不匹配"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接服务器"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "域名解析失败"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接错误"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS 握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "服务器无响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "响应体超出大小限制"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "响应解压失败"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "请求失败"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "无法打开下载文件"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "下载文件写入失败"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "重定向次数超限"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时"
		_:
			return "网络错误 %d" % result

func _server_message(body: PackedByteArray) -> String:
	var text := body.get_string_from_utf8()
	var message := ""
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		var err = parsed.get("error")
		if err is Dictionary and err.has("message"):
			message = String(err["message"])
	if message.is_empty():
		message = text.strip_edges()
	if message.length() > 160:
		message = message.substr(0, 160) + "…"
	return message

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _waiting:
		return
	_waiting = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_retry_or_fail("网络请求失败：%s。" % _result_text(result))
		return
	if code < 200 or code >= 300:
		_retry_or_fail("服务拒绝了请求（HTTP %d）：%s" % [code, _server_message(body)])
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var data: Variant = parsed.get("data") if parsed is Dictionary else null
	if not data is Array or data.is_empty():
		print("[FaceApi] HTTP %d unrecognized body: %s" % [code, body.get_string_from_utf8().substr(0, 300)])
		failed.emit("服务返回格式无法识别。")
		return
	if not data[0] is Dictionary:
		print("[FaceApi] HTTP %d unexpected data[0]: %s" % [code, body.get_string_from_utf8().substr(0, 300)])
		failed.emit("服务返回格式无法识别。")
		return
	var item: Dictionary = data[0]
	print("[FaceApi] HTTP %d body=%d bytes, data[0] keys=%s" % [code, body.size(), item.keys()])
	if item.has("revised_prompt"):
		print("[FaceApi] revised_prompt: %s" % String(item["revised_prompt"]).substr(0, 200))
	if item.has("b64_json"):
		var image := Image.new()
		var raw := Marshalls.base64_to_raw(String(item["b64_json"]))
		print("[FaceApi] b64_json decoded bytes=%d" % raw.size())
		if image.load_png_from_buffer(raw) == OK:
			completed.emit(image, _last_full_character)
		else:
			failed.emit("返回的图片无法解码。")
	elif item.has("url"):
		var err := _fetch.request(String(item["url"]))
		if err != OK:
			failed.emit("下载结果图失败（%d）。" % err)
		else:
			_waiting = true
			_arm_timeout()
	else:
		failed.emit("服务未返回图片。")

func _on_fetch_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _waiting:
		return
	_waiting = false
	print("[FaceApi] fetch result=%d code=%d bytes=%d" % [result, code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("下载结果图失败：%s。" % _result_text(result))
		return
	if code != 200:
		failed.emit("下载结果图被拒绝（HTTP %d）：%s" % [code, _server_message(body)])
		return
	var image := Image.new()
	if image.load_png_from_buffer(body) == OK or image.load_jpg_from_buffer(body) == OK or image.load_webp_from_buffer(body) == OK:
		completed.emit(image, _last_full_character)
	else:
		failed.emit("下载的图片无法解码。")
