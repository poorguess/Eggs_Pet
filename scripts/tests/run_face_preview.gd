extends SceneTree

func _initialize() -> void:
	var harness := Node.new()
	harness.scene_file_path = "res://scenes/main_island.tscn"
	harness.set_script(load("res://scripts/tests/preview_face_ui.gd"))
	root.add_child(harness)
	current_scene = harness
