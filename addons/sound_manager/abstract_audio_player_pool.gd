extends Node

var max_pool_size: int
var available_players: Array[AudioStreamPlayer]
var busy_players: Array[AudioStreamPlayer]
var bus: String

var _tweens: Dictionary[AudioStreamPlayer, Tween] = {}


func _init(expected_bus: String, pool_size: int = 8) -> void:
	bus = get_bus(expected_bus)
	
	max_pool_size = pool_size
	
	for i: int in pool_size:
		increase_pool()


func get_bus(expected_bus: String) -> String:
	if AudioServer.get_bus_index(expected_bus) > -1:
		return expected_bus
	push_warning("Expected bus was not found, check if the bus exists and if the name matches.\nExpected bus :",expected_bus)
	return "Master"


func prepare(resource: AudioStream, override_bus: String = "") -> AudioStreamPlayer:
	var player: AudioStreamPlayer

	if resource is AudioStreamRandomizer:
		player = get_player_with_resource(resource)

	if player == null:
		player = get_available_player()

	player.stream = resource
	player.bus = override_bus if override_bus != "" else bus
	player.volume_linear = 1.0
	player.pitch_scale = 1

	mark_player_as_busy(player)

	return player


func get_available_player() -> AudioStreamPlayer:
	if available_players.size() == 0:
		increase_pool()
	var player: AudioStreamPlayer = available_players.pop_front()
	return player


func get_player_with_resource(resource: AudioStream) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in busy_players + available_players:
		if player.stream == resource:
			return player
	return null


func get_busy_player_with_resource(resource: AudioStream) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in busy_players:
		if player.stream.resource_path == resource.resource_path:
			return player
	return null


func mark_player_as_busy(player: AudioStreamPlayer) -> void:
	if available_players.has(player):
		available_players.erase(player)

	if not busy_players.has(player):
		busy_players.append(player)


func mark_player_as_available(player: AudioStreamPlayer) -> void:
	if busy_players.has(player):
		busy_players.erase(player)

	if available_players.size() >= max_pool_size:
		available_players.erase(player)
		player.queue_free()
	elif not available_players.has(player):
		available_players.append(player)


func increase_pool() -> void:
	# See if we can reclaim a rogue busy player
	for player: AudioStreamPlayer in busy_players:
		if not player.playing:
			mark_player_as_available(player)
			return

	# Otherwise, add a new player
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(player)
	available_players.append(player)
	player.bus = bus
	player.finished.connect(_on_player_finished.bind(player))


func fade_volume(player: AudioStreamPlayer, from: float, to: float, duration: float) -> AudioStreamPlayer:
	# Clamp volume values between 0 and 1
	from = clampf(from, 0.0, 1.0)
	to = clampf(to, 0.0, 1.0)
	
	# Make sure duration isn't negative or ridiculously long
	duration = clampf(duration, 0.0, 100.0)
	
	# Remove any tweens that might already be on this player
	_remove_tween(player)

	# Start a new tween
	var tween: Tween = get_tree().create_tween().bind_node(self)

	player.volume_linear = from
	if from > to:
		# Fade out
		tween.tween_property(player, "volume_linear", to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		# Fade in
		tween.tween_property(player, "volume_linear", to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_tweens[player] = tween
	tween.finished.connect(_on_fade_completed.bind(player, tween, from, to, duration))

	return player


#region Helpers


func _remove_tween(player: AudioStreamPlayer) -> void:
	if _tweens.has(player):
		var fade: Tween = _tweens.get(player)
		fade.kill()
		_tweens.erase(player)


#endregion

#region Signals


func _on_player_finished(player: AudioStreamPlayer) -> void:
	mark_player_as_available(player)


func _on_fade_completed(player: AudioStreamPlayer, _tween: Tween, _from: float, to: float, _duration: float) -> void:
	_remove_tween(player)

	# If we just faded out then our player is now available
	if to <= 0:
		player.stop()
		mark_player_as_available(player)


#endregion
