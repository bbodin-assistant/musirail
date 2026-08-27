extends Control

const SONG_SELECT_SCENE: String = (
	"res://scenes/song_select/song_select.tscn"
)
const CONFIG_SCENE: String = "res://scenes/config/config_menu.tscn"
const SCORES_SCENE: String = "res://scenes/scores/scores_screen.tscn"
const TRACK_SETUP_SCENE: String = (
	"res://scenes/track_editor/track_setup.tscn"
)

@onready var play_button: Button = $Background/Center/Menu/PlayButton
@onready var config_button: Button = $Background/Center/Menu/ConfigButton
@onready var scores_button: Button = $Background/Center/Menu/ScoresButton
@onready var editor_button: Button = $Background/Center/Menu/EditorButton
@onready var load_track_button: Button = (
	$Background/Center/Menu/LoadTrackButton
)
@onready var status_label: Label = $Background/Center/Menu/StatusLabel


func _ready() -> void:
	play_button.pressed.connect(_open_song_select)
	config_button.pressed.connect(_open_config)
	scores_button.pressed.connect(_open_scores)
	editor_button.pressed.connect(_open_track_editor)
	load_track_button.pressed.connect(_open_track_import)
	get_tree().root.go_back_requested.connect(_quit_game)
	play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_quit_game()


func _open_song_select() -> void:
	get_tree().change_scene_to_file(SONG_SELECT_SCENE)


func _open_config() -> void:
	get_tree().change_scene_to_file(CONFIG_SCENE)


func _open_scores() -> void:
	get_tree().change_scene_to_file(SCORES_SCENE)


func _open_track_editor() -> void:
	GameManager.clear_track_editor_draft()
	get_tree().change_scene_to_file(TRACK_SETUP_SCENE)


func _open_track_import() -> void:
	var error: Error = DisplayServer.file_dialog_show(
		"Load Musirail track",
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray([
			(
				"*.musirail;Musirail Track;"
				+ "application/zip,application/octet-stream"
			),
		]),
		_on_track_import_selected
	)
	if error != OK:
		_show_import_status(
			"The system file picker could not be opened.",
			false
		)


func _on_track_import_selected(
	accepted: bool,
	selected_paths: PackedStringArray,
	_selected_filter: int
) -> void:
	if not accepted or selected_paths.is_empty():
		return
	load_track_button.disabled = true
	var song: Dictionary = SongLibrary.import_song_package(selected_paths[0])
	load_track_button.disabled = false
	if song.is_empty():
		_show_import_status(SongLibrary.last_package_error, false)
		return
	_show_import_status(
		"%s loaded — open PLAY to find it." % str(song["title"]),
		true
	)


func _show_import_status(message: String, success: bool) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		(
			Color(0.55, 1.0, 0.72, 1.0)
			if success
			else Color(1.0, 0.48, 0.42, 1.0)
		)
	)
	status_label.visible = true


func _quit_game() -> void:
	SettingsManager.save_settings()
	get_tree().quit()
