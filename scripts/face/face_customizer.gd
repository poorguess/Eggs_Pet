class_name FaceCustomizer
extends Control

signal photo_requested
signal service_configuration_saved
signal applied(image: Image, profile: PetFaceProfile)
signal composite_applied(image: Image)
signal cancelled

const Preview = preload("res://scripts/face/face_preview.gd")
const ServiceDialog = preload("res://scripts/face/face_service_dialog.gd")
var track: PetFaceTrack
var draft := PetFaceProfile.new()
var image: Image
# 生图方式：false = 联网 AI 服务，true = 本机离线合成（MediaPipe + warp 烘焙）。
var local_mode := false
# 主岛按 API 配置情况给出的默认（未配置服务时默认本机）。
var default_local := false
var _composite: Image
var _preview: Control
var _status: Label
var _info: Label
var _apply: Button
var _photo: Button
var _cutout: Button
var _service: Button
var _reset_button: Button
var _mode: OptionButton
var _sliders: Dictionary = {}
var _service_dialog: AcceptDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("202933")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	# Portrait phones use a single readable column: preview first, then the
	# scrollable controls. This keeps every touch target inside the safe width.
	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	columns.add_child(left)
	var title := Label.new()
	title.text = "宠物换脸 · 首帧对齐"
	title.add_theme_font_size_override("font_size", 32)
	left.add_child(title)
	_preview = Preview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(240, 260)
	left.add_child(_preview)
	var hint := Label.new()
	hint.text = "在第 0 帧对齐后，五官将随原角色动画运动。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 18)
	scroll.add_child(panel)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(info)
	_info = info
	var mode_label := Label.new()
	mode_label.text = "生成方式"
	panel.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.add_item("AI 生图服务（联网）")
	_mode.add_item("本机合成（离线）")
	_mode.custom_minimum_size.y = 54
	_mode.item_selected.connect(_on_mode_changed)
	panel.add_child(_mode)
	_service = _button(panel, "配置生图服务 / API Key", _open_service_configuration)
	_photo = _button(panel, "拍照 / 选择自拍", func() -> void: photo_requested.emit())
	_cutout = _button(panel, "上传已抠图五官（本地预览）", _choose_cutout)
	_slider(panel, "x", "水平位移", -160, 160, 1, 0)
	_slider(panel, "y", "垂直位移", -160, 160, 1, 0)
	_slider(panel, "zoom", "整体大小", 0.25, 2, 0.01, 1)
	_slider(panel, "aspect", "宽高比例", 0.5, 1.5, 0.01, 1)
	_slider(panel, "rotation", "旋转角度", -45, 45, 1, 0)
	_reset_button = _button(panel, "重置对齐", _reset)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "请生成或上传五官图，确认效果后再应用。"
	panel.add_child(_status)
	_apply = _button(panel, "应用到宠物", func() -> void:
		if _composite != null:
			composite_applied.emit(_composite)
		else:
			applied.emit(image, draft))
	_apply.disabled = true
	_button(panel, "取消", func() -> void: cancelled.emit())
	add_theme_font_size_override("font_size", 24)

func open(data: PetFaceTrack, settings: PetFaceProfile, current: Image) -> void:
	track = data
	draft = PetFaceProfile.new()
	draft.from_dict(settings.to_dict())
	image = current
	_composite = null
	var error := track.validate()
	if not error.is_empty():
		_status.text = "轨迹错误：" + error
		_photo.disabled = true
		_cutout.disabled = true
		_apply.disabled = true
		return
	var local_ok := FaceAnalyzer.is_available()
	_mode.set_item_disabled(1, not local_ok)
	_mode.select(1 if local_ok and default_local else 0)
	_on_mode_changed(_mode.selected)
	_preview.configure(track, draft, ImageTexture.create_from_image(image) if image != null else null)
	_sync_sliders()
	_sync_controls()
	_apply.disabled = image == null
	if image != null:
		_status.text = "已载入当前五官，可继续调节；取消会保留原外貌。"
	visible = true

func set_result(result: Image) -> void:
	_composite = null
	_preview.composite = null
	image = result
	_preview.face = ImageTexture.create_from_image(result)
	_preview.refresh()
	_apply.disabled = false
	_status.text = "生成完成。请检查仅有五官、没有皮肤和身体，调好位置后应用。"
	_sync_controls()

