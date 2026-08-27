extends Control

const GAMEPLAY_SCENE: String = "res://scenes/main/main.tscn"
const TRACK_SETUP_SCENE: String = (
	"res://scenes/track_editor/track_setup.tscn"
)
const START_MENU_SCENE: String = (
	"res://scenes/start_menu/start_menu.tscn"
)
const FALLBACK_COVER: Texture2D = preload("res://icon.svg")
const SCROLL_BAR_TOUCH_WIDTH: float = 48.0

@onready var song_scroll: ScrollContainer = (
	$Background/Margin/Layout/SongScroll
)
@onready var back_button: Button = (
	$Background/Margin/Layout/TopBar/BackButton
)
@onready var subtitle_label: Label = (
	$Background/Margin/Layout/Subtitle
)
@onready var song_list: VBoxContainer = (
	$Background/Margin/Layout/SongScroll/SongList
)
@onready var status_label: Label = (
	$Background/Margin/Layout/StatusLabel
)
@onready var visibility_slider: HSlider = (
	$Background/Margin/Layout/SpeedSettings/VisibilitySlider
)
@onready var visibility_label: Label = (
	$Background/Margin/Layout/SpeedSettings/VisibilityLabel
)
@onready var difficulty_overlay: ColorRect = $DifficultyOverlay
@onready var difficulty_song_label: Label = (
	$DifficultyOverlay/Center/Panel/SongLabel
)
@onready var difficulty_title_label: Label = (
	$DifficultyOverlay/Center/Panel/Title
)
@onready var difficulty_scroll: ScrollContainer = (
	$DifficultyOverlay/Center/Panel/DifficultyScroll
)
@onready var difficulty_buttons: VBoxContainer = (
	$DifficultyOverlay/Center/Panel/DifficultyScroll/DifficultyButtons
)
@onready var difficulty_cancel_button: Button = (
	$DifficultyOverlay/Center/Panel/CancelButton
)
@onready var delete_overlay: ColorRect = $DeleteOverlay
@onready var delete_message: Label = $DeleteOverlay/Center/Panel/Message
@onready var delete_cancel_button: Button = (
	$DeleteOverlay/Center/Panel/CancelButton
)
@onready var delete_confirm_button: Button = (
	$DeleteOverlay/Center/Panel/ConfirmButton
)

var pending_song: Dictionary = {}
var pending_delete_song: Dictionary = {}


func _ready() -> void:
	get_tree().root.go_back_requested.connect(_on_go_back_requested)
	back_button.pressed.connect(_go_to_start_menu)
	_configure_song_scroll()
	visibility_slider.min_value = NoteMotion.MIN_APPROACH_TIME
	visibility_slider.max_value = NoteMotion.MAX_APPROACH_TIME
	visibility_slider.value = SettingsManager.note_visibility_seconds
	visibility_slider.value_changed.connect(
		_on_visibility_changed
	)
	difficulty_cancel_button.pressed.connect(
		_close_difficulty_picker
	)
	delete_cancel_button.pressed.connect(_close_delete_confirmation)
	delete_confirm_button.pressed.connect(_confirm_delete_song)
	difficulty_scroll.get_v_scroll_bar().custom_minimum_size.x = (
		SCROLL_BAR_TOUCH_WIDTH
	)
	_update_visibility_label(visibility_slider.value)
	_populate_song_list()


func _configure_song_scroll() -> void:
	# Song cards cover almost the entire scroll area on phones. Let their
	# touch events bubble up so a drag scrolls instead of becoming a tap.
	song_scroll.scroll_deadzone = 0
	var vertical_scroll_bar: VScrollBar = song_scroll.get_v_scroll_bar()
	vertical_scroll_bar.custom_minimum_size.x = SCROLL_BAR_TOUCH_WIDTH


func _on_go_back_requested() -> void:
	if delete_overlay.visible:
		_close_delete_confirmation()
		return
	if difficulty_overlay.visible:
		_close_difficulty_picker()
		return

	_go_to_start_menu()


func _go_to_start_menu() -> void:
	SettingsManager.save_settings()
	get_tree().change_scene_to_file(START_MENU_SCENE)


