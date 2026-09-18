extends Control

const BUTTON_PRESS_SCALE := Vector2(1.07, 1.07)
const BUTTON_TURN_COVER_SCALE := Vector2(1.1, 1.1)
const BUTTON_HIT_AREA := Rect2(Vector2(1096.0, 1087.0), Vector2(360.0, 330.0))
const GACHA_DURATION := 2.2
const MACHINE_BASE_PIVOT := Vector2(1280.0, 1640.0)
const FLASH_ORIGIN_LOCAL := Vector2(1280.0, 1515.0)
const FLASH_TRIGGER_LEAD_TIME := 0.7
const FLASH_DURATION := 1.05
const REWARD_ENTER_DURATION := 0.72
const REWARD_PANEL_SHADER := preload("res://assets/shaders/reward_panel_wobble.gdshader")
const REWARD_TEXT_SHADER := preload("res://assets/shaders/reward_text_shine.gdshader")
const SHOW_REWARD_UI_ON_READY := false

@onready var _egg_machine: Control = %EggMachine
@onready var _egg_03: TextureRect = %Egg03
@onready var _egg_02: TextureRect = %Egg02
@onready var _egg_01: TextureRect = %Egg01
@onready var _button: TextureRect = %Button
@onready var _button_hit_area: Control = %ButtonHitArea
@onready var _egg_idle_animation: AnimationPlayer = %EggIdleAnimation
@onready var _gacha_flash_overlay: ColorRect = %GachaFlashOverlay
@onready var _reward_dim_overlay: ColorRect = %RewardDimOverlay
@onready var _reward_ui: Control = %RewardUI
@onready var _get_things_panel: TextureRect = %GetThingsPanel
@onready var _get_things_text: TextureRect = %GetThingsText
@onready var _confirm_icon: Control = %QdIcon

var _button_feedback_tween: Tween
var _gacha_tween: Tween
var _flash_tween: Tween
var _reward_tween: Tween
var _confirm_icon_tween: Tween
var _button_is_pressed := false
var _gacha_is_running := false
var _reward_shader_time := 0.0
var _reward_ui_authored_position := Vector2.ZERO
var _reward_ui_authored_scale := Vector2.ONE
var _reward_ui_authored_rotation := 0.0
var _confirm_icon_authored_scale := Vector2.ONE
var _egg_machine_authored_position := Vector2.ZERO
var _egg_machine_authored_rotation := 0.0
var _egg_machine_authored_scale := Vector2.ONE
var _button_authored_rotation := 0.0
var _button_authored_scale := Vector2.ONE

func _ready() -> void:
	_egg_machine.pivot_offset = MACHINE_BASE_PIVOT
	_button.pivot_offset = Vector2(1276.5, 1252.0)
	_egg_machine_authored_position = _egg_machine.position
	_egg_machine_authored_rotation = _egg_machine.rotation
	_egg_machine_authored_scale = _egg_machine.scale
	_button_authored_rotation = _button.rotation
	_button_authored_scale = _button.scale
	_confirm_icon_authored_scale = _confirm_icon.scale
	_gacha_flash_overlay.visible = false
	_reward_dim_overlay.visible = false
	_reward_ui.visible = SHOW_REWARD_UI_ON_READY
	_reward_ui.modulate = Color.WHITE if SHOW_REWARD_UI_ON_READY else Color(1.0, 1.0, 1.0, 0.0)
	_reward_dim_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ensure_reward_shaders()
	_capture_reward_authored_transform()
	if not SHOW_REWARD_UI_ON_READY:
		_place_reward_ui_offscreen()
	if SHOW_REWARD_UI_ON_READY:
		_set_reward_panel_wobble(0.26)
		_set_reward_panel_squash(0.0)
		_set_reward_panel_glow(0.35)
		_set_reward_panel_chromatic(0.0)
		_set_reward_text_glow(0.35)
	set_process(SHOW_REWARD_UI_ON_READY)
	_button_hit_area.position = BUTTON_HIT_AREA.position
	_button_hit_area.size = BUTTON_HIT_AREA.size
	_button_hit_area.gui_input.connect(_on_button_hit_area_gui_input)
	_confirm_icon.gui_input.connect(_on_confirm_icon_gui_input)
	_egg_idle_animation.play("egg_idle")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not _reward_ui.visible:
		_place_reward_ui_offscreen()

func _process(delta: float) -> void:
	_reward_shader_time += delta
	_set_reward_shader_parameter(_get_things_panel, "time_offset", _reward_shader_time)

func _on_button_hit_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_button()
		else:
			_release_button(true)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_button()
		else:
			_release_button(true)

func _on_confirm_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirm_reward_and_reset()
	elif event is InputEventScreenTouch and event.pressed:
		_confirm_reward_and_reset()

