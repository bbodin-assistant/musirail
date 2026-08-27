extends Node

const SONG_SELECT_SCENE: String = (
	"res://scenes/song_select/song_select.tscn"
)
const FALLBACK_COVER: Texture2D = preload("res://icon.svg")

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var background_cover: TextureRect = $SongBackground/Cover
@onready var notes: Node2D = $Notes
@onready var pause_menu: GameplayPauseMenu = $PauseMenu
@onready var results_screen: ResultsScreen = $ResultsScreen

var game_paused: bool = false
var song_finished: bool = false


func _ready() -> void:
	var song: Dictionary = GameManager.get_selected_song()
	if song.is_empty():
		push_warning("Gameplay opened without a selected song.")
		get_tree().change_scene_to_file(SONG_SELECT_SCENE)
		return
	var audio_path: String = SongLibrary.get_audio_path(song)
	var chart_path: String = SongLibrary.get_chart_path(song)
	var audio_stream: AudioStream = SongLibrary.load_audio(audio_path)
	_load_background_cover(song)

	if audio_stream == null:
		push_error("Unable to load song audio: " + audio_path)
		get_tree().change_scene_to_file(SONG_SELECT_SCENE)
		return

	music_player.stream = audio_stream

	GameManager.song_clock.set_audio_player(music_player)
	GameManager.song_clock.reset()

	ScoreManager.reset()
	LifeManager.reset()

	pause_menu.set_pause_available(true)

	music_player.finished.connect(_on_music_finished)
	pause_menu.pause_requested.connect(_pause_game)
	pause_menu.resume_ready.connect(_resume_game)
	pause_menu.restart_requested.connect(_restart_song)
	pause_menu.quit_requested.connect(_quit_to_song_select)
	results_screen.restart_requested.connect(_restart_song)
	results_screen.return_requested.connect(_quit_to_song_select)

	ChartManager.load_chart(
		chart_path,
		notes,
		str(song.get("difficulty_id", "normal"))
	)

	music_player.play(0.0)


func _load_background_cover(song: Dictionary) -> void:
	var cover_name: String = str(song.get("cover", ""))

	if cover_name.is_empty():
		background_cover.texture = FALLBACK_COVER
		return

	var cover_path: String = SongLibrary.get_cover_path(song)
	var cover: Texture2D = SongLibrary.load_cover(cover_path)
	background_cover.texture = cover if cover != null else FALLBACK_COVER


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		and is_node_ready()
	):
		_pause_game()


func _on_music_finished() -> void:
	song_finished = true
	pause_menu.set_pause_available(false)
	InputManager.set_gameplay_input_enabled(false)

	var song: Dictionary = GameManager.get_selected_song()
	var song_id: String = str(song.get("id", ""))
	if song_id.is_empty():
		song_id = str(song.get("directory", "unknown")).get_file()
	var difficulty_id: String = str(song.get("difficulty_id", "normal"))
	var summary: Dictionary = ScoreManager.get_result_summary()
	var cleared: bool = LifeManager.is_cleared()
	summary["cleared"] = cleared
	summary["life_percentage"] = LifeManager.life
	if not cleared:
		summary["achievement"] = "FAILED"
	var is_new_best: bool = SettingsManager.register_result(
		song_id,
		difficulty_id,
		summary
	)
	var best_score: int = SettingsManager.get_best_score(
		song_id,
		difficulty_id
	)
	results_screen.show_results(
		song,
		summary,
		best_score,
		is_new_best
	)


func _pause_game() -> void:
	if game_paused or song_finished:
		return

	game_paused = true
	music_player.stream_paused = true
	InputManager.set_gameplay_input_enabled(false)
	get_tree().paused = true
	pause_menu.show_paused()


func _resume_game() -> void:
	if not game_paused:
		return

	get_tree().paused = false
	InputManager.set_gameplay_input_enabled(true)
	music_player.stream_paused = false
	game_paused = false


func _restart_song() -> void:
	_prepare_scene_change()
	get_tree().reload_current_scene()


func _quit_to_song_select() -> void:
	_prepare_scene_change()
	get_tree().change_scene_to_file(SONG_SELECT_SCENE)


func _prepare_scene_change() -> void:
	get_tree().paused = false
	InputManager.set_gameplay_input_enabled(true)
	music_player.stream_paused = false
	game_paused = false
