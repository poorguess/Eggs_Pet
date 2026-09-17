extends SceneTree

# 临时校验脚本：对 ui/theme.tres 做「资源层」与「活节点层」两层断言。跑完即删。

const THEME_PATH := "res://ui/theme.tres"

var _resource_checks := 0
var _resource_failures := 0
var _checks := 0
var _failures := 0
var _resource_done := false
var _theme: Theme


func _initialize() -> void:
	_theme = load(THEME_PATH) as Theme
	if _theme == null:
		push_error("无法加载 %s" % THEME_PATH)
		quit(1)
		return
	_check_resource()
	_resource_done = true


# 节点必须真的进树，主题解析才会生效；因此活节点断言放到 _process 里。
func _process(_delta: float) -> bool:
	if not _resource_done:
		return false
	var root := Node.new()
	get_root().add_child(root)

	var button := Button.new()
	button.text = "测试"
	root.add_child(button)

	var label := Label.new()
	root.add_child(label)

	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	root.add_child(hint)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var countdown := Label.new()
	countdown.theme_type_variation = &"CountdownLabel"
	root.add_child(countdown)

	var soft := Button.new()
	soft.theme_type_variation = &"SecondaryButton"
	soft.text = "测试"
	root.add_child(soft)

	var bar := ProgressBar.new()
	root.add_child(bar)

	var panel := PanelContainer.new()
	root.add_child(panel)

	var soft_panel := PanelContainer.new()
	soft_panel.theme_type_variation = &"SoftPanel"
	root.add_child(soft_panel)

	_check_live(button, label, hint, title, countdown, soft, bar, panel, soft_panel)

	print("RESOURCE CHECKS: ", _resource_checks, "  FAILURES: ", _resource_failures)
	print("LIVE CHECKS: ", _checks, "  FAILURES: ", _failures)
	root.queue_free()
	quit(0)
	return true


func _req(actual: Variant, expected: Variant, what: String) -> void:
	_resource_checks += 1
	if actual != expected:
		_resource_failures += 1
		print("  FAIL ", what, ": 实际=", actual, " 期望=", expected)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual != expected:
		_failures += 1
		print("  FAIL ", what, ": 实际=", actual, " 期望=", expected)


func _box(item: String, type_name: String) -> StyleBoxFlat:
	return _theme.get_stylebox(item, type_name) as StyleBoxFlat