func _populate_song_list() -> void:
	var songs: Array[Dictionary] = _load_song_catalog()
	var loaded_count: int = 0

	for song: Dictionary in songs:
		_add_song_button(song)
		loaded_count += 1

	if loaded_count == 0:
		_show_error("No playable songs found.")
	else:
		status_label.visible = false
		_update_career_summary(songs)


func _load_song_catalog() -> Array[Dictionary]:
	var songs: Array[Dictionary] = []
	for song: Dictionary in SongLibrary.get_all_songs():
		var song_directory: String = str(song.get("directory", ""))
		var difficulties_value: Variant = song.get("difficulties", [])

		if (
			not SongLibrary.is_song_playable(song)
			or not difficulties_value is Array
			or difficulties_value.is_empty()
		):
			push_warning("Skipping invalid cached song: " + song_directory)
			continue

		song["title"] = str(song.get("title", song_directory.get_file()))
		song["artist"] = str(song.get("artist", ""))
		song["difficulties"] = difficulties_value
		songs.append(song)

	return songs


func _add_song_button(song: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = _make_safe_node_name(str(song["title"]))
	row.custom_minimum_size = Vector2(0.0, 230.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 20)

	var button: Button = Button.new()
	button.name = "PlayButton"
	var heading: String = str(song["title"])

	if not str(song["artist"]).is_empty():
		heading += "  —  " + str(song["artist"])

	button.text = "%s\n%s" % [heading, _get_song_record_summary(song)]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 230.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_constant_override("icon_max_width", 190)
	button.add_theme_constant_override("h_separation", 48)
	button.icon = _load_cover(song)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_song_pressed.bind(song))

	var edit_button: Button = Button.new()
	edit_button.name = "EditButton"
	edit_button.text = "EDIT"
	edit_button.custom_minimum_size = Vector2(230.0, 230.0)
	edit_button.mouse_filter = Control.MOUSE_FILTER_PASS
	edit_button.add_theme_font_size_override("font_size", 38)
	edit_button.add_theme_color_override(
		"font_color",
		Color(0.55, 0.92, 1.0, 1.0)
	)
	edit_button.pressed.connect(_on_edit_pressed.bind(song))

	row.add_child(button)
	if SongLibrary.is_user_song(song):
		var actions: VBoxContainer = VBoxContainer.new()
		actions.name = "Actions"
		actions.custom_minimum_size = Vector2(230.0, 230.0)
		actions.add_theme_constant_override("separation", 8)
		edit_button.custom_minimum_size = Vector2(230.0, 71.0)
		edit_button.add_theme_font_size_override("font_size", 30)
		var share_button: Button = Button.new()
		share_button.name = "ShareButton"
		share_button.text = "SHARE"
		share_button.custom_minimum_size = Vector2(230.0, 71.0)
		share_button.mouse_filter = Control.MOUSE_FILTER_PASS
		share_button.add_theme_font_size_override("font_size", 30)
		share_button.add_theme_color_override(
			"font_color",
			Color(0.55, 1.0, 0.72, 1.0)
		)
		share_button.pressed.connect(_on_share_pressed.bind(song))
		var delete_button: Button = Button.new()
		delete_button.name = "DeleteButton"
		delete_button.text = "DELETE"
		delete_button.custom_minimum_size = Vector2(230.0, 71.0)
		delete_button.mouse_filter = Control.MOUSE_FILTER_PASS
		delete_button.add_theme_font_size_override("font_size", 30)
		delete_button.add_theme_color_override(
			"font_color",
			Color(1.0, 0.42, 0.40, 1.0)
		)
		delete_button.pressed.connect(_request_delete_song.bind(song))
		actions.add_child(edit_button)
		actions.add_child(share_button)
		actions.add_child(delete_button)
		row.add_child(actions)
	else:
		row.add_child(edit_button)
	song_list.add_child(row)
	print("Song selection loaded: ", song["title"])


func _load_cover(song: Dictionary) -> Texture2D:
	var cover_name: String = str(song.get("cover", ""))

	if cover_name.is_empty():
		return FALLBACK_COVER

	var cover_path: String = SongLibrary.get_cover_path(song)
	if not SongLibrary.asset_exists(cover_path):
		push_warning("Song cover not found: " + cover_path)
		return FALLBACK_COVER

	var cover: Texture2D = SongLibrary.load_cover(cover_path)
	return cover if cover != null else FALLBACK_COVER


