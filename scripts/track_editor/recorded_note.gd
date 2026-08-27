class_name RecordedEditorNote
extends Node2D

const FADE_DURATION_SECONDS: float = 0.30
const TAP_COLOR: Color = Color.WHITE
const TAP_HEIGHT: float = 36.0
const FLICK_HEIGHT: float = 42.0
const HOLD_BODY_WIDTH_RATIO: float = 1.0
const SLIDE_BODY_WIDTH_RATIO: float = 1.0
const HOLD_BODY_COLOR: Color = Color(0.30, 1.0, 0.55, 0.80)
const SLIDE_BODY_COLOR: Color = Color(0.72, 0.35, 1.0, 0.70)
const FLICK_COLOR: Color = Color(1.0, 0.50, 0.16, 1.0)
const RELEASE_MARKER_COLOR: Color = Color(1.0, 0.82, 0.28, 1.0)
const RELEASE_MARKER_INNER_COLOR: Color = Color(0.10, 0.18, 0.25, 1.0)
const SLIDE_RELEASE_MARKER_INNER_COLOR: Color = Color(0.16, 0.08, 0.22, 1.0)

var gesture: RecordedTrackGesture
var note_width: float = 0.18
var note_type: String = "tap"
var final_note: Dictionary = {}
var active: bool = true
var end_time: float = 0.0


func configure_active(
	recorded_gesture: RecordedTrackGesture,
	width: float
) -> void:
	gesture = recorded_gesture
	note_width = width
	end_time = gesture.start_time
	queue_redraw()


func finalize(note: Dictionary) -> void:
	final_note = note.duplicate(true)
	note_type = str(note.get("type", "tap"))
	end_time = _note_end_time(note)
	active = false
	queue_redraw()


func get_display_type() -> String:
	if not active:
		return note_type
	var current_time: float = _current_song_time()
	var duration: float = maxf(current_time - gesture.start_time, 0.0)
	# Do not guess while a quick gesture is still in progress. A tap or flick
	# only becomes visible once its release speed and duration are known.
	if duration < RecordedTrackGesture.HOLD_MIN_DURATION:
		return "pending"
	if gesture.max_x_displacement >= RecordedTrackGesture.SLIDE_MIN_DISTANCE:
		return "slide"
	return "hold"


func _process(_delta: float) -> void:
	if gesture == null:
		queue_free()
		return

	note_type = get_display_type()
	if active:
		end_time = _current_song_time()
		modulate.a = 1.0
	else:
		var age_after_end: float = maxf(
			_current_song_time() - end_time,
			0.0
		)
		var fade_age: float = (
			age_after_end - NoteMotion.get_approach_time()
		)
		modulate.a = 1.0 - clampf(
			fade_age / FADE_DURATION_SECONDS,
			0.0,
			1.0
		)
		if fade_age >= FADE_DURATION_SECONDS:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if gesture == null:
		return
	var display_type: String = get_display_type()
	match display_type:
		"hold", "slide":
			_draw_sustained_gesture(display_type)
		"flick":
			_draw_flick()
		"tap":
			_draw_tap()
		_:
			pass


func _draw_sustained_gesture(display_type: String) -> void:
	var samples: Array[Dictionary] = _display_path(display_type)
	if samples.size() < 2:
		return
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)
	var points: PackedVector2Array = PackedVector2Array()
	var scales: PackedFloat32Array = PackedFloat32Array()
	var half_widths: PackedFloat32Array = PackedFloat32Array()
	var body_width_ratio: float = (
		HOLD_BODY_WIDTH_RATIO
		if display_type == "hold"
		else SLIDE_BODY_WIDTH_RATIO
	)
	for sample: Dictionary in samples:
		var progress: float = _travel_progress(float(sample["time"]))
		var perspective_scale: float = NoteMotion.perspective_scale(progress)
		points.append(_position_for_sample(sample, screen_size))
		scales.append(perspective_scale)
		half_widths.append(
			note_width
			* gameplay_width
			* perspective_scale
			* body_width_ratio
			/ 2.0
		)
	var body_color: Color = (
		HOLD_BODY_COLOR if display_type == "hold" else SLIDE_BODY_COLOR
	)
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		if start.distance_squared_to(finish) < 0.01:
			continue
		draw_colored_polygon(
			PackedVector2Array([
				start - Vector2(half_widths[index], 0.0),
				start + Vector2(half_widths[index], 0.0),
				finish + Vector2(half_widths[index + 1], 0.0),
				finish - Vector2(half_widths[index + 1], 0.0),
			]),
			body_color
		)

	_draw_release_marker(
		points[-1],
		scales[-1],
		(
			RELEASE_MARKER_INNER_COLOR
			if display_type == "hold"
			else SLIDE_RELEASE_MARKER_INNER_COLOR
		)
	)


