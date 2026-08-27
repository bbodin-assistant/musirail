extends Node

const TRACK_SETUP_SCENE: String = (
	"res://scenes/track_editor/track_setup.tscn"
)
const SONG_SELECT_SCENE: String = (
	"res://scenes/song_select/song_select.tscn"
)
const RecordedNoteScript = preload(
	"res://scripts/track_editor/recorded_note.gd"
)
const RecordedGestureScript = preload(
	"res://scripts/track_editor/recorded_gesture.gd"
)
const SIMULTANEOUS_PRESS_WINDOW: float = 0.035

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var cover: TextureRect = $SongBackground/Cover
@onready var recorded_notes: Node2D = $RecordedNotes
@onready var title_label: Label = $UI/Root/TopBar/Title
@onready var timer_label: Label = $UI/Root/TopBar/Timer
@onready var count_label: Label = $UI/Root/TopBar/Count
@onready var cancel_button: Button = $UI/Root/TopBar/CancelButton
@onready var intro_overlay: ColorRect = $UI/Root/IntroOverlay
@onready var intro_title: Label = $UI/Root/IntroOverlay/Center/Panel/Title
@onready var intro_help: Label = $UI/Root/IntroOverlay/Center/Panel/Help
@onready var start_button: Button = (
	$UI/Root/IntroOverlay/Center/Panel/StartButton
)
@onready var countdown_overlay: ColorRect = $UI/Root/CountdownOverlay
@onready var countdown_label: Label = (
	$UI/Root/CountdownOverlay/Center/Number
)
@onready var result_overlay: ColorRect = $UI/Root/ResultOverlay
@onready var result_title: Label = (
	$UI/Root/ResultOverlay/Center/Panel/Title
)
@onready var result_summary: Label = (
	$UI/Root/ResultOverlay/Center/Panel/Summary
)
@onready var result_button: Button = (
	$UI/Root/ResultOverlay/Center/Panel/ResultButton
)
@onready var retry_button: Button = (
	$UI/Root/ResultOverlay/Center/Panel/RetryButton
)
@onready var cancel_overlay: ColorRect = $UI/Root/CancelOverlay
@onready var keep_recording_button: Button = (
	$UI/Root/CancelOverlay/Center/Panel/Actions/KeepButton
)
@onready var discard_button: Button = (
	$UI/Root/CancelOverlay/Center/Panel/Actions/DiscardButton
)

var draft: Dictionary = {}
var chart_notes: Array[Dictionary] = []
var recording: bool = false
var saved_song: Dictionary = {}
var active_gestures: Dictionary = {}
var gesture_previews: Dictionary = {}
var chord_anchor_raw_time: float = -INF
var chord_anchor_chart_time: float = -INF
var resume_after_cancel: bool = false
var resume_countdown_after_cancel: bool = false
var countdown_running: bool = false
var countdown_token: int = 0


func _ready() -> void:
	draft = GameManager.get_track_editor_draft()
	if draft.is_empty():
		_return_to_setup()
		return

	var stream: AudioStream = SongLibrary.load_audio(
		str(draft.get("audio_path", ""))
	)
	if stream == null:
		push_error("Unable to load the selected editor audio.")
		_return_to_setup()
		return
	music_player.stream = stream
	GameManager.song_clock.set_audio_player(music_player)
	GameManager.song_clock.reset()
	InputManager.set_gameplay_input_enabled(false)
	_load_cover()
	var difficulty: Dictionary = draft.get("difficulty", {})
	var heading: String = str(draft.get("title", "Untitled Track"))
	if not str(draft.get("artist", "")).is_empty():
		heading += " — " + str(draft["artist"])
	title_label.text = heading
	intro_title.text = "%s  •  %s" % [
		heading,
		str(difficulty.get("label", "Normal")),
	]
	start_button.pressed.connect(_start_recording)
	cancel_button.pressed.connect(_request_cancel)
	keep_recording_button.pressed.connect(_resume_after_cancel)
	discard_button.pressed.connect(_return_to_setup)
	result_button.pressed.connect(_open_song_list)
	retry_button.pressed.connect(_retry_recording)
	music_player.finished.connect(_finish_recording)
	get_tree().root.go_back_requested.connect(_request_cancel)
	start_button.grab_focus()


func _exit_tree() -> void:
	InputManager.set_gameplay_input_enabled(true)


