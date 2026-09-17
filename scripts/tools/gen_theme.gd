extends SceneTree

# 从 scripts/ui_theme.gd 的常量生成 ui/theme.tres，并在每个字面值旁标注它来自哪个常量。
# 生成物入库（项目没有 CI 生成步骤），但请勿手工编辑：在 Godot 编辑器里 Ctrl+S 保存会丢掉 `;` 注释。
#
# 用法：
#   Godot --headless --path . --script res://scripts/tools/gen_theme.gd
#
# 真源是 scripts/ui_theme.gd。改调色板/圆角/字号请改那里，然后重跑本脚本。

const OUTPUT_PATH := "res://ui/theme.tres"

# 设计里糖果按钮的高（main_island 的 _hatch_boost_rect / _face_dialog_button 都是 280x88）。
const BUTTON_HEIGHT := 88.0
# 实测 Button(text).get_minimum_size().y == 88 所需的上下留白；生成时按实际字体度量重算并核对。
const BUTTON_MARGIN_Y_EXPECTED := 23.0
# 水平内边距。ui_style_guide.md §5.1 写的是 56px（最小宽 240px），这里沿用 40px 是为了与改造前
# 的 ui/theme.tres 语义一致；各场景都显式给了按钮宽度，该值只影响最小宽，不影响现有渲染。
# 是否对齐 §5.1 由 lead 定夺。
const BUTTON_CONTENT_MARGIN_X := 40.0
# StyleBox 拿不到控件高度，用足够大的半径近似「圆角 = 高度/2」的药丸形。
const PILL_RADIUS := 999
# 对应 main_island 倒计时描边的 draw_string_outlined(..., outline_width = 2.0)。
const OUTLINE_WIDTH := 2

var _sub_resources := PackedStringArray()
var _items := PackedStringArray()


func _initialize() -> void:
	var font := ThemeDB.fallback_font
	var line_height := font.get_height(UiTheme.FONT_BODY)
	var button_margin_y := (BUTTON_HEIGHT - line_height) * 0.5
	if button_margin_y != BUTTON_MARGIN_Y_EXPECTED:
		# 默认字体度量变了就会走到这里：Button(text) 的最小高不再等于设计里的 88px。
		push_warning("FONT_BODY 行高 %d 推出上下留白 %s，与实测的 %s 不符" % [
			line_height, _num(button_margin_y), _num(BUTTON_MARGIN_Y_EXPECTED)])

	_build_styleboxes(button_margin_y, line_height)
	_build_theme_items()

	# 块之间空一行，与 Godot 自身的序列化排版一致，便于和改造前的文件做 diff。
	var parts := PackedStringArray()
	parts.append("[gd_resource type=\"Theme\" load_steps=%d format=3]" % (_sub_resources.size() + 1))
	parts.append(_header())
	parts.append_array(_sub_resources)
	parts.append("[resource]\n%s" % "\n".join(_items))
	var text := "\n\n".join(parts) + "\n"

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 %s：%s" % [OUTPUT_PATH, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("已生成 ", OUTPUT_PATH, "（", _sub_resources.size(), " 个 StyleBox + ", _items.size(), " 个主题项）")
	quit(0)


func _header() -> String:
	return """; 本文件由 scripts/tools/gen_theme.gd 生成，请勿手工编辑。
; 在 Godot 编辑器里打开并 Ctrl+S 保存会丢失下面的注释，恢复方式是重新运行生成器：
;   Godot --headless --path . --script res://scripts/tools/gen_theme.gd
; 数值真源是 scripts/ui_theme.gd；每个字面值后的注释标注它对应哪个常量。"""