func _draw_tap() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var position: Vector2 = _position_for_sample(
		{"time": gesture.start_time, "x": gesture.start_x},
		screen_size
	)
	var progress: float = _travel_progress(gesture.start_time)
	var width_pixels: float = (
		note_width
		* NoteMotion.gameplay_width(screen_size)
		* NoteMotion.perspective_scale(progress)
	)
	var height_pixels: float = (
		TAP_HEIGHT * NoteMotion.perspective_scale(progress)
	)
	draw_rect(
		Rect2(
			position - Vector2(width_pixels / 2.0, height_pixels / 2.0),
			Vector2(width_pixels, height_pixels)
		),
		TAP_COLOR
	)


func _draw_release_marker(
	marker_center: Vector2,
	scale_value: float,
	inner_color: Color
) -> void:
	var marker_radius: float = maxf(8.0, 18.0 * scale_value)
	draw_circle(
		marker_center,
		marker_radius * 1.45,
		RELEASE_MARKER_COLOR
	)
	draw_circle(
		marker_center,
		marker_radius * 0.72,
		inner_color
	)
	draw_line(
		marker_center + Vector2(-marker_radius * 0.42, 0.0),
		marker_center + Vector2(marker_radius * 0.42, 0.0),
		Color.WHITE,
		maxf(2.0, 4.0 * scale_value),
		true
	)


func _draw_flick() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var position: Vector2 = _position_for_sample(
		{"time": gesture.start_time, "x": gesture.start_x},
		screen_size
	)
	var progress: float = _travel_progress(gesture.start_time)
	var width_pixels: float = (
		note_width
		* NoteMotion.gameplay_width(screen_size)
		* NoteMotion.perspective_scale(progress)
	)
	var perspective_scale: float = NoteMotion.perspective_scale(progress)
	var height_pixels: float = FLICK_HEIGHT * perspective_scale
	draw_rect(
		Rect2(
			position - Vector2(width_pixels / 2.0, height_pixels / 2.0),
			Vector2(width_pixels, height_pixels)
		),
		FLICK_COLOR
	)
	var direction: Vector2 = _flick_direction_vector()
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var unscaled_width: float = (
		note_width * NoteMotion.gameplay_width(screen_size)
	)
	var arrow_size: float = (
		minf(unscaled_width * 0.28, 30.0) * perspective_scale
	)
	draw_colored_polygon(
		PackedVector2Array([
			position + direction * arrow_size,
			position - direction * arrow_size * 0.55
			+ perpendicular * arrow_size * 0.7,
			position - direction * arrow_size * 0.55
			- perpendicular * arrow_size * 0.7,
		]),
		Color.WHITE
	)


func _flick_direction_vector() -> Vector2:
	match str(final_note.get("direction", "up")):
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		_:
			return Vector2.UP


func _display_path(display_type: String) -> Array[Dictionary]:
	if not active:
		if display_type == "slide":
			var path_value: Variant = final_note.get("path", [])
			if path_value is Array:
				return _copy_path(path_value)
		return [
			{"time": gesture.start_time, "x": gesture.start_x},
			{"time": end_time, "x": gesture.last_x},
		]

	if display_type == "slide":
		var live_path: Array[Dictionary] = gesture.path.duplicate(true)
		_append_live_tail(live_path)
		return live_path
	return [
		{"time": gesture.start_time, "x": gesture.start_x},
		{"time": _current_song_time(), "x": gesture.start_x},
	]


func _append_live_tail(path: Array[Dictionary]) -> void:
	var current_time: float = _current_song_time()
	if path.is_empty():
		path.append({"time": current_time, "x": gesture.last_x})
		return
	if current_time <= float(path[-1]["time"]):
		current_time = float(path[-1]["time"]) + 0.000001
	path.append({"time": current_time, "x": gesture.last_x})


func _copy_path(path_value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Variant in path_value:
		if point is Dictionary:
			result.append(point.duplicate(true))
	return result


func _position_for_sample(
	sample: Dictionary,
	screen_size: Vector2
) -> Vector2:
	var progress: float = _travel_progress(float(sample["time"]))
	return Vector2(
		NoteMotion.x_position_at_progress(
			float(sample["x"]),
			progress,
			screen_size
		),
		NoteMotion.y_at_progress(progress, screen_size)
	)


func _travel_progress(sample_time: float) -> float:
	var age: float = maxf(_current_song_time() - sample_time, 0.0)
	return 1.0 - clampf(
		age / NoteMotion.get_approach_time(),
		0.0,
		1.0
	)


func _note_end_time(note: Dictionary) -> float:
	if str(note.get("type", "")) == "slide":
		var path_value: Variant = note.get("path", [])
		if path_value is Array:
			var note_path: Array = path_value
			if not note_path.is_empty() and note_path[-1] is Dictionary:
				return float(note_path[-1].get("time", gesture.last_time))
	return float(note.get("end_time", note.get("time", gesture.last_time)))


func _current_song_time() -> float:
	return SettingsManager.correct_input_time(
		float(GameManager.song_clock.get_song_time())
	)
