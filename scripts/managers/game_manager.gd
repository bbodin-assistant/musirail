extends Node

const SongClockScript = preload("res://scripts/core/song_clock.gd")
var song_clock: Node
var selected_song: Dictionary = {}
var track_editor_draft: Dictionary = {}


func _ready() -> void:
	print("GameManager ready")

	song_clock = SongClockScript.new()
	song_clock.name = "SongClock"
	add_child(song_clock)


func select_song(song: Dictionary) -> void:
	selected_song = song.duplicate(true)


func get_selected_song() -> Dictionary:
	return selected_song.duplicate(true)


func set_track_editor_draft(draft: Dictionary) -> void:
	track_editor_draft = draft.duplicate(true)


func get_track_editor_draft() -> Dictionary:
	return track_editor_draft.duplicate(true)


func clear_track_editor_draft() -> void:
	track_editor_draft.clear()
