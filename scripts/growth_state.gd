class_name GrowthState
extends RefCounted

const HATCH_DURATION := 30.0
const BOOST_PERCENT := 100.0 * 5.0 / HATCH_DURATION
const INTIMACY_COMFORTABLE := 20.0
const INTIMACY_CLOSE := 60.0

var hatch_progress: float = 0.0
var hatch_ready: bool = false
var hatched: bool = false
var intimacy_points: float = 0.0

func tick(delta: float, comfortable: bool) -> void:
	if not hatched:
		if not hatch_ready:
			hatch_progress = minf(100.0, hatch_progress + delta * 100.0 / HATCH_DURATION)
			hatch_ready = hatch_progress >= 100.0
	else:
		intimacy_points = minf(100.0, intimacy_points + delta * (0.01 if comfortable else 0.003))

func accelerate(percent: float = BOOST_PERCENT) -> void:
	if not hatched and not hatch_ready:
		hatch_progress = minf(100.0, hatch_progress + percent)
		hatch_ready = hatch_progress >= 100.0

func hatch() -> void:
	if hatch_ready and not hatched:
		hatch_progress = 100.0
		hatched = true

func hatch_seconds_left() -> float:
	return maxf(0.0, (100.0 - hatch_progress) * HATCH_DURATION / 100.0)

func intimacy_level() -> String:
	if intimacy_points >= INTIMACY_CLOSE:
		return "Close"
	if intimacy_points >= INTIMACY_COMFORTABLE:
		return "Comfortable"
	return "Stranger"

func intimacy_progress() -> float:
	if intimacy_points >= INTIMACY_CLOSE:
		return 1.0
	if intimacy_points >= INTIMACY_COMFORTABLE:
		return (intimacy_points - INTIMACY_COMFORTABLE) / (INTIMACY_CLOSE - INTIMACY_COMFORTABLE)
	return intimacy_points / INTIMACY_COMFORTABLE

func to_dict() -> Dictionary:
	return {"hatch_progress": hatch_progress, "hatch_ready": hatch_ready, "hatched": hatched, "intimacy_points": intimacy_points}

func from_dict(data: Dictionary) -> void:
	if data.has("hatch_progress"):
		hatch_progress = clampf(float(data.get("hatch_progress", 0.0)), 0.0, 100.0)
	elif data.has("hatch_remaining"):
		hatch_progress = clampf(100.0 * (1.0 - float(data["hatch_remaining"]) / HATCH_DURATION), 0.0, 100.0)
	hatch_ready = bool(data.get("hatch_ready", hatch_progress >= 100.0))
	hatched = bool(data.get("hatched", false))
	if hatched:
		hatch_progress = 100.0
		hatch_ready = true
	intimacy_points = clampf(float(data.get("intimacy_points", intimacy_points)), 0.0, 100.0)
