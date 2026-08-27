extends Node

var audio_player: AudioStreamPlayer
var output_latency: float = 0.0

var last_song_time: float = 0.0


func _ready() -> void:
	output_latency = AudioServer.get_output_latency()
	print("SongClock ready")


func set_audio_player(player: AudioStreamPlayer) -> void:
	audio_player = player
	last_song_time = 0.0


func get_song_time() -> float:
	if audio_player == null:
		return 0.0

	if not audio_player.playing:
		return last_song_time

	var time := audio_player.get_playback_position()
	time += AudioServer.get_time_since_last_mix()
	time -= output_latency
	time += SettingsManager.audio_offset_seconds
	time = max(time, 0.0)

	# L'horloge musicale ne doit jamais revenir en arrière.
	if time < last_song_time:
		return last_song_time

	last_song_time = time
	return time


func reset() -> void:
	last_song_time = 0.0