func _check_resource() -> void:
	_req(_theme.default_font_size, UiTheme.FONT_BODY, "default_font_size")

	var panel := _box("panel", "Panel")
	_req(panel.bg_color, UiTheme.CREAM, "Panel.panel.bg_color")
	_req(panel.corner_radius_top_left, int(UiTheme.RADIUS_PANEL), "Panel.panel.radius_tl")

	var soft_panel := _box("panel", "SoftPanel")
	_req(soft_panel.bg_color, UiTheme.CREAM_DARK, "SoftPanel.panel.bg_color")
	_req(soft_panel.corner_radius_bottom_right, int(UiTheme.RADIUS_PANEL), "SoftPanel.panel.radius_br")

	var normal := _box("normal", "Button")
	_req(normal.bg_color, UiTheme.CANDY_PINK, "Button.normal.bg_color")
	_req(normal.border_width_bottom, int(UiTheme.BUTTON_EDGE), "Button.normal.border_width_bottom")
	_req(normal.border_color, UiTheme.CANDY_PINK_DARK, "Button.normal.border_color")
	_req(normal.corner_radius_top_left, 999, "Button.normal.radius_tl")
	_req(normal.content_margin_top, 23.0, "Button.normal.content_margin_top")

	var pressed := _box("pressed", "Button")
	_req(pressed.content_margin_top, 23.0 + UiTheme.PRESS_DROP, "Button.pressed.content_margin_top")
	_req(pressed.content_margin_bottom, 23.0 - UiTheme.PRESS_DROP, "Button.pressed.content_margin_bottom")
	_req(pressed.border_width_bottom, 0, "Button.pressed 无底边")

	_req(_box("disabled", "Button").bg_color, UiTheme.CREAM_DARK, "Button.disabled.bg_color")
	_req(_box("hover", "Button"), _box("normal", "Button"), "Button.hover 沿用 normal")

	_req(_theme.get_color("font_color", "Button"), UiTheme.CREAM, "Button.font_color")
	_req(_theme.get_color("font_pressed_color", "Button"), UiTheme.CREAM, "Button.font_pressed_color")
	_req(_theme.get_color("font_disabled_color", "Button"), UiTheme.INK_SOFT, "Button.font_disabled_color")
	_req(_theme.get_font_size("font_size", "Button"), UiTheme.FONT_BODY, "Button.font_size")

	_req(_theme.get_color("font_color", "Label"), UiTheme.INK, "Label.font_color")
	_req(_theme.get_font_size("font_size", "Label"), UiTheme.FONT_BODY, "Label.font_size")

	_req(_theme.get_stylebox("panel", "PanelContainer"), panel, "PanelContainer.panel 与 Panel 同")

	_req(_theme.get_color("font_color", "ProgressBar"), UiTheme.INK, "ProgressBar.font_color")
	_req(_theme.get_font_size("font_size", "ProgressBar"), UiTheme.FONT_BODY, "ProgressBar.font_size")
	_req(_box("background", "ProgressBar").bg_color, UiTheme.CREAM_DARK, "ProgressBar.background")
	_req(_box("fill", "ProgressBar").bg_color, UiTheme.CANDY_PINK, "ProgressBar.fill")

	_req(_theme.get_type_variation_base("CountdownLabel"), &"Label", "CountdownLabel.base_type")
	_req(_theme.get_color("font_color", "CountdownLabel"), UiTheme.LEMON, "CountdownLabel.font_color")
	_req(_theme.get_color("font_outline_color", "CountdownLabel"), UiTheme.INK, "CountdownLabel.outline_color")
	_req(_theme.get_constant("outline_size", "CountdownLabel"), 2, "CountdownLabel.outline_size")
	_req(_theme.get_font_size("font_size", "CountdownLabel"), UiTheme.FONT_COUNTDOWN, "CountdownLabel.font_size")

	_req(_theme.get_type_variation_base("HintLabel"), &"Label", "HintLabel.base_type")
	_req(_theme.get_color("font_color", "HintLabel"), UiTheme.INK_SOFT, "HintLabel.font_color")
	_req(_theme.get_font_size("font_size", "HintLabel"), UiTheme.FONT_HINT, "HintLabel.font_size")

	_req(_theme.get_type_variation_base("SecondaryButton"), &"Button", "SecondaryButton.base_type")
	_req(_theme.get_color("font_color", "SecondaryButton"), UiTheme.INK, "SecondaryButton.font_color")
	_req(_theme.get_color("font_pressed_color", "SecondaryButton"), UiTheme.INK, "SecondaryButton.font_pressed_color")
	_req(_box("normal", "SecondaryButton").bg_color, UiTheme.CREAM_DARK, "SecondaryButton.normal.bg_color")
	_req(_box("normal", "SecondaryButton").border_width_bottom, 0, "SecondaryButton 无底边")
	_req(_box("pressed", "SecondaryButton").content_margin_top, 23.0 + UiTheme.PRESS_DROP, "SecondaryButton.pressed 下沉")
	_req(_theme.get_font_size("font_size", "SecondaryButton"), UiTheme.FONT_BODY, "SecondaryButton.font_size")

	_req(_theme.get_type_variation_base("TitleLabel"), &"Label", "TitleLabel.base_type")
	_req(_theme.get_color("font_color", "TitleLabel"), UiTheme.INK, "TitleLabel.font_color")
	_req(_theme.get_font_size("font_size", "TitleLabel"), UiTheme.FONT_TITLE, "TitleLabel.font_size")


func _check_live(button: Button, label: Label, hint: Label, title: Label, countdown: Label, soft: Button, bar: ProgressBar, panel: PanelContainer, soft_panel: PanelContainer) -> void:
	_eq(button.get_theme_stylebox("normal"), _theme.get_stylebox("normal", "Button"), "Button 活节点取到主题 normal")
	_eq(button.get_theme_color("font_color"), UiTheme.CREAM, "Button 活节点字色")
	_eq(button.get_minimum_size().y, 88.0, "Button(text) 最小高 == 88（触摸目标下限）")
	_eq(label.get_theme_color("font_color"), UiTheme.INK, "Label 活节点字色")
	_eq(label.get_theme_font_size("font_size"), UiTheme.FONT_BODY, "Label 活节点字号")
	_eq(hint.get_theme_color("font_color"), UiTheme.INK_SOFT, "HintLabel 变体字色")
	_eq(hint.get_theme_font_size("font_size"), UiTheme.FONT_HINT, "HintLabel 变体字号")
	_eq(title.get_theme_font_size("font_size"), UiTheme.FONT_TITLE, "TitleLabel 变体字号")
	_eq(countdown.get_theme_color("font_color"), UiTheme.LEMON, "CountdownLabel 变体字色")
	_eq(countdown.get_theme_constant("outline_size"), 2, "CountdownLabel 描边宽")
	_eq(countdown.get_theme_font_size("font_size"), UiTheme.FONT_COUNTDOWN, "CountdownLabel 字号")
	_eq(soft.get_theme_color("font_color"), UiTheme.INK, "SecondaryButton 字色")
	_eq((soft.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, UiTheme.CREAM_DARK, "SecondaryButton 底色")
	_eq(soft.get_minimum_size().y, 88.0, "SecondaryButton 最小高 == 88")
	_eq((bar.get_theme_stylebox("background") as StyleBoxFlat).bg_color, UiTheme.CREAM_DARK, "ProgressBar 活节点底槽")
	_eq((panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, UiTheme.CREAM, "PanelContainer 活节点面板")
	_eq((soft_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, UiTheme.CREAM_DARK, "SoftPanel 活节点面板")
