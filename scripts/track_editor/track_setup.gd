extends Control

const START_MENU_SCENE: String = (
	"res://scenes/start_menu/start_menu.tscn"
)
const RECORDER_SCENE: String = (
	"res://scenes/track_editor/track_recorder.tscn"
)
const TRACK_SETUP_SCENE: String = (
	"res://scenes/track_editor/track_setup.tscn"
)
const DIFFICULTIES: Array[Dictionary] = [
	{"id": "easy", "label": "Easy", "stars": 1, "width": 0.21},
	{"id": "normal", "label": "Normal", "stars": 2, "width": 0.20},
	{"id": "hard", "label": "Hard", "stars": 3, "width": 0.18},
	{"id": "expert", "label": "Expert", "stars": 4, "width": 0.17},
	{"id": "master", "label": "Master", "stars": 5, "width": 0.16},
]
const SELECTED_STAR_COLOR: Color = Color(1.0, 0.82, 0.18, 1.0)
const UNSELECTED_STAR_COLOR: Color = Color(0.34, 0.40, 0.52, 1.0)

@onready var title_edit: LineEdit = (
	$Background/Center/Form/IdentityRow/TitleField/Edit
)
@onready var heading_label: Label = $Background/Center/Form/Heading
@onready var help_label: Label = $Background/Center/Form/Help
@onready var artist_edit: LineEdit = (
	$Background/Center/Form/IdentityRow/ArtistField/Edit
)
@onready var audio_button: Button = (
	$Background/Center/Form/AssetRow/AudioChoice/Button
)
@onready var audio_check: Label = (
	$Background/Center/Form/AssetRow/AudioChoice/Check
)
@onready var cover_button: Button = (
	$Background/Center/Form/AssetRow/CoverChoice/Button
)
@onready var cover_check: Label = (
	$Background/Center/Form/AssetRow/CoverChoice/Check
)
@onready var difficulty_stars: HBoxContainer = (
	$Background/Center/Form/DifficultyRow/Stars
)
@onready var status_label: Label = $Background/Center/Form/StatusLabel
@onready var start_button: Button = $Background/Center/Form/Actions/StartButton
@onready var back_button: Button = $Background/Center/Form/Actions/BackButton
@onready var audio_dialog: FileDialog = $AudioDialog
@onready var cover_dialog: FileDialog = $CoverDialog

var audio_path: String = ""
var cover_path: String = ""
var selected_difficulty_index: int = 2
var star_buttons: Array[Button] = []
var initial_draft: Dictionary = {}


func _ready() -> void:
	initial_draft = GameManager.get_track_editor_draft()
	_create_difficulty_stars()
	if initial_draft.is_empty():
		_select_difficulty(selected_difficulty_index)
	else:
		_apply_prefilled_draft(initial_draft)
	audio_button.pressed.connect(audio_dialog.popup_file_dialog)
	cover_button.pressed.connect(cover_dialog.popup_file_dialog)
	audio_dialog.file_selected.connect(_on_audio_selected)
	cover_dialog.file_selected.connect(_on_cover_selected)
	title_edit.text_changed.connect(_on_form_changed)
	start_button.pressed.connect(_start_recording)
	back_button.pressed.connect(_go_back)
	get_tree().root.go_back_requested.connect(_go_back)
	_update_start_button()


func _apply_prefilled_draft(prefill: Dictionary) -> void:
	heading_label.text = "EDIT TRACK COPY"
	help_label.text = (
		"Change the details, then open the recorder to create its chart."
	)
	title_edit.text = str(prefill.get("title", ""))
	artist_edit.text = str(prefill.get("artist", ""))
	audio_path = str(prefill.get("audio_path", ""))
	if SongLibrary.asset_exists(audio_path):
		audio_check.visible = true
		audio_button.text = "CHANGE SONG"
	else:
		audio_path = ""
		audio_check.visible = false

	cover_path = str(prefill.get("cover_path", ""))
	if not cover_path.is_empty() and SongLibrary.asset_exists(cover_path):
		cover_check.visible = true
		cover_button.text = "CHANGE COVER"
	else:
		cover_path = ""
		cover_check.visible = false

	var difficulty_value: Variant = prefill.get("difficulty", {})
	var difficulty: Dictionary = (
		difficulty_value if difficulty_value is Dictionary else {}
	)
	_select_difficulty(_difficulty_index(difficulty))


