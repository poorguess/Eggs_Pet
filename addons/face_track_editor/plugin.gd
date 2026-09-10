@tool
extends EditorPlugin

const Dock = preload("res://addons/face_track_editor/face_track_editor_dock.gd")
const ExportGuard = preload("res://addons/face_track_editor/export_guard.gd")
var _dock: Control
var _export_guard: EditorExportPlugin

func _enter_tree() -> void:
	_export_guard = ExportGuard.new()
	add_export_plugin(_export_guard)
	_dock = Dock.new()
	_dock.name = "Face Contour"
	add_control_to_bottom_panel(_dock, "Face Contour")

func _exit_tree() -> void:
	if _export_guard != null:
		remove_export_plugin(_export_guard)
	if is_instance_valid(_dock):
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
