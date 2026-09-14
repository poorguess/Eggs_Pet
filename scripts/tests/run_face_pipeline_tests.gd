extends SceneTree

func _initialize() -> void:
	# 与 run_face_tests.gd 相同：scene_manager autoload 要求先注册当前场景。
	var harness := Node.new()
	harness.scene_file_path = "res://scenes/main_island.tscn"
	harness.set_script(load("res://scripts/tests/test_face_pipeline.gd"))
	root.add_child(harness)
	current_scene = harness
