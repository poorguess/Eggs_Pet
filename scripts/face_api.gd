class_name FaceApi
extends Node

signal completed(image: Image, full_character: bool)
signal failed(message: String)

const CONFIG_PATH_USER := "user://face_api.cfg"
const CONFIG_PATH_RES := "res://face_api.cfg"
# 上游网关限制：输入图总像素须 ≤ 196608（实测阈值），多图表单不被支持，故把角色图与真人照拼成单张参考图上传。
const COMPOSITE_SIZE := Vector2i(512, 384)
const FALLBACK_AVATAR_SIZE := 400
const LEGACY_PROMPT := "把照片中的人脸变成黑白漫画表情包风格的头像：必须严格保留此人的性别、脸型、发型、眼镜等配饰与五官特征，让朋友一眼认出是本人；正面居中构图，头部占满画面；不要画任何背景、边框或文字。"
# 通用换脸提示词（角色无关），设计说明见 docs/face_swap_prompt.md。
const DEFAULT_PROMPT := "这是一张左右拼接的参考图：左半部分是一张游戏角色图，右半部分是一张真人照片。请完成一次「保身份换脸」：把右半人物的长相移植到左半角色的脸上。按以下步骤处理：1) 从右半真人照片中提取此人的身份特征：脸型轮廓与比例、眼睛形状与间距、眉毛、鼻子、嘴部与表情、肤色，以及标志性特征（眼镜、胡须、痣、发型轮廓）；2) 分析左半角色的脸部结构与画风：它有哪些五官、各自位置、线条粗细、配色与阴影方式；3) 只重绘角色的五官，使其一眼可辨是右半照片本人——将真人的眼睛、眉毛、嘴部表情与脸型特征映射到角色对应的五官上；角色没有的五官（如鼻子、耳朵）不要凭空添加；真人特征必须改用角色的画风重新绘制（同样的笔触、线宽、配色、阴影），严禁照片直接拼贴或写实风格。硬性约束：输出图只画游戏角色本身，不要输出拼接参考图；除脸部/头部区域外的一切保持不变，包括身体、四肢、姿势、服装、配饰、配色、背景、光影与构图；不添加文字、水印、边框或新道具；成品必须仍是同一个角色，只是脸变成了照片中的人。"
# 协议级约束，代码侧强制（不依赖 cfg）：成品要叠到岛屿场景，必须透明背景。
# 注意：此网关的 /images/edits 对 background=transparent 表单字段稳定 400，只能走提示词。
const TRANSPARENT_BG_SUFFIX := "\n补充硬性约束：输出 PNG 必须带 alpha 通道，角色以外的区域完全透明（alpha=0），不要任何底色、描边光晕、边框或背景。"

var endpoint := ""
var base_url := ""
var api_key := ""
var model := ""
var prompt := DEFAULT_PROMPT
var character_ref := ""
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
		prompt = String(config.get_value("api", "prompt", DEFAULT_PROMPT))
		character_ref = String(config.get_value("api", "character_ref", ""))
		image_size = String(config.get_value("api", "size", ""))
		quality = String(config.get_value("api", "quality", ""))
	if endpoint.is_empty() and not base_url.is_empty():
		endpoint = base_url.rstrip("/") + "/images/edits"
	if base_url.is_empty() or api_key.is_empty():
		endpoint = ""
		config_error = "未配置图生图 API（face_api.cfg 缺失）。"
	print("[FaceApi] config loaded=%s endpoint=%s model=%s character_ref=%s key_set=%s" % [loaded, endpoint, model, character_ref, not api_key.is_empty()])
	if not config_error.is_empty():
		push_warning("FaceApi: " + config_error)

func process_photo(photo: Image) -> void:
	if photo == null or photo.is_empty():
		failed.emit("没有可用的照片。")
		return
	if _waiting:
		print("[FaceApi] process_photo ignored: request already in flight")
		return
	if not config_error.is_empty():
		failed.emit(config_error)
		return
	_attempt = 0
	var ref := _load_character_ref()
	if ref:
		print("[FaceApi] pipeline=swap ref=%dx%d photo=%dx%d" % [ref.get_width(), ref.get_height(), photo.get_width(), photo.get_height()])
		_request_cloud_swap(photo, ref)
	else:
		print("[FaceApi] pipeline=fallback_avatar photo=%dx%d" % [photo.get_width(), photo.get_height()])
		_request_cloud(photo)

static func crop_square(photo: Image) -> Image:
	var image := photo.duplicate()
	var side := mini(image.get_width(), image.get_height())
	var region := Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side)
	return image.get_region(region)

func _load_character_ref() -> Image:
	if character_ref.is_empty():
		return null
	var image: Image = null
	# 导出包里 res:// 纹理已被导入为 .ctex，Image.load 读不到原始 PNG，必须走 ResourceLoader（编辑器与导出包通用）。
	var tex: Texture2D = null
	if ResourceLoader.exists(character_ref):
		tex = ResourceLoader.load(character_ref) as Texture2D
	if tex:
		image = tex.get_image()
	else:
		var file_image := Image.new()
		if file_image.load(character_ref) == OK:
			image = file_image
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
		var id := _request_id
		await get_tree().create_timer(1.5 * _attempt).timeout
		# 退避期间被 cancel() 或新流程取代时，旧重试链不再重发（否则会对忙的 _http 误报 ERR_BUSY）。
		if id != _request_id:
			return
		_send_now()
	else:
		failed.emit(message)

func _request_cloud(photo: Image) -> void:
	_last_full_character = false
	var image := crop_square(photo)
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

func _request_cloud_swap(photo: Image, ref: Image) -> void:
	_last_full_character = true
	var composite := _build_composite(ref, photo)
	var parts: Array[PackedByteArray] = [
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "model", model),
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "prompt", prompt + TRANSPARENT_BG_SUFFIX),
		_image_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "image", "reference.png", composite.save_png_to_buffer()),
		_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "output_format", "png"),
	]
	if not image_size.is_empty():
		parts.append(_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "size", image_size))
	if not quality.is_empty():
		parts.append(_text_part("GodotFaceApiBoundary7MA4YWxkTrZu0gW", "quality", quality))
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
