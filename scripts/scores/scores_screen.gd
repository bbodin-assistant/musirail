extends Control

const START_MENU_SCENE: String = "res://scenes/start_menu/start_menu.tscn"
const TOUCH_SCROLL_BAR_WIDTH: float = 44.0

@onready var back_button: Button = $Background/Margin/Layout/TopBar/BackButton
@onready var song_list: VBoxContainer = (
	$Background/Margin/Layout/Columns/Songs/Scroll/SongList
)
@onready var difficulty_list: VBoxContainer = (
	$Background/Margin/Layout/Columns/Difficulties/Scroll/DifficultyList
)
@onready var history_list: VBoxContainer = (
	$Background/Margin/Layout/Columns/History/Scroll/HistoryList
)
@onready var song_heading: Label = (
	$Background/Margin/Layout/Columns/Songs/Heading
)
@onready var difficulty_heading: Label = (
	$Background/Margin/Layout/Columns/Difficulties/Heading
)
@onready var history_heading: Label = (
	$Background/Margin/Layout/Columns/History/Heading
)
@onready var empty_label: Label = (
	$Background/Margin/Layout/Columns/History/Scroll/HistoryList/EmptyLabel
)

var songs: Array[Dictionary] = []
var selected_song: Dictionary = {}
var selected_difficulty: Dictionary = {}
var song_buttons: Dictionary = {}
var difficulty_buttons: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_go_back)
	get_tree().root.go_back_requested.connect(_go_back)
	_configure_scroll_bars()
	_load_songs()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _configure_scroll_bars() -> void:
	for scroll: ScrollContainer in [
		$Background/Margin/Layout/Columns/Songs/Scroll,
		$Background/Margin/Layout/Columns/Difficulties/Scroll,
		$Background/Margin/Layout/Columns/History/Scroll,
	]:
		scroll.scroll_deadzone = 0
		scroll.get_v_scroll_bar().custom_minimum_size.x = (
			TOUCH_SCROLL_BAR_WIDTH
		)


func _load_songs() -> void:
	for song: Dictionary in SongLibrary.get_all_songs():
		if not SongLibrary.is_song_playable(song):
			continue
		songs.append(song)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0.0, 112.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 28)
		button.text = _song_button_text(song)
		button.pressed.connect(_select_song.bind(song))
		song_list.add_child(button)
		song_buttons[_song_id(song)] = button

	if songs.is_empty():
		song_heading.text = "NO SONGS"
		difficulty_heading.text = "DIFFICULTIES"
		history_heading.text = "LAST 10 SCORES"
		empty_label.text = "No playable songs found."
		return
	_select_song(songs[0])


func _select_song(song: Dictionary) -> void:
	selected_song = song.duplicate(true)
	selected_difficulty.clear()
	_set_selected_button(song_buttons, _song_id(song))
	song_heading.text = str(song.get("title", "UNTITLED")).to_upper()
	_clear_container(difficulty_list)
	difficulty_buttons.clear()
	var difficulties_value: Variant = song.get("difficulties", [])
	if not difficulties_value is Array:
		_show_empty_history("This song has no difficulties.")
		return
	var difficulties: Array = difficulties_value
	for difficulty_value: Variant in difficulties:
		if not difficulty_value is Dictionary:
			continue
		var difficulty: Dictionary = difficulty_value
		var difficulty_id: String = str(difficulty.get("id", "normal"))
		var stars: int = clampi(int(difficulty.get("stars", 1)), 1, 5)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0.0, 112.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_color_override(
			"font_color",
			Color(1.0, 0.84, 0.30, 1.0)
		)
		button.text = "%s\n%s" % [
			str(difficulty.get("label", difficulty_id)).to_upper(),
			"★".repeat(stars) + "☆".repeat(5 - stars),
		]
		button.pressed.connect(_select_difficulty.bind(difficulty))
		difficulty_list.add_child(button)
		difficulty_buttons[difficulty_id] = button
	if not difficulties.is_empty() and difficulties[0] is Dictionary:
		_select_difficulty(difficulties[0])


