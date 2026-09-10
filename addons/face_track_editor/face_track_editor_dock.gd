@tool
extends HBoxContainer

const Track = preload("res://scripts/face/face_track.gd")
const Canvas = preload("res://addons/face_track_editor/face_frame_canvas.gd")
var _track := Track.new()
var _canvas: Control
var _path: LineEdit
var _source: LineEdit
var _columns: SpinBox
var _rows: SpinBox
var _count: SpinBox
var _points: SpinBox
var _animation: LineEdit
var _frame: SpinBox
var _point: SpinBox
var _hidden: CheckBox
var _status: Label
var _playing: bool = false
var _clock: float = 0

func _ready() -> void:
	custom_minimum_size.y = 430
	_canvas = Canvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.edited.connect(_on_edited)
	add_child(_canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 540
	add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_path = _edit(panel, "res://assets/pets/face_tracks/character1_walk.tres", "轨迹路径 (.tres)")
	_button(panel, "载入轨迹", _load_track)
	_source = _edit(panel, "res://assets/pets/character1.png", "序列 PNG 或 SpriteFrames.tres")
	_animation = _edit(panel, "walk", "动画名")
	var row := HBoxContainer.new()
	panel.add_child(row)
	_columns = _spin(row, "列", 1, 64, 4)
	_rows = _spin(row, "行", 1, 64, 9)
	_count = _spin(row, "帧数", 1, 4096, 33)
	_points = _spin(row, "轮廓点数", 4, 64, 12)
	_button(panel, "从序列新建（替换未保存草稿）", _new_track)
	row = HBoxContainer.new()
	panel.add_child(row)
	_frame = _spin(row, "帧", 0, 32, 0)
	_point = _spin(row, "点编号", 0, 11, 0)
	_frame.value_changed.connect(func(_v: float) -> void: _refresh())
	_point.value_changed.connect(func(v: float) -> void:
		_canvas.active = int(v)
		_canvas.queue_redraw())
	var move := CheckBox.new()
	move.text = "拖动整个轮廓"
	move.toggled.connect(func(v: bool) -> void: _canvas.move_all = v)
	panel.add_child(move)
	_hidden = CheckBox.new()
	_hidden.text = "当前帧隐藏五官（背面/遮挡）"
	_hidden.toggled.connect(func(v: bool) -> void:
		var index := int(_frame.value)
		if v and not _track.hidden_frames.has(index):
			_track.hidden_frames.append(index)
		elif not v:
			var where := _track.hidden_frames.find(index)
			if where >= 0:
				_track.hidden_frames.remove_at(where))
	panel.add_child(_hidden)
	_button(panel, "复制前一帧", func() -> void:
		if _frame.value > 0:
			_track.frames[int(_frame.value)] = _track.get_contour(int(_frame.value) - 1)
			_refresh())
	_button(panel, "清除当前关键帧（第0帧保留）", func() -> void:
		if _frame.value > 0:
			_track.frames.erase(int(_frame.value))
			_refresh())
	_button(panel, "播放 / 暂停轮廓预览", func() -> void: _playing = not _playing)
	_button(panel, "校验并保存轨迹", _save_track)
	_button(panel, "将路径中的旧三点 .tres 导入为草稿", _import_legacy)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)
	_load_track()

func _process(delta: float) -> void:
	if _playing:
		_clock += delta
		if _clock >= 0.1:
			_clock = 0
			_frame.value = (int(_frame.value) + 1) % _track.source_frame_count