## 本机合成结果：整帧成品图，五官已按模板烘焙到位，位置滑杆不适用。
func set_composite_result(result: Image) -> void:
	_composite = result
	_preview.composite = ImageTexture.create_from_image(result)
	_preview.refresh()
	_apply.disabled = false
	_status.text = "合成完成。确认效果后应用；不满意可重新拍照。"
	_sync_controls()

func set_error(message: String) -> void:
	_status.text = message

func _on_mode_changed(index: int) -> void:
	local_mode = index == 1
	_info.text = ("上传自拍，本机离线把五官合成到角色脸上。\n照片不离开设备，无需网络与 API Key。" if local_mode
		else "上传自拍生成五官\n照片将发送至已配置的生图服务；点击下方按钮后确认上传。")
	_service.disabled = local_mode

## 滑杆只服务于 AI 五官贴层；本机合成结果是成品整帧，位置已烘焙。
func _sync_controls() -> void:
	var adjusting := _composite == null
	for key: String in _sliders:
		_sliders[key].editable = adjusting
	if _reset_button != null:
		_reset_button.disabled = not adjusting

func _open_service_configuration() -> void:
	if _service_dialog == null:
		_service_dialog = ServiceDialog.new()
		add_child(_service_dialog)
		_service_dialog.configuration_saved.connect(func() -> void:
			service_configuration_saved.emit()
			_status.text = "服务配置已保存并生效，可选择自拍测试生图。")
	_service_dialog.popup_centered(Vector2i(760, 620))

func _choose_cutout() -> void:
	var dialog := FileDialog.new()
	dialog.title = "选择已抠图的透明五官图片"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.png,*.webp ; 透明五官图片"])
	dialog.size = Vector2i(900, 600)
	dialog.file_selected.connect(func(path: String) -> void:
		import_cutout(path)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func import_cutout(path: String) -> void:
	var imported := Image.new()
	if imported.load(path) != OK:
		set_error("图片读取失败，请选择透明 PNG 或 WebP。")
		return
	if imported.detect_alpha() == Image.ALPHA_NONE:
		set_error("图片没有透明区域，请先抠图后再上传。")
		return
	var bounds := imported.get_used_rect()
	if not bounds.has_area():
		set_error("图片完全透明，没有可显示的五官。")
		return
	# Tight cutouts are valid here: preserve their proportions and add a clear
	# margin rather than applying the model-output boundary/coverage rules.
	imported = imported.get_region(bounds)
	imported.convert(Image.FORMAT_RGBA8)
	var longest := maxi(imported.get_width(), imported.get_height())
	if longest > 400:
		var ratio := 400.0 / longest
		imported.resize(maxi(1, int(imported.get_width() * ratio)), maxi(1, int(imported.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var side := maxi(32, ceili(maxi(imported.get_width(), imported.get_height()) * 1.25))
	var padded := Image.create(side, side, false, Image.FORMAT_RGBA8)
	padded.fill(Color.TRANSPARENT)
	padded.blit_rect(imported, Rect2i(Vector2i.ZERO, imported.get_size()), (Vector2i(side, side) - imported.get_size()) / 2)
	set_result(padded)
	_status.text = "已载入本地五官图，未发送至生图服务。调好位置后点击应用。"

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _slider(parent: Node, key: String, label: String, low: float, high: float, step: float, value: float) -> void:
	var caption := Label.new()
	parent.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 44
	parent.add_child(slider)
	_sliders[key] = slider
	slider.value_changed.connect(func(amount: float) -> void:
		caption.text = "%s  %.2f" % [label, amount]
		match key:
			"x": draft.offset.x = amount
			"y": draft.offset.y = amount
			"zoom": draft.zoom = amount
			"aspect": draft.aspect = amount
			"rotation": draft.rotation = deg_to_rad(amount)
		if _preview != null:
			_preview.refresh())
	caption.text = "%s  %.2f" % [label, value]

func _sync_sliders() -> void:
	_sliders.x.value = draft.offset.x
	_sliders.y.value = draft.offset.y
	_sliders.zoom.value = draft.zoom
	_sliders.aspect.value = draft.aspect
	_sliders.rotation.value = rad_to_deg(draft.rotation)

func _reset() -> void:
	draft.offset = Vector2.ZERO
	draft.zoom = 1
	draft.aspect = 1
	draft.rotation = 0
	_sync_sliders()
	_preview.refresh()
