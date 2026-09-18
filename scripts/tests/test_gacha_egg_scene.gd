extends Node

var failures: int = 0
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var panel_shader_text := FileAccess.get_file_as_string("res://assets/shaders/reward_panel_wobble.gdshader")
	check(panel_shader_text.find("vec3(1.0, 0.92") == -1, "reward panel shader does not add white shine bands")
	check(panel_shader_text.find("vec3(1.0, 0.82") == -1, "reward panel shader does not add pale sparkle bands")
	check(panel_shader_text.find("uv +=") != -1, "reward panel shader keeps water ripple UV distortion")
	var packed := load("res://scenes/gacha_egg_scene.tscn") as PackedScene
	check(packed != null, "gacha egg scene exists")
	if packed != null:
		var scene := packed.instantiate()
		var authored_reward_ui := scene.get_node_or_null("RewardUI") as Control
		var reward_anchor_left := authored_reward_ui.anchor_left if authored_reward_ui else 0.0
		var reward_anchor_top := authored_reward_ui.anchor_top if authored_reward_ui else 0.0
		var reward_anchor_right := authored_reward_ui.anchor_right if authored_reward_ui else 0.0
		var reward_anchor_bottom := authored_reward_ui.anchor_bottom if authored_reward_ui else 0.0
		add_child(scene)
		check(scene is Control, "scene root is a full-screen Control")
		check(scene.has_node("BackLayer/Back"), "static back image node exists")
		check(scene.has_node("MiddleLayer/Middle"), "middle overlay exists")
		check(scene.has_node("EggMachine/Egg03"), "egg 03 exists under egg machine")
		check(scene.has_node("EggMachine/Egg02"), "egg 02 exists under egg machine")
		check(scene.has_node("EggMachine/Egg01"), "egg 01 exists under egg machine")
		check(scene.has_node("EggMachine/Machine"), "machine exists under egg machine")
		check(scene.has_node("EggMachine/Button"), "button exists under egg machine")
		check(scene.has_node("EggMachine/ButtonHitArea"), "button has a focused touch hit area")
		check(scene.has_node("EggMachine/EggIdleAnimation"), "egg machine has idle animation player")
		check(scene.has_node("ForegroundLayer/Mubu"), "foreground curtain exists")
		check(scene.has_node("GachaFlashOverlay"), "gacha flash overlay exists")
		check(scene.has_node("RewardDimOverlay"), "reward dim overlay exists")
		check(scene.has_node("RewardUI"), "reward UI container exists")
		check(scene.has_node("RewardUI/GetThingsPanel"), "reward UI panel art exists")
		check(scene.has_node("RewardUI/GetThingsText"), "reward UI text art exists")
		check(load("res://assets/gacha_egg/icons/bag_icon.png") is Texture2D, "bag icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/bx_icon.png") is Texture2D, "treasure chest icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/chat_icon.png") is Texture2D, "chat icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/egg_icon.png") is Texture2D, "reward egg icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/qd_icon.png") is Texture2D, "confirm icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/sz_icon.png") is Texture2D, "settings icon texture imports from project assets")
		check(load("res://assets/gacha_egg/icons/tj_icon.png") is Texture2D, "catalog icon texture imports from project assets")
		check(scene.has_node("IconLayer"), "top-level icon layer exists")
		check(scene.has_node("IconLayer/BagIcon"), "bag icon node exists")
		check(scene.has_node("IconLayer/BxIcon"), "treasure chest icon node exists")
		check(scene.has_node("IconLayer/ChatIcon"), "chat icon node exists")
		check(scene.has_node("IconLayer/SzIcon"), "settings icon node exists")
		check(scene.has_node("IconLayer/TjIcon"), "catalog icon node exists")
		check(scene.has_node("RewardUI/RewardEggIcon"), "reward egg icon exists above get things panel")
		check(scene.has_node("RewardUI/QdIcon"), "confirm icon belongs to reward UI")
		var egg_machine := scene.get_node("EggMachine")
		var egg_machine_authored_position: Vector2 = egg_machine.position
		var egg_machine_authored_rotation: float = egg_machine.rotation
		check(egg_machine.get_child(0).name == "Egg03", "egg machine back-most child is egg 03")
		check(egg_machine.get_child(1).name == "Egg02", "egg 02 draws over egg 03")
		check(egg_machine.get_child(2).name == "Egg01", "egg 01 draws over egg 02")
		check(egg_machine.get_child(3).name == "Machine", "machine draws over eggs")
		check(egg_machine.get_child(4).name == "Button", "button draws over machine")
		check(scene.get_node("IconLayer").get_index() < scene.get_node("RewardDimOverlay").get_index(), "reward dim overlay draws above normal icon layer")
		check(scene.get_node("RewardDimOverlay").get_index() < scene.get_node("RewardUI").get_index(), "reward UI draws above dim overlay")
		var reward_ui := scene.get_node_or_null("RewardUI")
		var reward_ui_size := Vector2.ZERO
		var reward_ui_pivot := Vector2.ZERO
		var reward_ui_scale := Vector2.ZERO
		var reward_ui_rotation := 0.0
		var panel_position := Vector2.ZERO
		var panel_size := Vector2.ZERO
		var panel_scale := Vector2.ZERO
		var panel_rotation := 0.0
		var text_position := Vector2.ZERO
		var text_size := Vector2.ZERO
		var text_scale := Vector2.ZERO
		var text_rotation := 0.0
		if reward_ui:
			reward_ui_size = reward_ui.size
			reward_ui_pivot = reward_ui.pivot_offset
			reward_ui_scale = reward_ui.scale
			reward_ui_rotation = reward_ui.rotation
			check(reward_ui.get_child(0).name == "GetThingsPanel", "reward panel art draws below text")
			check(reward_ui.get_child(1).name == "GetThingsText", "reward text draws above panel art")
			check(reward_ui.get_child_count() >= 3 and reward_ui.get_child(2).name == "RewardEggIcon", "reward egg icon draws above get things panel")
			check(reward_ui.get_child_count() >= 4 and reward_ui.get_child(3).name == "QdIcon", "confirm icon draws with reward UI")
			var panel := scene.get_node("RewardUI/GetThingsPanel") as TextureRect
			var text := scene.get_node("RewardUI/GetThingsText") as TextureRect
			panel_position = panel.position
			panel_size = panel.size
			panel_scale = panel.scale
			panel_rotation = panel.rotation
			text_position = text.position
			text_size = text.size
			text_scale = text.scale
			text_rotation = text.rotation
			check(not reward_ui.visible, "reward UI is hidden on scene load until the hatch flash finishes")
			var panel_material := panel.material as ShaderMaterial
			check(panel_material != null and panel_material.shader != null, "reward panel shader material is assigned")
			var text_material := text.material as ShaderMaterial
			check(text_material != null and text_material.shader != null, "reward text shader material is assigned")
		check(scene.has_method("_on_button_hit_area_gui_input"), "scene exposes button input handler")
		check(scene.has_method("_play_gacha_animation"), "scene exposes gacha animation trigger")
		check(scene.has_method("_play_gacha_flash"), "scene exposes hatch flash trigger")
		check(scene.has_method("_play_reward_reveal"), "scene exposes reward reveal trigger")
		check(not scene.has_node("VideoLayer/NiudanBackVideo"), "scene does not depend on video playback")
		scene._play_gacha_flash()
		check(scene.get_node("GachaFlashOverlay").visible, "hatch flash can be triggered without runtime errors")
		scene._finish_gacha_flash()
		await get_tree().create_timer(1.0).timeout
		var reward_dim := scene.get_node_or_null("RewardDimOverlay")
		if reward_dim:
			check(reward_dim.visible, "reward dim overlay appears after hatch flash")
		if reward_ui:
			check(reward_ui.visible, "reward UI appears after hatch flash")
			check(reward_ui.size == reward_ui_size, "reward reveal preserves edited reward UI size")
			check(reward_ui.pivot_offset == reward_ui_pivot, "reward reveal preserves edited reward UI pivot")
			check(reward_ui.anchor_left == reward_anchor_left, "reward reveal preserves edited reward UI left anchor")
			check(reward_ui.anchor_top == reward_anchor_top, "reward reveal preserves edited reward UI top anchor")
			check(reward_ui.anchor_right == reward_anchor_right, "reward reveal preserves edited reward UI right anchor")
			check(reward_ui.anchor_bottom == reward_anchor_bottom, "reward reveal preserves edited reward UI bottom anchor")
			check(reward_ui.scale == reward_ui_scale, "reward reveal preserves edited reward UI scale")
			check(reward_ui.rotation == reward_ui_rotation, "reward reveal preserves edited reward UI rotation")
			check(scene.get_node("RewardUI/GetThingsPanel").position == panel_position, "reward reveal preserves edited panel position")
			check(scene.get_node("RewardUI/GetThingsPanel").size == panel_size, "reward reveal preserves edited panel size")
			check(scene.get_node("RewardUI/GetThingsPanel").scale == panel_scale, "reward reveal preserves edited panel scale")
			check(scene.get_node("RewardUI/GetThingsPanel").rotation == panel_rotation, "reward reveal preserves edited panel rotation")
			check(scene.get_node("RewardUI/GetThingsText").position == text_position, "reward reveal preserves edited text position")
			check(scene.get_node("RewardUI/GetThingsText").size == text_size, "reward reveal preserves edited text size")
			check(scene.get_node("RewardUI/GetThingsText").scale == text_scale, "reward reveal preserves edited text scale")
			check(scene.get_node("RewardUI/GetThingsText").rotation == text_rotation, "reward reveal preserves edited text rotation")
			var confirm_icon := scene.get_node_or_null("RewardUI/QdIcon") as Control
			check(confirm_icon != null and confirm_icon.mouse_filter == Control.MOUSE_FILTER_STOP, "confirm icon accepts button input")
			if confirm_icon:
				var button := scene.get_node("EggMachine/Button") as TextureRect
				var egg_idle := scene.get_node("EggMachine/EggIdleAnimation") as AnimationPlayer
				var confirm_event := InputEventMouseButton.new()
				confirm_event.button_index = MOUSE_BUTTON_LEFT
				confirm_event.pressed = true
				confirm_icon.gui_input.emit(confirm_event)
				await get_tree().create_timer(0.32).timeout
				check(not reward_ui.visible, "confirm icon hides reward UI")
				check(not reward_dim.visible, "confirm icon hides reward dim overlay")
				check(reward_ui.modulate.a == 0.0, "confirm icon clears reward UI alpha")
				check(scene.get_node("EggMachine/ButtonHitArea").mouse_filter == Control.MOUSE_FILTER_STOP, "confirm icon restores button hit area input")
				check(egg_machine.position == egg_machine_authored_position, "confirm icon restores egg machine authored position")
				check(egg_machine.rotation == egg_machine_authored_rotation, "confirm icon restores egg machine authored rotation")
				check(button.scale == Vector2.ONE, "confirm icon restores gacha button scale")
				check(button.rotation == 0.0, "confirm icon restores gacha button rotation")
				check(egg_idle.is_playing(), "confirm icon restarts egg idle animation")
		scene.queue_free()
	print("GACHA EGG SCENE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