func _select_difficulty(difficulty: Dictionary) -> void:
	selected_difficulty = difficulty.duplicate(true)
	var difficulty_id: String = str(difficulty.get("id", "normal"))
	_set_selected_button(difficulty_buttons, difficulty_id)
	difficulty_heading.text = str(
		difficulty.get("label", difficulty_id)
	).to_upper()
	var best_score: int = SettingsManager.get_best_score(
		_song_id(selected_song),
		difficulty_id
	)
	history_heading.text = (
		"LAST 10 SCORES  •  BEST %09d" % best_score
		if best_score > 0
		else "LAST 10 SCORES"
	)
	_clear_container(history_list, empty_label)
	var records: Array[Dictionary] = SettingsManager.get_score_history(
		_song_id(selected_song),
		difficulty_id
	)
	if records.is_empty():
		_show_empty_history("No scores yet — play this difficulty!")
		return

	empty_label.visible = false
	var best_marked: bool = false
	for index: int in range(records.size()):
		var record: Dictionary = records[index]
		var is_best: bool = (
			not best_marked
			and bool(record.get("cleared", true))
			and int(record.get("score", 0)) == best_score
		)
		if is_best:
			best_marked = true
		_add_history_row(record, difficulty, index, is_best)


func _add_history_row(
	record: Dictionary,
	difficulty: Dictionary,
	index: int,
	is_best: bool
) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 118.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)

	var maximum_score: int = int(record.get(
		"maximum_score",
		difficulty.get("max_score", 0)
	))
	if maximum_score <= 0:
		maximum_score = int(difficulty.get("max_score", 0))
	var grade: String = ScoreGrade.grade_for_score(
		int(record.get("score", 0)),
		maximum_score
	)
	var grade_label: Label = Label.new()
	grade_label.custom_minimum_size = Vector2(92.0, 0.0)
	grade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_label.add_theme_font_size_override("font_size", 62)
	grade_label.add_theme_color_override(
		"font_color",
		ScoreGrade.grade_color(grade)
	)
	grade_label.text = grade
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var details: Label = Label.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_font_size_override("font_size", 25)
	var cleared: bool = bool(record.get("cleared", true))
	var status: String = str(record.get(
		"achievement",
		"CLEARED" if cleared else "FAILED"
	))
	if is_best:
		status = "BEST  •  " + status
	details.text = "%02d  %09d / %09d\n%.2f%%  •  COMBO %d  •  %s" % [
		index + 1,
		maxi(0, int(record.get("score", 0))),
		maximum_score,
		float(record.get("accuracy", 0.0)),
		maxi(0, int(record.get("max_combo", 0))),
		status,
	]
	details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var date_label: Label = Label.new()
	date_label.custom_minimum_size = Vector2(210.0, 0.0)
	date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_label.add_theme_font_size_override("font_size", 20)
	date_label.add_theme_color_override(
		"font_color",
		Color(0.65, 0.70, 0.82, 1.0)
	)
	date_label.text = _format_played_at(record)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	row.add_child(grade_label)
	row.add_child(details)
	row.add_child(date_label)
	history_list.add_child(row)


func _song_button_text(song: Dictionary) -> String:
	var title: String = str(song.get("title", "Untitled"))
	var artist: String = str(song.get("artist", ""))
	return title if artist.is_empty() else title + "\n" + artist


func _song_id(song: Dictionary) -> String:
	var identifier: String = str(song.get("id", ""))
	if not identifier.is_empty():
		return identifier
	return str(song.get("directory", "unknown")).get_file()


func _set_selected_button(buttons: Dictionary, selected_id: String) -> void:
	for identifier: Variant in buttons:
		var button_value: Variant = buttons[identifier]
		if not button_value is Button:
			continue
		var button: Button = button_value
		button.button_pressed = str(identifier) == selected_id


func _format_played_at(record: Dictionary) -> String:
	if bool(record.get("legacy", false)):
		return "PREVIOUS BEST"
	var timestamp: int = int(record.get("played_at", 0))
	if timestamp <= 0:
		return ""
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d\n%02d:%02d" % [
		int(date.get("year", 0)),
		int(date.get("month", 0)),
		int(date.get("day", 0)),
		int(date.get("hour", 0)),
		int(date.get("minute", 0)),
	]


func _show_empty_history(message: String) -> void:
	_clear_container(history_list, empty_label)
	empty_label.text = message
	empty_label.visible = true


func _clear_container(container: Container, keep: Control = null) -> void:
	for child: Node in container.get_children():
		if child == keep:
			continue
		container.remove_child(child)
		child.queue_free()


func _go_back() -> void:
	SettingsManager.save_settings()
	get_tree().change_scene_to_file(START_MENU_SCENE)