func _difficulty_index(difficulty: Dictionary) -> int:
	var difficulty_id: String = str(difficulty.get("id", ""))
	for index: int in range(DIFFICULTIES.size()):
		if str(DIFFICULTIES[index]["id"]) == difficulty_id:
			return index
	return clampi(
		int(difficulty.get("stars", selected_difficulty_index + 1)) - 1,
		0,
		DIFFICULTIES.size() - 1
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _on_audio_selected(path: String) -> void:
	var stream: AudioStream = SongLibrary.load_audio(path)
	if stream == null:
		audio_path = ""
		audio_check.visible = false
		status_label.text = "Choose an OGG, MP3, or WAV file."
		_update_start_button()
		return
	audio_path = path
	audio_check.visible = true
	audio_button.text = "CHANGE SONG"
	_update_start_button()


func _on_cover_selected(path: String) -> void:
	var texture: Texture2D = SongLibrary.load_cover(path)
	if texture == null:
		cover_path = ""
		cover_check.visible = false
		status_label.text = "Choose a PNG, JPG, or WEBP image."
		return
	cover_path = path
	cover_check.visible = true
	cover_button.text = "CHANGE COVER"
	_update_start_button()


func _on_form_changed(_value: String) -> void:
	_update_start_button()


func _update_start_button() -> void:
	var title_missing: bool = title_edit.text.strip_edges().is_empty()
	var song_missing: bool = audio_path.is_empty()
	start_button.disabled = title_missing or song_missing
	if title_missing and song_missing:
		status_label.text = "Add a title and select a song. Cover is optional."
	elif title_missing:
		status_label.text = "Add a title. Cover is optional."
	elif song_missing:
		status_label.text = "Select a song. Cover is optional."
	else:
		status_label.text = "Ready to record."


func _create_difficulty_stars() -> void:
	for index: int in range(DIFFICULTIES.size()):
		var button: Button = Button.new()
		button.name = "Star%d" % (index + 1)
		button.text = "★"
		button.flat = true
		button.custom_minimum_size = Vector2(116.0, 92.0)
		button.add_theme_font_size_override("font_size", 66)
		button.pressed.connect(_select_difficulty.bind(index))
		difficulty_stars.add_child(button)
		star_buttons.append(button)


func _select_difficulty(index: int) -> void:
	selected_difficulty_index = clampi(index, 0, DIFFICULTIES.size() - 1)
	for star_index: int in range(star_buttons.size()):
		var selected: bool = star_index <= selected_difficulty_index
		var button: Button = star_buttons[star_index]
		button.text = "★" if selected else "☆"
		var color: Color = (
			SELECTED_STAR_COLOR if selected else UNSELECTED_STAR_COLOR
		)
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color)
		button.add_theme_color_override("font_pressed_color", color)
		button.add_theme_color_override("font_focus_color", color)


func _start_recording() -> void:
	if start_button.disabled:
		return
	var difficulty: Dictionary = DIFFICULTIES[
		selected_difficulty_index
	].duplicate(true)
	var recorder_draft: Dictionary = {
		"title": title_edit.text.strip_edges(),
		"artist": artist_edit.text.strip_edges(),
		"audio_path": audio_path,
		"cover_path": cover_path,
		"difficulty": difficulty,
		"return_scene": TRACK_SETUP_SCENE,
		"setup_return_scene": str(initial_draft.get(
			"setup_return_scene",
			START_MENU_SCENE
		)),
	}
	if initial_draft.has("clone_source_id"):
		recorder_draft["clone_source_id"] = str(
			initial_draft["clone_source_id"]
		)
	if bool(initial_draft.get("prefilled_edit", false)):
		recorder_draft["prefilled_edit"] = true
	GameManager.set_track_editor_draft(recorder_draft)
	get_tree().change_scene_to_file(RECORDER_SCENE)


func _go_back() -> void:
	var return_scene: String = str(initial_draft.get(
		"setup_return_scene",
		START_MENU_SCENE
	))
	GameManager.clear_track_editor_draft()
	get_tree().change_scene_to_file(return_scene)
