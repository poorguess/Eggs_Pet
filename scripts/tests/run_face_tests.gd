extends SceneTree

func _initialize() -> void:
	# The existing scene-manager autoload requires a registered current scene
	# before its _ready. Use its known island identity only in this test harness.
	var harness := Node.new()
	harness.scene_file_path = "res://scenes/main_island.tscn"
	harness.set_script(load("res://scripts/tests/test_face_module.gd"))
	root.add_child(harness)
	current_scene = harness