func _build_styleboxes(button_margin_y: float, line_height: int) -> void:
	var margin_note := "上下 %s*2 + FONT_BODY(%d) 行高 %d = %dpx，对齐设计里 %dx%d 的糖果按钮" % [
		_num(button_margin_y), UiTheme.FONT_BODY, line_height,
		int(BUTTON_HEIGHT), 280, int(BUTTON_HEIGHT)]

	_sub("StyleBoxFlat_panel", PackedStringArray([
		_bg(UiTheme.CREAM, "CREAM"),
		_corners(int(UiTheme.RADIUS_PANEL), "RADIUS_PANEL"),
	]))
	_sub("StyleBoxFlat_soft_panel", PackedStringArray([
		_bg(UiTheme.CREAM_DARK, "CREAM_DARK"),
		_corners(int(UiTheme.RADIUS_PANEL), "RADIUS_PANEL"),
	]))

	var candy := PackedStringArray([
		_margin(BUTTON_CONTENT_MARGIN_X, button_margin_y, margin_note),
		_bg(UiTheme.CANDY_PINK, "CANDY_PINK"),
		"border_width_bottom = %d ; BUTTON_EDGE" % int(UiTheme.BUTTON_EDGE),
		"border_color = %s ; CANDY_PINK_DARK" % _col(UiTheme.CANDY_PINK_DARK),
		_corners(PILL_RADIUS, "圆角=高度/2 的近似；StyleBox 拿不到控件高度"),
	])
	_sub("StyleBoxFlat_btn_normal", candy)

	# 按下态：文字下沉 PRESS_DROP、底边消失，盒子外框不动。
	# 关键在于 top +drop、bottom -drop —— 两者对称加 drop 会把总高撑大 2*drop，
	# 按下时按钮长高、整行布局跳动。总高必须与 normal 相等。
	var drop := int(UiTheme.PRESS_DROP)
	var drop_note := "normal 的 %s ± PRESS_DROP(%d)：文字下沉、总高不变" % [_num(button_margin_y), drop]
	_sub("StyleBoxFlat_btn_pressed", PackedStringArray([
		_pressed_margin(BUTTON_CONTENT_MARGIN_X, button_margin_y, drop, drop_note),
		_bg(UiTheme.CANDY_PINK, "CANDY_PINK"),
		_corners(PILL_RADIUS, "同 normal"),
	]))

	_sub("StyleBoxFlat_btn_disabled", PackedStringArray([
		_margin(BUTTON_CONTENT_MARGIN_X, button_margin_y, "同 normal，保证禁用时文字不跳位"),
		_bg(UiTheme.CREAM_DARK, "CREAM_DARK"),
		_corners(PILL_RADIUS, "同 normal"),
	]))

	var soft_note := "同 primary button"
	_sub("StyleBoxFlat_soft_btn_normal", PackedStringArray([
		_margin(BUTTON_CONTENT_MARGIN_X, button_margin_y, soft_note),
		_bg(UiTheme.CREAM_DARK, "CREAM_DARK"),
		_corners(PILL_RADIUS, soft_note),
	]))
	_sub("StyleBoxFlat_soft_btn_pressed", PackedStringArray([
		_pressed_margin(BUTTON_CONTENT_MARGIN_X, button_margin_y, drop,
			"PRESS_DROP(%d) 下沉；次按钮无底边，故只上下对挪、总高不变" % drop),
		_bg(UiTheme.CREAM_DARK, "CREAM_DARK"),
		_corners(PILL_RADIUS, "同 normal"),
	]))

	# 状态条：对应 UiTheme.draw_status_bar 的 size.y*0.5 药丸底槽。
	var bar_note := "对应 draw_status_bar 的 size.y*0.5 药丸形"
	_sub("StyleBoxFlat_bar_background", PackedStringArray([
		_bg(UiTheme.CREAM_DARK, "CREAM_DARK"),
		_corners(PILL_RADIUS, bar_note),
	]))
	_sub("StyleBoxFlat_bar_fill", PackedStringArray([
		_bg(UiTheme.CANDY_PINK, "CANDY_PINK"),
		_corners(PILL_RADIUS, "同 bar background"),
	]))


