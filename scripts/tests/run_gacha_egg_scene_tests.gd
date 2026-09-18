extends SceneTree

func _initialize() -> void:
	var harness := Node.new()
	harness.scene_file_path = "res://scenes/gacha_egg_scene.tscn"
	harness.set_script(load("res://scripts/tests/test_gacha_egg_scene.gd"))
	root.add_child(harness)
	current_scene = harness