func _process(_delta: float) -> void:
	if not recording:
		return
	var elapsed: float = float(GameManager.song_clock.get_song_time())
	var duration: float = music_player.stream.get_length()
	timer_label.text = "%s / %s" % [
		_format_duration(elapsed),
		_format_duration(duration),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_request_cancel()
		return
	if not recording:
		return

	# Mouse input is already converted to these touch events by project.godot.
	# Handling both streams would record two overlapping notes for one click.
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_gesture(event.index, event.position)
		else:
			_finish_gesture(event.index, event.position)
	elif event is InputEventScreenDrag:
		_update_gesture(
			event.index,
			event.position,
			event.screen_velocity
		)


func _start_recording() -> void:
	if countdown_running:
		return
	_clear_visual_notes()
	chart_notes.clear()
	active_gestures.clear()
	gesture_previews.clear()
	chord_anchor_raw_time = -INF
	chord_anchor_chart_time = -INF
	count_label.text = "0 NOTES"
	timer_label.text = "0:00 / " + _format_duration(
		music_player.stream.get_length()
	)
	intro_overlay.visible = false
	result_overlay.visible = false
	cancel_overlay.visible = false
	recording = false
	music_player.stop()
	GameManager.song_clock.reset()
	_run_countdown()


func _run_countdown() -> void:
	countdown_running = true
	countdown_token += 1
	var current_token: int = countdown_token
	countdown_overlay.visible = true
	countdown_label.pivot_offset = countdown_label.size * 0.5
	for number: int in [3, 2, 1]:
		countdown_label.text = str(number)
		countdown_label.scale = Vector2(1.18, 1.18)
		var tween: Tween = create_tween()
		tween.tween_property(
			countdown_label,
			"scale",
			Vector2.ONE,
			0.22
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.0).timeout
		if current_token != countdown_token:
			return
	countdown_overlay.visible = false
	countdown_running = false
	recording = true
	GameManager.song_clock.reset()
	music_player.play(0.0)


func _begin_gesture(finger_id: int, screen_position: Vector2) -> void:
	if active_gestures.has(finger_id):
		return
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var left: float = NoteMotion.x_position(0.0, screen_size)
	var right: float = NoteMotion.x_position(1.0, screen_size)
	if screen_position.x < left or screen_position.x > right:
		return
	var raw_song_time: float = float(GameManager.song_clock.get_song_time())
	var corrected_time: float = clampf(
		SettingsManager.correct_input_time(raw_song_time),
		0.0,
		music_player.stream.get_length()
	)
	var event_time: float = corrected_time
	if raw_song_time - chord_anchor_raw_time <= SIMULTANEOUS_PRESS_WINDOW:
		event_time = chord_anchor_chart_time
	else:
		chord_anchor_raw_time = raw_song_time
		chord_anchor_chart_time = corrected_time
	var normalized_x: float = clampf(
		inverse_lerp(left, right, screen_position.x),
		0.0,
		1.0
	)
	var gesture: RecordedTrackGesture = RecordedGestureScript.new()
	gesture.configure(
		finger_id,
		event_time,
		normalized_x,
		screen_position
	)
	active_gestures[finger_id] = gesture
	var difficulty: Dictionary = draft.get("difficulty", {})
	var width: float = float(difficulty.get("width", 0.18))
	var preview: RecordedEditorNote = RecordedNoteScript.new()
	preview.configure_active(gesture, width)
	recorded_notes.add_child(preview)
	gesture_previews[finger_id] = preview


func _update_gesture(
	finger_id: int,
	screen_position: Vector2,
	velocity: Vector2
) -> void:
	if not active_gestures.has(finger_id):
		return
	var gesture: RecordedTrackGesture = active_gestures[finger_id]
	gesture.add_sample(
		_corrected_song_time(),
		_normalized_x(screen_position),
		screen_position,
		velocity
	)


func _finish_gesture(finger_id: int, screen_position: Vector2) -> void:
	if not active_gestures.has(finger_id):
		return
	var gesture: RecordedTrackGesture = active_gestures[finger_id]
	active_gestures.erase(finger_id)
	var difficulty: Dictionary = draft.get("difficulty", {})
	var width: float = float(difficulty.get("width", 0.18))
	var note: Dictionary = gesture.build_note(
		_corrected_song_time(),
		_normalized_x(screen_position),
		screen_position,
		width
	)
	chart_notes.append(note)
	var preview_value: Variant = gesture_previews.get(finger_id)
	gesture_previews.erase(finger_id)
	if preview_value is RecordedEditorNote:
		preview_value.finalize(note)
	count_label.text = "%d NOTES" % chart_notes.size()


func _corrected_song_time() -> float:
	return clampf(
		SettingsManager.correct_input_time(
			float(GameManager.song_clock.get_song_time())
		),
		0.0,
		music_player.stream.get_length()
	)


func _normalized_x(screen_position: Vector2) -> float:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var left: float = NoteMotion.x_position(0.0, screen_size)
	var right: float = NoteMotion.x_position(1.0, screen_size)
	return clampf(inverse_lerp(left, right, screen_position.x), 0.0, 1.0)


func _finalize_active_gestures() -> void:
	var finger_ids: Array = active_gestures.keys()
	for finger_id: Variant in finger_ids:
		var gesture: RecordedTrackGesture = active_gestures[finger_id]
		_finish_gesture(int(finger_id), gesture.last_position)


func _finish_recording() -> void:
	if not recording:
		return
	_finalize_active_gestures()
	recording = false
	if chart_notes.is_empty():
		_show_failed_result("No notes were recorded.")
		return
	saved_song = SongLibrary.save_recorded_song(
		draft,
		chart_notes,
		music_player.stream.get_length(),
		saved_song
	)
	if saved_song.is_empty():
		_show_failed_result("The track could not be saved.")
		return
	result_title.text = "TRACK SAVED"
	result_summary.text = (
		"%s\n%d notes recorded on %s.\n%s\nAdded to your song list."
		% [
			draft["title"],
			chart_notes.size(),
			draft["difficulty"]["label"],
			_gesture_summary(),
		]
	)
	result_button.visible = true
	result_button.text = "OPEN SONG LIST"
	retry_button.visible = true
	retry_button.text = "RESTART RECORDING"
	result_overlay.visible = true
	result_button.grab_focus()


func _show_failed_result(message: String) -> void:
	result_title.text = "NOT SAVED"
	result_summary.text = message + "\nYou can record the song again."
	result_button.visible = false
	retry_button.visible = true
	retry_button.text = "RETRY"
	result_overlay.visible = true
	retry_button.grab_focus()


func _retry_recording() -> void:
	result_overlay.visible = false
	_start_recording()


func _load_cover() -> void:
	var texture: Texture2D = SongLibrary.load_cover(
		str(draft.get("cover_path", ""))
	)
	if texture != null:
		cover.texture = texture


func _request_cancel() -> void:
	if cancel_overlay.visible:
		_resume_after_cancel()
		return
	resume_countdown_after_cancel = countdown_running
	if countdown_running:
		countdown_running = false
		countdown_token += 1
		countdown_overlay.visible = false
	resume_after_cancel = recording and music_player.playing
	if resume_after_cancel:
		music_player.stream_paused = true
	cancel_overlay.visible = true
	keep_recording_button.grab_focus()


func _resume_after_cancel() -> void:
	cancel_overlay.visible = false
	if resume_countdown_after_cancel:
		resume_countdown_after_cancel = false
		_run_countdown()
		return
	if resume_after_cancel and recording:
		music_player.stream_paused = false
	resume_after_cancel = false


func _return_to_setup() -> void:
	recording = false
	countdown_running = false
	countdown_token += 1
	active_gestures.clear()
	gesture_previews.clear()
	music_player.stop()
	var return_scene: String = str(
		draft.get("return_scene", TRACK_SETUP_SCENE)
	)
	if return_scene == TRACK_SETUP_SCENE:
		GameManager.set_track_editor_draft(draft)
	else:
		GameManager.clear_track_editor_draft()
	get_tree().change_scene_to_file(return_scene)


func _open_song_list() -> void:
	GameManager.clear_track_editor_draft()
	get_tree().change_scene_to_file(SONG_SELECT_SCENE)


func _clear_visual_notes() -> void:
	gesture_previews.clear()
	for child: Node in recorded_notes.get_children():
		child.queue_free()


func _gesture_summary() -> String:
	var counts: Dictionary = {
		"tap": 0,
		"hold": 0,
		"slide": 0,
		"flick": 0,
	}
	for note: Dictionary in chart_notes:
		var note_type: String = str(note.get("type", "tap"))
		counts[note_type] = int(counts.get(note_type, 0)) + 1
	return "%d taps  •  %d holds  •  %d slides  •  %d flicks" % [
		counts["tap"],
		counts["hold"],
		counts["slide"],
		counts["flick"],
	]


func _format_duration(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(seconds))
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]
