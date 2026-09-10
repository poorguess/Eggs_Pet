class_name SaveService
extends RefCounted

const PATH := "user://egg_pet_save.json"
const FACE_PATH := "user://face.png"
const PET_LOOK_PATH := "user://pet_look.png"

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func apply_offline(data: Dictionary) -> Dictionary:
	var elapsed := maxf(0.0, Time.get_unix_time_from_system() - float(data.get("last_saved", Time.get_unix_time_from_system())))
	var capped := minf(elapsed, 60.0 * 60.0 * 24.0 * 3.0)
	var care: Dictionary = data.get("care", {})
	care["hunger"] = maxf(24.0, float(care.get("hunger", 72.0)) - capped * 0.012)
	care["cleanliness"] = maxf(28.0, float(care.get("cleanliness", 78.0)) - capped * 0.008)
	care["mood"] = maxf(30.0, float(care.get("mood", 70.0)) - capped * 0.005)
	care["temperature"] = clampf(float(care.get("temperature", 72.0)) + (72.0 - float(care.get("temperature", 72.0))) * 0.1, 0.0, 100.0)
	data["care"] = care
	if data.get("stage", "egg") == "egg" and not bool(data.get("hatched", false)):
		var progress := float(data.get("hatch_progress", -1.0))
		if progress < 0.0:
			progress = clampf(100.0 * (1.0 - float(data.get("hatch_remaining", GrowthState.HATCH_DURATION)) / GrowthState.HATCH_DURATION), 0.0, 100.0)
		progress = minf(100.0, progress + capped * 50.0 / GrowthState.HATCH_DURATION)
		data["hatch_progress"] = progress
		if progress >= 100.0:
			data["hatch_ready"] = true
	return data

static func save_data(data: Dictionary) -> void:
	data["last_saved"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

static func reset() -> void:
	for path in [PATH, FACE_PATH, PET_LOOK_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