func _confirm_reward_and_reset() -> void:
	_play_confirm_icon_feedback()
	if not _reward_ui.visible and not _reward_dim_overlay.visible:
		return
	_hide_reward_ui()
	_reset_gacha_interface()

func _play_confirm_icon_feedback() -> void:
	if _confirm_icon_tween:
		_confirm_icon_tween.kill()
	_confirm_icon.scale = _confirm_icon_authored_scale
	_confirm_icon_tween = create_tween()
	_confirm_icon_tween.set_trans(Tween.TRANS_BACK)
	_confirm_icon_tween.set_ease(Tween.EASE_OUT)
	_confirm_icon_tween.tween_property(_confirm_icon, "scale", _confirm_icon_authored_scale * 1.08, 0.1)
	_confirm_icon_tween.tween_property(_confirm_icon, "scale", _confirm_icon_authored_scale, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _hide_reward_ui() -> void:
	if _reward_tween:
		_reward_tween.kill()
	_reward_ui.visible = false
	_reward_ui.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_reward_ui.position = _reward_ui_authored_position
	_reward_ui.scale = _reward_ui_authored_scale
	_reward_ui.rotation = _reward_ui_authored_rotation
	_reward_dim_overlay.visible = false
	_reward_dim_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_place_reward_ui_offscreen()
	_set_reward_panel_wobble(0.0)
	_set_reward_panel_squash(0.0)
	_set_reward_panel_glow(0.35)
	_set_reward_panel_chromatic(0.0)
	_set_reward_text_shine(0.0)
	_set_reward_text_pulse(0.0)
	_set_reward_text_glow(0.35)
	set_process(false)

func _reset_gacha_interface() -> void:
	_button_is_pressed = false
	_gacha_is_running = false
	_kill_button_feedback_tween()
	if _gacha_tween:
		_gacha_tween.kill()
	if _flash_tween:
		_flash_tween.kill()
	_gacha_flash_overlay.visible = false
	_egg_machine.position = _egg_machine_authored_position
	_egg_machine.rotation = _egg_machine_authored_rotation
	_egg_machine.scale = _egg_machine_authored_scale
	_button.rotation = _button_authored_rotation
	_button.scale = _button_authored_scale
	_reset_egg(_egg_03)
	_reset_egg(_egg_02)
	_reset_egg(_egg_01)
	_button_hit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_egg_idle_animation.play("egg_idle")

func _press_button() -> void:
	if _gacha_is_running:
		return
	_button_is_pressed = true
	_kill_button_feedback_tween()
	_button_feedback_tween = create_tween()
	_button_feedback_tween.set_trans(Tween.TRANS_BACK)
	_button_feedback_tween.set_ease(Tween.EASE_OUT)
	_button_feedback_tween.tween_property(_button, "scale", BUTTON_PRESS_SCALE, 0.1)

func _release_button(trigger_gacha: bool) -> void:
	if not _button_is_pressed:
		return
	_button_is_pressed = false
	_kill_button_feedback_tween()
	_button_feedback_tween = create_tween()
	_button_feedback_tween.set_trans(Tween.TRANS_BACK)
	_button_feedback_tween.set_ease(Tween.EASE_OUT)
	_button_feedback_tween.tween_property(_button, "scale", Vector2.ONE, 0.12)
	if trigger_gacha:
		_button_feedback_tween.tween_callback(_play_gacha_animation)

func _play_gacha_animation() -> void:
	if _gacha_is_running:
		return
	_gacha_is_running = true
	_kill_button_feedback_tween()
	_button_hit_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_egg_idle_animation.stop()
	if _gacha_tween:
		_gacha_tween.kill()
	var machine_position := _egg_machine.position
	var machine_rotation := _egg_machine.rotation
	var button_rotation := _button.rotation
	_gacha_tween = create_tween()
	_gacha_tween.set_parallel(true)
	_animate_button_turn(_gacha_tween, button_rotation)
	_animate_machine_shake(_gacha_tween, machine_position, machine_rotation)
	_animate_egg_impulse(_gacha_tween, _egg_03, Vector2(54.0, -28.0), 0.075, 0.06)
	_animate_egg_impulse(_gacha_tween, _egg_02, Vector2(-62.0, 34.0), -0.09, 0.14)
	_animate_egg_impulse(_gacha_tween, _egg_01, Vector2(46.0, -40.0), 0.1, 0.22)
	_gacha_tween.tween_callback(_play_gacha_flash).set_delay(max(GACHA_DURATION - FLASH_TRIGGER_LEAD_TIME, 0.0))
	_gacha_tween.set_parallel(false)
	_gacha_tween.tween_interval(GACHA_DURATION)
	_gacha_tween.tween_callback(_finish_gacha_animation.bind(machine_position, machine_rotation, button_rotation))

func _animate_button_turn(tween: Tween, base_rotation: float) -> void:
	tween.tween_property(_button, "rotation", base_rotation + deg_to_rad(90.0), 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_button, "rotation", base_rotation + deg_to_rad(84.0), 0.16).set_delay(0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_button, "rotation", base_rotation + deg_to_rad(90.0), 0.12).set_delay(0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_button, "scale", Vector2(1.16, 1.08), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_button, "scale", Vector2(1.08, 1.18), 0.22).set_delay(0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_button, "scale", BUTTON_TURN_COVER_SCALE, 0.2).set_delay(0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _animate_machine_shake(tween: Tween, base_position: Vector2, base_rotation: float) -> void:
	var times := PackedFloat32Array([0.0, 0.08, 0.17, 0.29, 0.43, 0.60, 0.80, 1.03, 1.30, 1.62, 1.95, GACHA_DURATION])
	var offsets := [
		Vector2.ZERO,
		Vector2(1.4, -0.4),
		Vector2(-1.8, 0.5),
		Vector2(1.2, 0.3),
		Vector2(-1.0, -0.2),
		Vector2(0.8, 0.2),
		Vector2(-0.6, -0.1),
		Vector2(0.4, 0.1),
		Vector2(-0.3, 0.0),
		Vector2(0.2, 0.0),
		Vector2(-0.1, 0.0),
		Vector2.ZERO,
	]
	var rotations := PackedFloat32Array([0.0, -0.025, 0.029, -0.023, 0.018, -0.014, 0.01, -0.007, 0.0045, -0.0027, 0.0013, 0.0])
	for i in range(1, times.size()):
		var duration := times[i] - times[i - 1]
		tween.tween_property(_egg_machine, "position", base_position + offsets[i], duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(times[i - 1])
		tween.tween_property(_egg_machine, "rotation", base_rotation + rotations[i], duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(times[i - 1])

func _animate_egg_impulse(tween: Tween, egg: Control, first_offset: Vector2, first_rotation: float, delay: float) -> void:
	var base_position := egg.position
	var base_rotation := egg.rotation
	var points := [
		Vector2.ZERO,
		first_offset,
		-first_offset * 0.72,
		first_offset.rotated(1.7) * 0.5,
		-first_offset * 0.28,
		first_offset * 0.14,
		Vector2.ZERO,
	]
	var rotations := PackedFloat32Array([0.0, first_rotation, -first_rotation * 0.75, first_rotation * 0.55, -first_rotation * 0.34, first_rotation * 0.15, 0.0])
	var times := PackedFloat32Array([0.0, 0.18, 0.43, 0.74, 1.08, 1.48, 1.92])
	for i in range(1, times.size()):
		var duration := times[i] - times[i - 1]
		tween.tween_property(egg, "position", base_position + points[i], duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay + times[i - 1])
		tween.tween_property(egg, "rotation", base_rotation + rotations[i], duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(delay + times[i - 1])

func _finish_gacha_animation(machine_position: Vector2, machine_rotation: float, button_rotation: float) -> void:
	_egg_machine.position = machine_position
	_egg_machine.rotation = machine_rotation
	_button.rotation = button_rotation + deg_to_rad(90.0)
	_button.scale = BUTTON_TURN_COVER_SCALE
	_reset_egg(_egg_03)
	_reset_egg(_egg_02)
	_reset_egg(_egg_01)
	_gacha_is_running = false
	_button_hit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_egg_idle_animation.play("egg_idle")

func _play_gacha_flash() -> void:
	var material := _gacha_flash_overlay.material as ShaderMaterial
	if material == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	var viewport_size := get_viewport_rect().size
	var machine_transform: Transform2D = _egg_machine.get_global_transform()
	var origin_global: Vector2 = machine_transform * FLASH_ORIGIN_LOCAL
	var origin_uv := Vector2(0.5, 0.66)
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		origin_uv = origin_global / viewport_size
	material.set_shader_parameter("origin", origin_uv)
	material.set_shader_parameter("aspect", viewport_size.x / max(viewport_size.y, 1.0))
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("strength", 0.0)
	_gacha_flash_overlay.visible = true
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_method(_set_flash_progress, 0.0, 1.0, FLASH_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_method(_set_flash_strength, 0.0, 1.18, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_method(_set_flash_strength, 1.18, 0.62, 0.34).set_delay(0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flash_tween.tween_method(_set_flash_strength, 0.62, 0.0, 0.53).set_delay(0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_flash_tween.set_parallel(false)
	_flash_tween.tween_callback(_finish_gacha_flash)

func _set_flash_progress(value: float) -> void:
	var material := _gacha_flash_overlay.material as ShaderMaterial
	if material:
		material.set_shader_parameter("progress", value)

func _set_flash_strength(value: float) -> void:
	var material := _gacha_flash_overlay.material as ShaderMaterial
	if material:
		material.set_shader_parameter("strength", value)

func _finish_gacha_flash() -> void:
	_set_flash_progress(1.0)
	_set_flash_strength(0.0)
	_gacha_flash_overlay.visible = false
	_play_reward_reveal()

func _play_reward_reveal() -> void:
	if _reward_tween:
		_reward_tween.kill()
	_ensure_reward_shaders()
	_place_reward_ui_offscreen()
	_reward_shader_time = 0.0
	_set_reward_shader_parameter(_get_things_panel, "time_offset", 0.0)
	_set_reward_shader_parameter(_get_things_panel, "wobble_strength", 1.0)
	_set_reward_shader_parameter(_get_things_panel, "entrance_squash", 1.0)
	_set_reward_shader_parameter(_get_things_panel, "glow_strength", 1.0)
	_set_reward_shader_parameter(_get_things_panel, "chromatic_strength", 0.85)
	_set_reward_shader_parameter(_get_things_text, "shine_progress", 0.0)
	_set_reward_shader_parameter(_get_things_text, "pulse_strength", 1.0)
	_set_reward_shader_parameter(_get_things_text, "glow_strength", 1.0)
	_reward_dim_overlay.visible = true
	_reward_ui.visible = true
	_reward_dim_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_reward_ui.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_reward_ui.scale = _reward_ui_authored_scale * Vector2(0.84, 1.1)
	_reward_ui.rotation = _reward_ui_authored_rotation - 0.075
	set_process(true)

	_reward_tween = create_tween()
	_reward_tween.set_parallel(true)
	_reward_tween.tween_property(_reward_dim_overlay, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_property(_reward_ui, "modulate:a", 1.0, 0.18).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_property(_reward_ui, "position", _reward_ui_authored_position, REWARD_ENTER_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_property(_reward_ui, "scale", _reward_ui_authored_scale, REWARD_ENTER_DURATION).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_property(_reward_ui, "rotation", _reward_ui_authored_rotation, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_panel_squash, 1.0, 0.0, 0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_panel_wobble, 1.0, 0.26, 0.82).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_panel_glow, 1.0, 0.35, 0.74).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_panel_chromatic, 0.85, 0.0, 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_text_shine, 0.0, 1.0, 0.58).set_delay(0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_text_pulse, 1.0, 0.0, 0.54).set_delay(0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reward_tween.tween_method(_set_reward_text_glow, 1.0, 0.35, 0.62).set_delay(0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _place_reward_ui_offscreen() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1088.0, 1920.0)
	_reward_ui.position = _reward_ui_authored_position - Vector2(viewport_size.x * 1.18, 0.0)

func _capture_reward_authored_transform() -> void:
	_reward_ui_authored_position = _reward_ui.position
	_reward_ui_authored_scale = _reward_ui.scale
	_reward_ui_authored_rotation = _reward_ui.rotation

func _set_reward_panel_squash(value: float) -> void:
	_set_reward_shader_parameter(_get_things_panel, "entrance_squash", value)

func _set_reward_panel_wobble(value: float) -> void:
	_set_reward_shader_parameter(_get_things_panel, "wobble_strength", value)

func _set_reward_panel_glow(value: float) -> void:
	_set_reward_shader_parameter(_get_things_panel, "glow_strength", value)

func _set_reward_panel_chromatic(value: float) -> void:
	_set_reward_shader_parameter(_get_things_panel, "chromatic_strength", value)

func _set_reward_text_shine(value: float) -> void:
	_set_reward_shader_parameter(_get_things_text, "shine_progress", value)

func _set_reward_text_pulse(value: float) -> void:
	_set_reward_shader_parameter(_get_things_text, "pulse_strength", value)

func _set_reward_text_glow(value: float) -> void:
	_set_reward_shader_parameter(_get_things_text, "glow_strength", value)

func _set_reward_shader_parameter(node: CanvasItem, parameter: StringName, value: Variant) -> void:
	var material := node.material as ShaderMaterial
	if material:
		material.set_shader_parameter(parameter, value)

func _ensure_reward_shaders() -> void:
	var material := _get_things_panel.material as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		_get_things_panel.material = material
	if material.shader == null:
		material.shader = REWARD_PANEL_SHADER
	var text_material := _get_things_text.material as ShaderMaterial
	if text_material == null:
		text_material = ShaderMaterial.new()
		_get_things_text.material = text_material
	if text_material.shader == null:
		text_material.shader = REWARD_TEXT_SHADER

func _reset_egg(egg: Control) -> void:
	egg.position = Vector2.ZERO
	egg.rotation = 0.0

func _kill_button_feedback_tween() -> void:
	if _button_feedback_tween:
		_button_feedback_tween.kill()
