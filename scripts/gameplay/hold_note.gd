extends Node2D

@export var hit_time: float = 2.0
@export var end_time: float = 3.0
@export var note_x: float = 0.5
@export var note_width: float = 0.20
@export var release_required: bool = false

const RELEASE_WINDOW: float = 0.210
const VISUAL_CLEANUP_DELAY: float = 0.30
const RELEASE_MARKER_COLOR: Color = Color(1.0, 0.82, 0.28, 1.0)
const RELEASE_MARKER_INNER_COLOR: Color = Color(0.10, 0.18, 0.25, 1.0)

var judged: bool = false
var holding: bool = false
var active_finger_id: int = -1
var head_error: float = 0.0
var head_judgement: String = ""
var tail_offset: Vector2 = Vector2.ZERO
var head_width_pixels: float = 0.0
var tail_width_pixels: float = 0.0
var head_scale: float = 1.0
var tail_scale: float = 1.0
var resolved_result: String = ""
var next_sustain_tick_time: float = INF


func _ready() -> void:
	add_to_group("hittable_notes")


func _process(_delta: float) -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var song_time: float = float(
		GameManager.song_clock.get_song_time()
	)
	var visual_song_time: float = SettingsManager.get_visual_time(song_time)
	var time_until_hit: float = hit_time - visual_song_time

	if (
		not judged
		and not holding
		and time_until_hit > NoteMotion.get_approach_time()
	):
		visible = false
		return

	visible = true
	_update_position(screen_size, visual_song_time)
	if judged:
		if visual_song_time >= end_time + VISUAL_CLEANUP_DELAY:
			queue_free()
		else:
			queue_redraw()
		return

	if holding:
		if not InputManager.is_finger_pressed(active_finger_id):
			_resolve("MISS", song_time - end_time)
			return

		_award_sustain_ticks(song_time)
		if release_required:
			if song_time > end_time + RELEASE_WINDOW:
				_resolve("MISS", song_time - end_time)
				return
		elif song_time >= end_time:
			_resolve(head_judgement, head_error)
			return

	else:
		var late_error: float = song_time - hit_time

		if late_error > JudgementSystem.BAD_WINDOW:
			_resolve("MISS", late_error)
			return

	queue_redraw()


func can_receive_press(
	touch_position: Vector2,
	input_time: float
) -> bool:
	if judged or holding:
		return false

	if not _is_position_inside(touch_position):
		return false

	return JudgementSystem.is_inside_hit_window(
		input_time - hit_time
	)


func get_timing_error(input_time: float) -> float:
	return input_time - hit_time


func receive_press(
	_touch_position: Vector2,
	input_time: float,
	finger_id: int
) -> void:
	if judged or holding:
		return

	var error: float = input_time - hit_time

	if not JudgementSystem.is_inside_hit_window(error):
		return

	holding = true
	active_finger_id = finger_id
	head_error = error
	head_judgement = JudgementSystem.get_judgement(error)
	next_sustain_tick_time = (
		maxf(hit_time, input_time)
		+ ScoreManager.SUSTAIN_TICK_INTERVAL_SECONDS
	)
	remove_from_group("hittable_notes")
	queue_redraw()


func receive_release(
	_touch_position: Vector2,
	input_time: float,
	finger_id: int
) -> void:
	if judged or not is_tracking_finger(finger_id):
		return

	_award_sustain_ticks(minf(input_time, end_time))
	var release_error: float = input_time - end_time
	if release_required:
		if absf(release_error) > RELEASE_WINDOW:
			_resolve("MISS", release_error)
			return
		var release_judgement: String = JudgementSystem.get_judgement(
			release_error,
			RELEASE_WINDOW
		)
		_resolve(
			JudgementSystem.get_worst_judgement(
				head_judgement,
				release_judgement
			),
			release_error
		)
	elif input_time >= end_time - RELEASE_WINDOW:
		_resolve(head_judgement, head_error)
	else:
		_resolve("MISS", input_time - end_time)


