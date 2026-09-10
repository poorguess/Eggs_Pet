class_name CareState
extends RefCounted

var temperature: float = 72.0
var hunger: float = 72.0
var cleanliness: float = 78.0
var mood: float = 70.0

func clamp_values() -> void:
	temperature = clampf(temperature, 0.0, 100.0)
	hunger = clampf(hunger, 0.0, 100.0)
	cleanliness = clampf(cleanliness, 0.0, 100.0)
	mood = clampf(mood, 0.0, 100.0)

func tick(delta: float, lamp_on: bool) -> void:
	hunger -= delta * 0.018
	cleanliness -= delta * 0.012
	mood -= delta * 0.008
	temperature += (72.0 - temperature) * delta * 0.015
	if lamp_on:
		temperature += delta * 0.045
	clamp_values()

func is_comfortable() -> bool:
	return temperature >= 60.0 and hunger >= 60.0 and cleanliness >= 60.0 and mood >= 60.0

func apply_action(action: String) -> void:
	match action:
		"feed":
			hunger += 24.0
			mood += 4.0
		"warm":
			temperature += 20.0
			mood += 3.0
		"clean":
			cleanliness += 28.0
			mood += 6.0
		"play":
			mood += 22.0
			hunger -= 3.0
		"listen":
			mood += 5.0
	clamp_values()

func to_dict() -> Dictionary:
	return {"temperature": temperature, "hunger": hunger, "cleanliness": cleanliness, "mood": mood}

func from_dict(data: Dictionary) -> void:
	temperature = float(data.get("temperature", temperature))
	hunger = float(data.get("hunger", hunger))
	cleanliness = float(data.get("cleanliness", cleanliness))
	mood = float(data.get("mood", mood))
	clamp_values()
