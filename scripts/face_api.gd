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