func is_tracking_finger(finger_id: int) -> bool:
	return holding and active_finger_id == finger_id


func _is_position_inside(touch_position: Vector2) -> bool:
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)
	var note_center_x: float = NoteMotion.x_position(
		note_x,
		screen_size
	)
	var half_width: float = note_width * gameplay_width / 2.0

	return (
		touch_position.x >= note_center_x - half_width
		and touch_position.x <= note_center_x + half_width
	)


func _update_position(
	screen_size: Vector2,
	song_time: float
) -> void:
	var head_progress: float = (
		1.0
		if holding
		else NoteMotion.approach_progress(hit_time, song_time)
	)
	var tail_progress: float = NoteMotion.approach_progress(
		end_time,
		song_time
	)
	var head_position: Vector2 = Vector2(
		NoteMotion.x_position_at_progress(
			note_x,
			head_progress,
			screen_size
		),
		NoteMotion.y_at_progress(head_progress, screen_size)
	)
	var tail_position: Vector2 = NoteMotion.position_for_time(
		note_x,
		end_time,
		song_time,
		screen_size
	)
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)

	position = head_position
	tail_offset = tail_position - head_position
	head_scale = NoteMotion.perspective_scale(head_progress)
	tail_scale = NoteMotion.perspective_scale(tail_progress)
	head_width_pixels = note_width * gameplay_width * head_scale
	tail_width_pixels = note_width * gameplay_width * tail_scale


func _award_sustain_ticks(song_time: float) -> void:
	if next_sustain_tick_time == INF:
		return

	var tick_limit: float = minf(song_time, end_time)
	while next_sustain_tick_time <= tick_limit:
		if (
			InputManager.is_finger_pressed(active_finger_id)
			and _is_position_inside(
				InputManager.get_finger_position(active_finger_id)
			)
		):
			ScoreManager.register_sustain_tick()
		next_sustain_tick_time += (
			ScoreManager.SUSTAIN_TICK_INTERVAL_SECONDS
		)


func _resolve(result: String, error: float) -> void:
	if judged:
		return

	judged = true
	resolved_result = result
	if active_finger_id >= 0:
		NoteManager.release_active_gesture(active_finger_id, self)
	holding = false
	active_finger_id = -1
	remove_from_group("hittable_notes")

	ScoreManager.register_judgement(result)
	LifeManager.register_judgement(result)
	JudgementSystem.announce_judgement(result, error)
	NoteManager.request_hit_feedback(global_position, result)

	queue_redraw()


func _draw() -> void:
	var body_color: Color = (
		Color(0.95, 0.30, 0.34, 0.48)
		if judged and resolved_result == "MISS"
		else Color(0.30, 1.0, 0.55, 0.80)
		if holding
		else Color(0.20, 0.70, 1.0, 0.65)
	)
	if tail_offset.length_squared() > 0.0:
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(-head_width_pixels / 2.0, 0.0),
				Vector2(head_width_pixels / 2.0, 0.0),
				tail_offset + Vector2(tail_width_pixels / 2.0, 0.0),
				tail_offset - Vector2(tail_width_pixels / 2.0, 0.0)
			]),
			body_color
		)
	if release_required:
		var marker_center: Vector2 = tail_offset
		var marker_radius: float = maxf(8.0, 18.0 * tail_scale)
		draw_circle(
			marker_center,
			marker_radius * 1.45,
			RELEASE_MARKER_COLOR
		)
		draw_circle(
			marker_center,
			marker_radius * 0.72,
			RELEASE_MARKER_INNER_COLOR
		)
		draw_line(
			marker_center + Vector2(-marker_radius * 0.42, 0.0),
			marker_center + Vector2(marker_radius * 0.42, 0.0),
			Color.WHITE,
			maxf(2.0, 4.0 * tail_scale),
			true
		)
