@tool
extends EditorExportPlugin

const PLUGIN_PATH := "res://addons/face_track_editor/plugin.cfg"
var _enabled := PackedStringArray()

func _get_name() -> String:
	return "ExcludeFaceTrackEditor"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_enabled = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	var shipping := _enabled.duplicate()
	var index := shipping.find(PLUGIN_PATH)
	if index >= 0:
		shipping.remove_at(index)
	ProjectSettings.set_setting("editor_plugins/enabled", shipping)

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://addons/face_track_editor/"):
		skip()

func _export_end() -> void:
	ProjectSettings.set_setting("editor_plugins/enabled", _enabled)
