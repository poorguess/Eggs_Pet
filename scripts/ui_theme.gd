class_name UiTheme
extends RefCounted

# 「糖果岛」设计系统落地（docs/ui_style_guide.md §2/§3/§4），禁止在调用处发明新颜色/新圆角。

const CREAM := Color("#FFF9EF")
const CREAM_DARK := Color("#F5E9D5")
const INK := Color("#5B4A3F")
const INK_SOFT := Color("#A08B7C")
const CANDY_PINK := Color("#FF6B8A")
const CANDY_PINK_DARK := Color("#E14C6D")
const SKY := Color("#4FB7FF")
const SKY_DARK := Color("#2E96E8")
const MINT := Color("#5CD6A2")
const MINT_DARK := Color("#3DBB85")
const LEMON := Color("#FFD23F")
const DANGER := Color("#FF5A5A")
const SHADOW_WARM := Color("#5B4A3F", 0.18)
const DIM := Color("#5B4A3F", 0.35)

const STATUS_TEMPERATURE := Color("#FF9F43")
const STATUS_HUNGER := Color("#FF6B8A")
const STATUS_CLEANLINESS := Color("#4FB7FF")
const STATUS_MOOD := Color("#FFD23F")

const RADIUS_PANEL := 32.0
const RADIUS_CARD := 24.0
const BUTTON_EDGE := 4.0
const PRESS_DROP := 4.0
const PRESS_SCALE := 0.88

const FONT_TITLE := 46
const FONT_BODY := 30
const FONT_HINT := 24
const FONT_COUNTDOWN := 56

static func fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)

static func pill_style(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var r := int(radius)
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
	return style

# 棉花糖面板：暖色软投影（y+6）+ cream 圆角底。
static func draw_panel(canvas: CanvasItem, rect: Rect2, fill: Color = CREAM, radius: float = RADIUS_PANEL, alpha: float = 1.0) -> void:
	canvas.draw_style_box(pill_style(fade(SHADOW_WARM, alpha), radius), Rect2(rect.position + Vector2(0, 6), rect.size))
	canvas.draw_style_box(pill_style(fade(fill, alpha), radius), rect)

# 弹窗顶部 12px 糖霜条（主流程粉 / 错误红 / 处理中蓝）。
static func draw_frosting(canvas: CanvasItem, panel: Rect2, color: Color, alpha: float = 1.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fade(color, alpha)
	style.corner_radius_top_left = int(RADIUS_PANEL)
	style.corner_radius_top_right = int(RADIUS_PANEL)
	canvas.draw_style_box(style, Rect2(panel.position, Vector2(panel.size.x, 12)))

# 糖果按钮：pill 填充 + 底部 4px 深色边；press ∈ [0,1] 时整体下移、底边消失。
static func draw_candy_button(canvas: CanvasItem, rect: Rect2, label: String, font: Font, color: Color, edge_color: Color, press: float = 0.0, alpha: float = 1.0, icon: Texture2D = null) -> void:
	var body := rect
	body.position.y += PRESS_DROP * press
	var edge := BUTTON_EDGE * (1.0 - press)
	if edge > 0.1:
		canvas.draw_style_box(pill_style(fade(edge_color, alpha), body.size.y * 0.5), body)
		body.size.y -= edge
	canvas.draw_style_box(pill_style(fade(color, alpha), body.size.y * 0.5), body)
	var label_rect := body
	if icon:
		var icon_rect := Rect2(body.position + Vector2(44, 0), Vector2(36, body.size.y))
		draw_icon(canvas, icon, icon_rect, alpha)
		label_rect = Rect2(body.position + Vector2(36, 0), Vector2(body.size.x - 36, body.size.y))
	draw_label_centered(canvas, font, label_rect, label, FONT_BODY, fade(CREAM, alpha))

# 次按钮：cream_dark 底 + ink 字，无底边；按压同样下移 4px。
static func draw_secondary_button(canvas: CanvasItem, rect: Rect2, label: String, font: Font, press: float = 0.0, alpha: float = 1.0, icon: Texture2D = null) -> void:
	var body := rect
	body.position.y += PRESS_DROP * press
	canvas.draw_style_box(pill_style(fade(CREAM_DARK, alpha), body.size.y * 0.5), body)
	var label_rect := body
	if icon:
		var icon_rect := Rect2(body.position + Vector2(44, 0), Vector2(36, body.size.y))
		draw_icon(canvas, icon, icon_rect, alpha)
		label_rect = Rect2(body.position + Vector2(36, 0), Vector2(body.size.x - 36, body.size.y))
	draw_label_centered(canvas, font, label_rect, label, FONT_BODY, fade(INK, alpha))

# 状态条：cream_dark 全圆角底槽 + 状态色填充（末端圆头）。
static func draw_status_bar(canvas: CanvasItem, rect: Rect2, ratio: float, color: Color, alpha: float = 1.0) -> void:
	canvas.draw_style_box(pill_style(fade(CREAM_DARK, alpha), rect.size.y * 0.5), rect)
	var width := clampf(ratio, 0.0, 1.0) * rect.size.x
	if width >= rect.size.y:
		canvas.draw_style_box(pill_style(fade(color, alpha), rect.size.y * 0.5), Rect2(rect.position, Vector2(width, rect.size.y)))
	elif width > 0.0:
		canvas.draw_circle(rect.position + Vector2.ONE * rect.size.y * 0.5, rect.size.y * 0.5, fade(color, alpha))

static func draw_label_centered(canvas: CanvasItem, font: Font, rect: Rect2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(font, Vector2(rect.position.x, centered_baseline(font, size, rect)), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, color)

static func centered_baseline(font: Font, size: int, rect: Rect2) -> float:
	return rect.position.y + (rect.size.y - font.get_ascent(size) - font.get_descent(size)) * 0.5 + font.get_ascent(size)

# 倒计时数字用的描边字（lemon 填色 + ink 描边）。
static func draw_string_outlined(canvas: CanvasItem, font: Font, pos: Vector2, text: String, alignment: HorizontalAlignment, width: float, size: int, color: Color, outline_color: Color, outline_width: float = 2.0) -> void:
	for ox in [-1.0, 0.0, 1.0]:
		for oy in [-1.0, 0.0, 1.0]:
			if ox == 0.0 and oy == 0.0:
				continue
			canvas.draw_string(font, pos + Vector2(ox, oy) * outline_width, text, alignment, width, size, outline_color)
	canvas.draw_string(font, pos, text, alignment, width, size, color)

static func draw_icon(canvas: CanvasItem, texture: Texture2D, rect: Rect2, alpha: float = 1.0) -> void:
	var size := texture.get_size()
	var fit := minf(rect.size.x / size.x, rect.size.y / size.y)
	var draw_size := size * fit
	canvas.draw_texture_rect(texture, Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size), false, Color(1, 1, 1, alpha))