func _build_theme_items() -> void:
	_item("default_font_size = %d ; FONT_BODY" % UiTheme.FONT_BODY)

	_item("Button/colors/font_color = %s ; CREAM，糖果按钮字色" % _col(UiTheme.CREAM))
	_item("Button/colors/font_hover_color = %s ; CREAM" % _col(UiTheme.CREAM))
	_item("Button/colors/font_pressed_color = %s ; CREAM" % _col(UiTheme.CREAM))
	_item("Button/colors/font_disabled_color = %s ; INK_SOFT，cream_dark 底上唯一可读的弱化字色" % _col(UiTheme.INK_SOFT))
	_item("Button/font_sizes/font_size = %d ; FONT_BODY" % UiTheme.FONT_BODY)
	_item("Button/styles/disabled = SubResource(\"StyleBoxFlat_btn_disabled\")")
	_item("Button/styles/hover = SubResource(\"StyleBoxFlat_btn_normal\") ; hover 无独立设计（触屏优先），沿用 normal")
	_item("Button/styles/normal = SubResource(\"StyleBoxFlat_btn_normal\")")
	_item("Button/styles/pressed = SubResource(\"StyleBoxFlat_btn_pressed\")")

	_item("Label/colors/font_color = %s ; INK" % _col(UiTheme.INK))
	_item("Label/font_sizes/font_size = %d ; FONT_BODY" % UiTheme.FONT_BODY)

	_item("Panel/styles/panel = SubResource(\"StyleBoxFlat_panel\")")
	_item("PanelContainer/styles/panel = SubResource(\"StyleBoxFlat_panel\")")

	_item("ProgressBar/colors/font_color = %s ; INK，cream_dark 槽上默认字色不可读" % _col(UiTheme.INK))
	_item("ProgressBar/font_sizes/font_size = %d ; FONT_BODY" % UiTheme.FONT_BODY)
	_item("ProgressBar/styles/background = SubResource(\"StyleBoxFlat_bar_background\")")
	_item("ProgressBar/styles/fill = SubResource(\"StyleBoxFlat_bar_fill\")")

	_item("CountdownLabel/base_type = &\"Label\"")
	_item("CountdownLabel/colors/font_color = %s ; LEMON" % _col(UiTheme.LEMON))
	_item("CountdownLabel/colors/font_outline_color = %s ; INK" % _col(UiTheme.INK))
	_item("CountdownLabel/constants/outline_size = %d ; 对应 draw_string_outlined 的 outline_width" % OUTLINE_WIDTH)
	_item("CountdownLabel/font_sizes/font_size = %d ; FONT_COUNTDOWN" % UiTheme.FONT_COUNTDOWN)

	_item("HintLabel/base_type = &\"Label\"")
	_item("HintLabel/colors/font_color = %s ; INK_SOFT" % _col(UiTheme.INK_SOFT))
	_item("HintLabel/font_sizes/font_size = %d ; FONT_HINT" % UiTheme.FONT_HINT)

	_item("SecondaryButton/base_type = &\"Button\"")
	_item("SecondaryButton/colors/font_color = %s ; INK" % _col(UiTheme.INK))
	_item("SecondaryButton/colors/font_disabled_color = %s ; INK_SOFT" % _col(UiTheme.INK_SOFT))
	_item("SecondaryButton/colors/font_hover_color = %s ; INK" % _col(UiTheme.INK))
	_item("SecondaryButton/colors/font_pressed_color = %s ; INK" % _col(UiTheme.INK))
	_item("SecondaryButton/font_sizes/font_size = %d ; FONT_BODY" % UiTheme.FONT_BODY)
	_item("SecondaryButton/styles/disabled = SubResource(\"StyleBoxFlat_btn_disabled\")")
	_item("SecondaryButton/styles/hover = SubResource(\"StyleBoxFlat_soft_btn_normal\") ; hover 同 normal，理由同 Button")
	_item("SecondaryButton/styles/normal = SubResource(\"StyleBoxFlat_soft_btn_normal\")")
	_item("SecondaryButton/styles/pressed = SubResource(\"StyleBoxFlat_soft_btn_pressed\")")

	_item("SoftPanel/base_type = &\"PanelContainer\"")
	_item("SoftPanel/styles/panel = SubResource(\"StyleBoxFlat_soft_panel\")")

	_item("TitleLabel/base_type = &\"Label\"")
	_item("TitleLabel/colors/font_color = %s ; INK" % _col(UiTheme.INK))
	_item("TitleLabel/font_sizes/font_size = %d ; FONT_TITLE" % UiTheme.FONT_TITLE)


func _sub(id: String, lines: PackedStringArray) -> void:
	_sub_resources.append("[sub_resource type=\"StyleBoxFlat\" id=\"%s\"]\n%s" % [id, "\n".join(lines)])


func _item(line: String) -> void:
	_items.append(line)


func _margin(x: float, y: float, note: String) -> String:
	return "\n".join(PackedStringArray([
		"content_margin_left = %s ; 水平留白，量级对齐 draw_candy_button 的图标位 44px" % _num(x),
		"content_margin_top = %s ; %s" % [_num(y), note],
		"content_margin_right = %s ; 同 left" % _num(x),
		"content_margin_bottom = %s ; 同 top" % _num(y),
	]))


# 按下态专用：top +drop、bottom -drop，总高与 normal 相等。
# 不能复用 _margin（它把同一个 y 写给上下两边，会把总高撑大 2*drop）。
func _pressed_margin(x: float, y: float, drop: int, note: String) -> String:
	return "\n".join(PackedStringArray([
		"content_margin_left = %s ; 同 normal" % _num(x),
		"content_margin_top = %s ; %s" % [_num(y + drop), note],
		"content_margin_right = %s ; 同 normal" % _num(x),
		"content_margin_bottom = %s ; 同 normal（总高不变）" % _num(y - drop),
	]))


func _corners(radius: int, note: String) -> String:
	return "\n".join(PackedStringArray([
		"corner_radius_top_left = %d ; %s" % [radius, note],
		"corner_radius_top_right = %d ; %s" % [radius, note],
		"corner_radius_bottom_right = %d ; %s" % [radius, note],
		"corner_radius_bottom_left = %d ; %s" % [radius, note],
	]))


func _bg(color: Color, constant_name: String) -> String:
	return "bg_color = %s ; %s" % [_col(color), constant_name]


func _col(color: Color) -> String:
	return "Color(%s, %s, %s, %s)" % [_num(color.r), _num(color.g), _num(color.b), _num(color.a)]


# 与 Godot 自身序列化风格一致：最多 6 位小数，去掉尾随 0。
func _num(value: float) -> String:
	var text := "%.6f" % value
	text = text.rstrip("0").rstrip(".")
	return "0" if text.is_empty() or text == "-0" else text