func _on_song_pressed(song: Dictionary) -> void:
	_open_difficulty_picker(song)


func _on_edit_pressed(song: Dictionary) -> void:
	_open_song_in_editor(song)


func _request_delete_song(song: Dictionary) -> void:
	if not SongLibrary.is_user_song(song):
		return
	pending_delete_song = song.duplicate(true)
	delete_message.text = (
		"Delete \"%s\"?\nThe audio, cover, chart and score history "
		+ "will be permanently removed."
	) % str(song.get("title", "Untitled Track"))
	delete_overlay.visible = true
	delete_cancel_button.grab_focus()


func _close_delete_confirmation() -> void:
	delete_overlay.visible = false
	pending_delete_song.clear()


func _confirm_delete_song() -> void:
	if pending_delete_song.is_empty():
		return
	delete_confirm_button.disabled = true
	var song: Dictionary = pending_delete_song.duplicate(true)
	if not SongLibrary.delete_user_song(song):
		delete_confirm_button.disabled = false
		delete_overlay.visible = false
		pending_delete_song.clear()
		_show_error(SongLibrary.last_delete_error)
		return
	SettingsManager.delete_song_scores(_get_song_score_id(song))
	delete_overlay.visible = false
	pending_delete_song.clear()
	get_tree().reload_current_scene()


func _on_share_pressed(song: Dictionary) -> void:
	var suggested_name: String = (
		_make_safe_file_name(str(song.get("title", "track")))
		+ ".musirail"
	)
	var error: Error = DisplayServer.file_dialog_show(
		"Share Musirail track",
		"",
		suggested_name,
		false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray([
			(
				"*.musirail;Musirail Track;"
				+ "application/zip,application/octet-stream"
			),
		]),
		_on_share_location_selected.bind(song)
	)
	if error != OK:
		_show_error("The system save dialog could not be opened.")


func _on_share_location_selected(
	accepted: bool,
	selected_paths: PackedStringArray,
	_selected_filter: int,
	song: Dictionary
) -> void:
	if not accepted or selected_paths.is_empty():
		return
	var destination: String = selected_paths[0]
	if (
		not destination.begins_with("content://")
		and destination.get_extension().to_lower() != "musirail"
	):
		destination += ".musirail"
	var error: Error = SongLibrary.export_song_package(song, destination)
	if error != OK:
		_show_error(SongLibrary.last_package_error)
		return
	var share_sheet_opened: bool = _open_android_share_sheet(destination)
	status_label.text = (
		"CHOOSE A FRIEND OR APP TO SHARE WITH"
		if share_sheet_opened
		else "TRACK PACKAGE SAVED — SEND THE .MUSIRAIL FILE"
	)
	status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 1.0, 0.72, 1.0)
	)
	status_label.visible = true


func _open_android_share_sheet(package_uri: String) -> bool:
	if OS.get_name() != "Android" or not package_uri.begins_with("content://"):
		return false
	var android_runtime: Object = Engine.get_singleton("AndroidRuntime")
	if android_runtime == null:
		return false
	var activity: Object = android_runtime.getActivity()
	if activity == null:
		return false
	var open_share_sheet: Callable = func() -> void:
		var intent_class: Object = JavaClassWrapper.wrap(
			"android.content.Intent"
		)
		var uri_class: Object = JavaClassWrapper.wrap("android.net.Uri")
		var intent: Object = intent_class.Intent()
		intent.setAction(intent_class.ACTION_SEND)
		intent.putExtra(
			intent_class.EXTRA_STREAM,
			uri_class.parse(package_uri)
		)
		intent.addFlags(intent_class.FLAG_GRANT_READ_URI_PERMISSION)
		intent.setType("application/zip")
		activity.startActivity(
			intent_class.createChooser(intent, "Share Musirail track")
		)
	activity.runOnUiThread(
		android_runtime.createRunnableFromGodotCallable(open_share_sheet)
	)
	return true


