class_name DetailPanel
extends Control

# 详情弹窗（替代原 main_island 的 _draw_detail / _draw_detail_egg / _draw_detail_pet）。
# 全部几何来自 scenes/detail_panel.tscn，脚本只做「填内容 + 入场动画 + 关闭信号」。
# 两套视图(EggView/PetView)叠在同一块 Content 下，用 visible 切换。

signal closed

const ENTER_SCALE := 0.8      # 原 _draw_detail 的 s = 0.8 + 0.2 * _dialog_anim（main_island.gd:812）
const ENTER_TIME := 0.25      # 原 Tween 时长
const STAT_ROWS := 4

const PRESS_SCALE := UiTheme.PRESS_SCALE
const PRESS_DOWN_TIME := 0.12
const PRESS_UP_TIME := 0.18

var _enter_tween: Tween
var _press_tween: Tween

@onready var _panel: Panel = $Panel
@onready var _egg_view: Control = $Panel/Content/EggView
@onready var _pet_view: Control = $Panel/Content/PetView
@onready var _egg_title: Label = $Panel/Content/EggView/Title
@onready var _egg_sub: Label = $Panel/Content/EggView/Sub
@onready var _egg_progress: Label = $Panel/Content/EggView/Progress
@onready var _egg_bar: ProgressBar = $Panel/Content/EggView/Bar
@onready var _egg_hint_b: Label = $Panel/Content/EggView/HintB
@onready var _pet_title: Label = $Panel/Content/PetView/Title
@onready var _pet_sub: Label = $Panel/Content/PetView/Sub
@onready var _pet_intimacy: Label = $Panel/Content/PetView/Intimacy
@onready var _pet_bar: ProgressBar = $Panel/Content/PetView/Bar
@onready var _pet_hint: Label = $Panel/Content/PetView/Hint
@onready var _pet_look: Label = $Panel/Content/PetView/Look
@onready var _close_button: Button = $Panel/Content/CloseButton

var _egg_bars: Array[ProgressBar] = []
var _egg_values: Array[Label] = []
var _pet_bars: Array[ProgressBar] = []
var _pet_values: Array[Label] = []

func _ready() -> void:
	for i in range(STAT_ROWS):
		var egg_row := _egg_view.get_node("Stats/StatRow%d" % i)
		_egg_bars.append(egg_row.get_node("Bar") as ProgressBar)
		_egg_values.append(egg_row.get_node("ValueBox/Value") as Label)
		var pet_row := _pet_view.get_node("Stats/StatRow%d" % i)
		_pet_bars.append(pet_row.get_node("Bar") as ProgressBar)
		_pet_values.append(pet_row.get_node("ValueBox/Value") as Label)
	_close_button.pressed.connect(close)
	_close_button.button_down.connect(_on_close_down)
	_close_button.button_up.connect(_on_close_up)
	_close_button.pivot_offset = _close_button.size * 0.5
	_panel.resized.connect(_sync_pivot)
	_sync_pivot()
	hide_views()

func hide_views() -> void:
	visible = false
	_egg_view.visible = false
	_pet_view.visible = false

# ---------------------------------------------------------------- 对外 API

# days：到家天数；progress_text 例 "孵化进度  42%  ·  约 120s 后破壳"（由调用方拼，原样照搬）。
# ready：可破壳；can_boost：孵蛋阶段仍可加速（默认 true = 原文行为，false 时收掉「加速」提示行）。
# progress_ratio 为 0..1，直接喂给 max_value=1 的进度条（传 growth.hatch_progress / 100.0）。
func show_egg(days: int, progress_text: String, ready: bool, can_boost: bool = true, progress_ratio: float = 0.0) -> void:
	_egg_view.visible = true
	_pet_view.visible = false
	_egg_title.text = "一颗蛋"
	_egg_sub.text = "普通蛋  ·  到家第 %d 天" % days
	_egg_progress.text = progress_text
	_egg_bar.value = clampf(progress_ratio, 0.0, 1.0)
	if ready:
		_egg_hint_b.text = "点下方「迎接破壳」，见它第一面。"
	elif can_boost:
		_egg_hint_b.text = "点下方「加速」可以让它早点破壳。"
	else:
		_egg_hint_b.text = "安静地等它自己准备好。"

# sub 例 "Shell Pudding  ·  相伴第 3 天"；intimacy_ratio 为 0..1（growth.intimacy_progress()）。
func show_pet(creature_name: String, sub: String, intimacy_cn: String, hint: String, look: String, intimacy_ratio: float = 0.0) -> void:
	_egg_view.visible = false
	_pet_view.visible = true
	_pet_title.text = creature_name
	_pet_sub.text = sub
	_pet_intimacy.text = "亲密度  %s" % intimacy_cn
	_pet_hint.text = hint
	_pet_bar.value = clampf(intimacy_ratio, 0.0, 1.0)
	_pet_look.text = "外貌：%s  ·  动作：继续照护可解锁新动作" % look

# 四行状态（温/饱/洁/心），值域 0..100，两套视图同步。
# 形参用无元素类型的 Array，理由同 Hud.set_stats（运行时拒绝 Array → Array[float] 隐式转换）。
func set_stats(values: Array) -> void:
	var count := mini(values.size(), STAT_ROWS)
	for i in range(count):
		var v := float(values[i])
		var text := str(int(round(v)))
		_egg_bars[i].value = v
		_egg_values[i].text = text
		_pet_bars[i].value = v
		_pet_values[i].text = text

# 入场：0.8 → 1.0 缩放 + 透明淡入，TRANS_BACK/EASE_OUT 0.25s（同原 Tween）。
func open() -> void:
	_sync_pivot()
	visible = true
	_panel.scale = Vector2.ONE * ENTER_SCALE
	_panel.modulate = Color(1, 1, 1, 0)
	if _enter_tween:
		_enter_tween.kill()
	_enter_tween = create_tween().set_parallel()
	_enter_tween.tween_property(_panel, "scale", Vector2.ONE, ENTER_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_panel, "modulate:a", 1.0, ENTER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 幂等：重复调用只发一次 closed（原 _activate_dialog_button 也是关掉即清 detail_open）。
func close() -> void:
	if not visible:
		return
	if _enter_tween:
		_enter_tween.kill()
		_enter_tween = null
	if _press_tween:
		_press_tween.kill()
		_press_tween = null
	_close_button.scale = Vector2.ONE
	visible = false
	closed.emit()

# ---------------------------------------------------------------- 内部

# size 还没算出来时不要覆盖 .tscn 里写好的 pivot，否则首帧会从左上角缩放。
func _sync_pivot() -> void:
	if _panel.size.x > 0.0 and _panel.size.y > 0.0:
		_panel.pivot_offset = _panel.size * 0.5

func _on_close_down() -> void:
	_tween_close(PRESS_SCALE, PRESS_DOWN_TIME, Tween.TRANS_LINEAR)

func _on_close_up() -> void:
	_tween_close(1.0, PRESS_UP_TIME, Tween.TRANS_BACK)

func _tween_close(target: float, duration: float, trans: Tween.TransitionType) -> void:
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(_close_button, "scale", Vector2.ONE * target, duration) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
