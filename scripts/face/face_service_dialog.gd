extends AcceptDialog

signal configuration_saved

const Settings = preload("res://scripts/face/face_service_config.gd")
var _address: LineEdit
var _key: LineEdit
var _model: LineEdit
var _models: OptionButton
var _status: Label
var _test: Button
var _http: HTTPRequest
var _tested_base: String
var _tested_key: String

func _ready() -> void:
	title = "生图服务配置"
	dialog_text = ""
	dialog_hide_on_ok = false
	get_ok_button().text = "保存并使用"
	add_cancel_button("取消")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_address = _field(box, "服务地址（自动连接 /images/edits）")
	_key = _field(box, "API Key")
	_key.secret = true
	_model = _field(box, "图生图模型名称（按服务商提供的名称填写）")
	_test = Button.new()
	_test.text = "测试连接 / 获取模型列表"
	_test.custom_minimum_size.y = 48
	_test.pressed.connect(_test_connection)
	box.add_child(_test)
	_models = OptionButton.new()
	_models.add_item("获取列表后可选择模型，也可手动填写")
	_models.disabled = true
	_models.item_selected.connect(func(index: int) -> void: _model.text = _models.get_item_text(index))
	box.add_child(_models)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Key 隐藏显示，仅保存在本机用户目录。连接测试只查询模型，不生成图片。"
	box.add_child(_status)
	_http = HTTPRequest.new()
	_http.timeout = 20
	_http.body_size_limit = 2 * 1024 * 1024
	_http.max_redirects = 0
	_http.request_completed.connect(_on_test_completed)
	add_child(_http)
	confirmed.connect(_save)
	visibility_changed.connect(func() -> void:
		if not visible:
			_http.cancel_request()
			_test.disabled = false
			_tested_key = "")
	var config := Settings.read_config()
	var base := String(config.get_value("api", "base_url", ""))
	if base.is_empty():
		base = String(config.get_value("api", "endpoint", Settings.DEFAULT_URL))
	_address.text = Settings.normalize_url(base)
	_key.text = String(config.get_value("api", "api_key", ""))
	_model.text = String(config.get_value("api", "model", ""))

func _field(parent: Node, title: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.custom_minimum_size.y = 44
	parent.add_child(edit)
	return edit

func _save() -> void:
	var error := Settings.save_config(_address.text, _key.text, _model.text)
	if not error.is_empty():
		_status.text = error
		return
	configuration_saved.emit()
	hide()

func _test_connection() -> void:
	var base := Settings.normalize_url(_address.text)
	var error := Settings.validate(base, _key.text, _model.text, false)
	if not error.is_empty():
		_status.text = error
		return
	_tested_base = base
	_tested_key = _key.text.strip_edges()
	_models.clear()
	_models.disabled = true
	var result := _http.request(base + "/models", PackedStringArray(["Authorization: Bearer " + _tested_key]))
	if result != OK:
		_status.text = "无法发起连接测试（%d）。" % result
		return
	_test.disabled = true
	_status.text = "正在验证连接与 Key……"

func _on_test_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_test.disabled = false
	if Settings.normalize_url(_address.text) != _tested_base or _key.text.strip_edges() != _tested_key:
		_status.text = "配置已修改，请重新测试当前地址和 Key。"
		_tested_key = ""
		return
	_tested_key = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "连接失败或超时，请检查地址和网络（%d）。" % result
		return
	if code < 200 or code >= 300:
		_status.text = "服务返回 HTTP %d。401/403 请检查 Key；404 可能不提供模型列表，可手动填模型后测试生图。" % code
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("data") is Array:
		_status.text = "服务已响应，但模型列表格式不兼容。请手动填写模型名称。"
		return
	for item: Variant in parsed.data:
		if item is Dictionary and item.get("id") is String:
			_models.add_item(item.id)
	_models.disabled = _models.item_count == 0
	_models.select(-1)
	_status.text = "连接成功，返回 %d 个模型。请选择服务商支持图片编辑的模型；列表成功不代表生图已验证。" % _models.item_count