func _edit(parent: Node, value: String, hint: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = hint
	edit.tooltip_text = hint
	parent.add_child(edit)
	return edit

func _spin(parent: Node, title: String, low: float, high: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.prefix = title
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	parent.add_child(spin)
	return spin

func _button(parent: Node, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)

func _load_track() -> void:
	if not ResourceLoader.exists(_path.text):
		_status.text = "轨迹路径不存在。请检查路径或从序列新建。"
		return
	var resource := ResourceLoader.load(_path.text, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is PetFaceTrack:
		_status.text = "不是版本2轮廓轨迹；旧三点数据请使用专门导入按钮。"
		return
	_track = resource.duplicate(true)
	_source.text = _track.source_texture_path
	_columns.value = _track.source_columns
	_rows.value = _track.source_rows
	_count.value = _track.source_frame_count
	_animation.text = String(_track.animation_name)
	_refresh()

func _new_track() -> void:
	if not ResourceLoader.exists(_source.text):
		_status.text = "找不到序列资源。请使用主项目内 res:// 路径。"
		return
	var source := load(_source.text)
	var dimensions := Vector2.ZERO
	var count := int(_count.value)
	if source is Texture2D:
		dimensions = source.get_size() / Vector2(_columns.value, _rows.value)
	elif source is SpriteFrames and source.has_animation(_animation.text):
		count = source.get_frame_count(_animation.text)
		if count > 0:
			dimensions = source.get_frame_texture(_animation.text, 0).get_size()
	if dimensions == Vector2.ZERO:
		_status.text = "无法读取序列尺寸或动画名。"
		return
	_track = Track.new()
	_track.source_texture_path = _source.text
	_track.source_columns = int(_columns.value) if source is Texture2D else count
	_track.source_rows = int(_rows.value) if source is Texture2D else 1
	_track.source_frame_count = count
	_track.animation_name = StringName(_animation.text)
	_track.frame_size = dimensions
	_track.frames[0] = _ellipse(dimensions * Vector2(0.5, 0.5), dimensions * Vector2(0.25, 0.2), int(_points.value))
	_track.provenance = "开发者新建轮廓；按同序点校正各帧。"
	_frame.value = 0
	_refresh()

static func _ellipse(origin: Vector2, radius: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in count:
		var angle := -PI * 0.5 + TAU * i / count
		points.append(origin + Vector2(cos(angle), sin(angle)) * radius)
	return points

func _on_edited(points: PackedVector2Array) -> void:
	_track.frames[int(_frame.value)] = points.duplicate()
	_point.set_value_no_signal(_canvas.active)
	var error := _track.validate()
	_status.text = "未保存。" if error.is_empty() else error

func _refresh() -> void:
	_frame.max_value = _track.source_frame_count - 1
	_canvas.texture = _track.frame_texture(int(_frame.value))
	_canvas.points = _track.get_contour(int(_frame.value))
	_point.max_value = maxi(0, _canvas.points.size() - 1)
	_canvas.active = mini(_canvas.active, int(_point.max_value))
	_hidden.set_pressed_no_signal(_track.hidden_frames.has(int(_frame.value)))
	_canvas.queue_redraw()
	_status.text = "帧 %d / %d · %s\n%s" % [int(_frame.value), _track.source_frame_count - 1, "关键帧" if _track.frames.has(int(_frame.value)) else "插值帧", _track.provenance]

func _save_track() -> void:
	var error := _track.validate()
	if not error.is_empty():
		_status.text = error
		return
	if not _path.text.begins_with("res://") or _path.text.begins_with("res://addons/"):
		_status.text = "请保存到主项目 addons 以外的 res:// 路径。"
		return
	var result := ResourceSaver.save(_track, _path.text)
	_status.text = "已保存：" + _path.text if result == OK else "保存失败：%d" % result

func _import_legacy() -> void:
	# Parse only the old serialized point assignments; do not load editor scripts
	# from the reference project or execute arbitrary Resource expressions.
	if not FileAccess.file_exists(_path.text):
		_status.text = "旧轨迹路径不存在。"
		return
	var text := FileAccess.get_file_as_string(_path.text)
	var frame_regex := RegEx.new()
	frame_regex.compile('(?s)(\\d+): \\{(.*?)\\}')
	var point_regex := RegEx.new()
	point_regex.compile('"(left|right|mouth)": Vector2\\(([-0-9.]+), ([-0-9.]+)\\)')
	var converted: Dictionary = {}
	for frame_match: RegExMatch in frame_regex.search_all(text):
		var points: Dictionary = {}
		for point_match: RegExMatch in point_regex.search_all(frame_match.get_string(2)):
			points[point_match.get_string(1)] = Vector2(float(point_match.get_string(2)), float(point_match.get_string(3)))
		if points.size() == 3:
			var left: Vector2 = points.left
			var right: Vector2 = points.right
			var mouth: Vector2 = points.mouth
			var eyes := (left + right) * 0.5
			converted[int(frame_match.get_string(1))] = _ellipse(eyes.lerp(mouth, 0.4), Vector2(left.distance_to(right) * 0.85, eyes.distance_to(mouth) * 1.3), int(_points.value))
	if not converted.has(0):
		_status.text = "旧格式未找到第0帧完整三点。"
		return
	_new_track()
	_track.frames = converted
	_track.provenance = "旧三点推算椭圆草稿，不是真实轮廓；请逐帧校正后另存。"
	_path.text = "res://assets/pets/face_tracks/imported_contour.tres"
	_refresh()