func _open_difficulty_picker(song: Dictionary) -> void:
	pending_song = song.duplicate(true)
	difficulty_title_label.text = "SELECT DIFFICULTY"
	difficulty_song_label.text = str(song["title"])
	_clear_difficulty_buttons()

	for difficulty: Dictionary in song["difficulties"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(1500.0, 158.0)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 18)
		var stars: int = int(difficulty["stars"])
		var record: Dictionary = SettingsManager.get_best_result(
			_get_song_score_id(song),
			str(difficulty.get("id", "normal"))
		)

		var difficulty_button: Button = Button.new()
		difficulty_button.name = "DifficultyButton"
		difficulty_button.text = "%s     %s" % [
			str(difficulty["label"]).to_upper(),
			"★".repeat(stars) + "☆".repeat(5 - stars),
		]
		difficulty_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		difficulty_button.custom_minimum_size = Vector2(940.0, 158.0)
		difficulty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		difficulty_button.mouse_filter = Control.MOUSE_FILTER_PASS
		difficulty_button.add_theme_font_size_override("font_size", 46)
		difficulty_button.add_theme_color_override(
			"font_color",
			Color(1.0, 0.84, 0.30, 1.0)
		)
		difficulty_button.pressed.connect(
			_on_difficulty_pressed.bind(difficulty)
		)

		var record_button: Button = Button.new()
		record_button.name = "RecordButton"
		record_button.text = _get_difficulty_record_summary(record)
		record_button.custom_minimum_size = Vector2(520.0, 158.0)
		record_button.mouse_filter = Control.MOUSE_FILTER_PASS
		record_button.add_theme_font_size_override("font_size", 30)
		record_button.pressed.connect(
			_on_difficulty_pressed.bind(difficulty)
		)

		row.add_child(difficulty_button)
		row.add_child(record_button)
		difficulty_buttons.add_child(row)

	difficulty_overlay.visible = true


func _on_difficulty_pressed(difficulty: Dictionary) -> void:
	if pending_song.is_empty():
		return

	var selected_song: Dictionary = pending_song.duplicate(true)
	selected_song["difficulty_id"] = str(difficulty["id"])
	selected_song["difficulty"] = str(difficulty["label"])
	selected_song["stars"] = int(difficulty["stars"])
	difficulty_overlay.visible = false

	SettingsManager.set_note_visibility(visibility_slider.value)
	SettingsManager.save_settings()
	print(
		"Song selected: ",
		selected_song["title"],
		" | difficulty: ",
		selected_song["difficulty"],
		" | note visibility: ",
		NoteMotion.get_approach_time(),
		" s"
	)
	GameManager.select_song(selected_song)
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _open_song_in_editor(song: Dictionary) -> void:
	var difficulty: Dictionary = _get_editor_difficulty(song)
	var stars: int = clampi(int(difficulty.get("stars", 3)), 1, 5)
	var editor_difficulty: Dictionary = difficulty.duplicate(true)
	editor_difficulty["id"] = str(difficulty.get("id", "normal"))
	editor_difficulty["label"] = str(
		difficulty.get("label", "Normal")
	)
	editor_difficulty["stars"] = stars
	editor_difficulty["width"] = lerpf(0.21, 0.16, (stars - 1) / 4.0)

	GameManager.set_track_editor_draft({
		"title": "%s (Copy)" % str(song.get("title", "Untitled Track")),
		"artist": str(song.get("artist", "")),
		"audio_path": SongLibrary.get_audio_path(song),
		"cover_path": SongLibrary.get_cover_path(song),
		"difficulty": editor_difficulty,
		"clone_source_id": str(song.get("id", "")),
		"setup_return_scene": "res://scenes/song_select/song_select.tscn",
		"prefilled_edit": true,
	})
	get_tree().change_scene_to_file(TRACK_SETUP_SCENE)


func _get_editor_difficulty(song: Dictionary) -> Dictionary:
	var difficulties_value: Variant = song.get("difficulties", [])
	if not difficulties_value is Array:
		return {
			"id": "normal",
			"label": "Normal",
			"stars": 2,
		}

	var difficulties: Array = difficulties_value
	for difficulty_value: Variant in difficulties:
		if (
			difficulty_value is Dictionary
			and str(difficulty_value.get("id", "")) == "normal"
		):
			return difficulty_value.duplicate(true)
	for difficulty_value: Variant in difficulties:
		if difficulty_value is Dictionary:
			return difficulty_value.duplicate(true)
	return {
		"id": "normal",
		"label": "Normal",
		"stars": 2,
	}


