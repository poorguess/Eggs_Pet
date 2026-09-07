@tool


extends Node


const SoundEffectsPlayer = preload("./sound_effects.gd")
const AmbientSoundsPlayer = preload("./ambient_sounds.gd")
const MusicPlayer = preload("./music.gd")

var sound_effects: SoundEffectsPlayer = SoundEffectsPlayer.new("Sound effects", 8)
var ui_sounds: SoundEffectsPlayer = SoundEffectsPlayer.new("UI sounds", 8)
var ambient_sounds: AmbientSoundsPlayer = AmbientSoundsPlayer.new("Ambient sounds", 2)
var music: MusicPlayer = MusicPlayer.new("Music", 2)


func _init() -> void:
	add_child(sound_effects)
	add_child(ui_sounds)
	add_child(ambient_sounds)
	add_child(music)

	sound_effects.process_mode = PROCESS_MODE_PAUSABLE
	ui_sounds.process_mode = PROCESS_MODE_ALWAYS
	ambient_sounds.process_mode = PROCESS_MODE_ALWAYS
	music.process_mode = PROCESS_MODE_ALWAYS


#region Volume


func get_volume(bus_index: int) -> float:
	return AudioServer.get_bus_volume_linear(bus_index)


func set_volume(bus_index: int, volume: float) -> void:
	AudioServer.set_bus_volume_linear(bus_index, _clamp_volume(volume))


func get_mute(bus_index: int) -> bool:
	return AudioServer.is_bus_mute(bus_index)


func set_mute(bus_index: int, mute: bool) -> void:
	AudioServer.set_bus_mute(bus_index, mute)


#endregion

#region Effects


func get_effect(bus_index: int, effect_index: int) -> AudioEffect:
	return AudioServer.get_bus_effect(bus_index, effect_index)


func get_effects(bus_index: int) -> Array[AudioEffect]:
	var effect_list : Array[AudioEffect] = []
	for effect_index : int in AudioServer.get_bus_effect_count(bus_index):
		effect_list.append(get_effect(bus_index, effect_index))
	return effect_list


func add_effect(bus_index: int, effect: AudioEffect, index : int = -1) -> void:
	AudioServer.add_bus_effect(bus_index, effect, index)


func set_effect(bus_index: int, effect_index: int, enabled: bool) -> void:
	AudioServer.set_bus_effect_enabled(bus_index, effect_index, enabled)


func remove_effect(bus_index: int, effect_index: int) -> void:
	AudioServer.remove_bus_effect(bus_index, effect_index)


func clear_effects(bus_index: int) -> void:
	var effect_count : int = AudioServer.get_bus_effect_count(bus_index)
	for effect_index : int in effect_count:
		remove_effect(bus_index ,effect_count - effect_index - 1)


#endregion

#region Master


func get_master_index() -> int:
	return AudioServer.get_bus_index("Master")


#endregion

#region Sound effects


func get_sound_effects_index() -> int:
	return AudioServer.get_bus_index(sound_effects.bus)


func play_sound_effect(resource: AudioStream, override_bus: String = "") -> AudioStreamPlayer:
	return sound_effects.play(resource, override_bus)


func stop_sound_effect(resource: AudioStream) -> void:
	return sound_effects.stop(resource)


func set_sound_effects_bus(bus: String) -> void:
	sound_effects.bus = bus


#endregion

#region UI sounds


func get_ui_sounds_index() -> int:
	return AudioServer.get_bus_index(ui_sounds.bus)


func play_ui_sound(resource: AudioStream, override_bus: String = "") -> AudioStreamPlayer:
	return ui_sounds.play(resource, override_bus)


func stop_ui_sound(resource: AudioStream) -> void:
	return ui_sounds.stop(resource)


func set_ui_sounds_bus(bus: String) -> void:
	ui_sounds.bus = bus


#endregion

#region Ambient sounds


func get_ambient_sounds_index() -> int:
	return AudioServer.get_bus_index(ambient_sounds.bus)


func play_ambient_sound(resource: AudioStream, fade_in_duration: float = 0.0, override_bus: String = "") -> AudioStreamPlayer:
	return ambient_sounds.play(resource, fade_in_duration, override_bus)


func stop_ambient_sound(resource: AudioStream, fade_out_duration: float = 0.0) -> void:
	ambient_sounds.stop(resource, fade_out_duration)


func stop_all_ambient_sounds(fade_out_duration: float = 0.0) -> void:
	ambient_sounds.stop_all(fade_out_duration)


func set_ambient_sound_bus(bus: String) -> void:
	ambient_sounds.bus = bus


#endregion

#region Music


func get_music_index() -> int:
	return AudioServer.get_bus_index(music.bus)


func play_music(resource: AudioStream, position: float = 0.0, volume: float = 1.0, crossfade_duration: float = 0.0, override_bus: String = "") -> AudioStreamPlayer:
	return music.play(resource, position, volume, crossfade_duration, override_bus)


func get_music_track_history() -> PackedStringArray:
	return music.track_history


func get_last_played_music_track() -> String:
	return music.track_history[0]


func is_music_playing(resource: AudioStream = null) -> bool:
	return music.is_playing(resource)


func is_music_track_playing(resource_path: String) -> bool:
	return music.is_track_playing(resource_path)


func get_currently_playing_music() -> Array[AudioStream]:
	return music.get_currently_playing()


func get_currently_playing_music_tracks() -> PackedStringArray:
	return music.get_currently_playing_tracks()


func pause_music(resource: AudioStream = null) -> void:
	music.pause(resource)


func resume_music(resource: AudioStream = null) -> void:
	music.resume(resource)


func stop_music(fade_out_duration: float = 0.0) -> void:
	music.stop(fade_out_duration)


func set_music_bus(bus: String) -> void:
	music.bus = bus


#endregion

#region Helpers


func _show_shared_bus_warning() -> void:
	if "Master" in [music.bus, sound_effects.bus, ui_sounds.bus, ambient_sounds.bus]:
		push_warning("Using the Master sound bus directly isn't recommended.")
	if music.bus == sound_effects.bus or music.bus == ui_sounds.bus:
		push_warning("Both music and sounds are using the same bus: %s" % music.bus)


func _clamp_volume(volume: float) -> float:
	if not (0.0 <= volume and volume <= 1.0):
		push_warning("Attempted to change volume to an invalid value :",volume)
	return clampf(volume, 0.0, 1.0)


#endregion