func _close_difficulty_picker() -> void:
	difficulty_overlay.visible = false
	pending_song.clear()
	_clear_difficulty_buttons()


func _clear_difficulty_buttons() -> void:
	for child: Node in difficulty_buttons.get_children():
		difficulty_buttons.remove_child(child)
		child.queue_free()


func _on_visibility_changed(value: float) -> void:
	SettingsManager.set_note_visibility(value)
	_update_visibility_label(NoteMotion.get_approach_time())


func _update_visibility_label(value: float) -> void:
	visibility_label.text = "NOTE VISIBILITY: " + (
		"%d ms" % int(round(value * 1000.0))
		if value < 1.0
		else "%.2f s" % value
	)


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.visible = true


func _get_song_score_id(song: Dictionary) -> String:
	var song_id: String = str(song.get("id", ""))
	if not song_id.is_empty():
		return song_id
	return str(song.get("directory", "unknown")).get_file()


func _get_song_record_summary(song: Dictionary) -> String:
	var difficulties_value: Variant = song.get("difficulties", [])
	if not difficulties_value is Array:
		return "NO SCORE YET"

	var difficulties: Array = difficulties_value
	var song_id: String = _get_song_score_id(song)
	var best_score: int = 0
	var cleared_count: int = 0
	var best_grade: String = "F"
	for difficulty_value: Variant in difficulties:
		if not difficulty_value is Dictionary:
			continue
		var difficulty: Dictionary = difficulty_value
		var record: Dictionary = SettingsManager.get_best_result(
			song_id,
			str(difficulty.get("id", "normal"))
		)
		if record.is_empty():
			continue
		cleared_count += 1
		best_score = maxi(best_score, int(record.get("score", 0)))
		var grade: String = ScoreGrade.grade_for_score(
			int(record.get("score", 0)),
			int(difficulty.get("max_score", 0))
		)
		if ScoreGrade.grade_rank(grade) > ScoreGrade.grade_rank(best_grade):
			best_grade = grade

	if cleared_count == 0:
		return "NO SCORE YET  •  0/%d CLEARED" % difficulties.size()
	return "GRADE %s  •  BEST %09d  •  %d/%d CLEARED" % [
		best_grade,
		best_score,
		cleared_count,
		difficulties.size(),
	]


func _get_difficulty_record_summary(record: Dictionary) -> String:
	if record.is_empty():
		return "NO SCORE YET"

	return "BEST  %09d\nMAX COMBO  %d" % [
		maxi(0, int(record.get("score", 0))),
		maxi(0, int(record.get("max_combo", 0))),
	]


func _update_career_summary(songs: Array[Dictionary]) -> void:
	var chart_count: int = 0
	var cleared_count: int = 0
	var career_score: int = 0
	for song: Dictionary in songs:
		var difficulties_value: Variant = song.get("difficulties", [])
		if not difficulties_value is Array:
			continue
		var song_id: String = _get_song_score_id(song)
		for difficulty_value: Variant in difficulties_value:
			if not difficulty_value is Dictionary:
				continue
			chart_count += 1
			var difficulty: Dictionary = difficulty_value
			var record: Dictionary = SettingsManager.get_best_result(
				song_id,
				str(difficulty.get("id", "normal"))
			)
			if record.is_empty():
				continue
			cleared_count += 1
			career_score += maxi(0, int(record.get("score", 0)))

	if cleared_count == 0:
		subtitle_label.text = "Choose a track to begin  •  No scores yet"
		return
	subtitle_label.text = "%d/%d CHARTS CLEARED  •  CAREER SCORE %d" % [
		cleared_count,
		chart_count,
		career_score,
	]


func _make_safe_node_name(title: String) -> String:
	return title.replace("/", "_").replace(".", "_") + "Button"


func _make_safe_file_name(title: String) -> String:
	var result: String = ""
	for character: String in title.strip_edges():
		if character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			result += "_"
		else:
			result += character
	return result if not result.is_empty() else "track"
