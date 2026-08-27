extends Node2D

@export var hit_time: float = 2.0
@export var end_time: float = 3.0
@export var note_x: float = 0.25
@export var end_x: float = 0.75
@export var note_width: float = 0.20
@export_enum("linear", "smooth") var interpolation: String = "linear"
@export var release_required: bool = false

const TRACKING_TOLERANCE_RATIO: float = 0.70
const OFF_PATH_GRACE: float = 0.12
const RELEASE_WINDOW: float = 0.210
const VISUAL_CLEANUP_DELAY: float = 0.30
const PATH_POINT_INTERVAL: float = 1.0 / 6.0
const SAMPLES_PER_SEGMENT: int = 4
const RELEASE_MARKER_COLOR: Color = Color(1.0, 0.82, 0.28, 1.0)
const RELEASE_MARKER_INNER_COLOR: Color = Color(0.16, 0.08, 0.22, 1.0)

var slide_path: Array[Dictionary] = []
var judged: bool = false
var tracking: bool = false
var active_finger_id: int = -1
var head_error: float = 0.0
var head_judgement: String = ""
var off_path_time: float = 0.0
var ribbon_centers: PackedVector2Array = PackedVector2Array()
var ribbon_half_widths: PackedFloat32Array = PackedFloat32Array()
var tail_scale: float = 1.0
var resolved_result: String = ""
var next_sustain_tick_time: float = INF


func configure_path(
	points: Array[Dictionary],
	interpolation_mode: String,
	requires_release: bool
) -> void:
	slide_path = _limit_path_density(points)
	interpolation = (
		"smooth" if interpolation_mode == "smooth" else "linear"
	)
	release_required = requires_release
	if slide_path.size() >= 2:
		hit_time = float(slide_path[0]["time"])
		note_x = float(slide_path[0]["x"])
		end_time = float(slide_path[-1]["time"])
		end_x = float(slide_path[-1]["x"])


func _ready() -> void:
	if slide_path.size() < 2:
		push_error("SlideNote requires a path containing at least 2 points.")
		queue_free()
		return
	add_to_group("hittable_notes")


func _process(delta: float) -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var song_time: float = float(
		GameManager.song_clock.get_song_time()
	)
	var visual_song_time: float = SettingsManager.get_visual_time(song_time)
	var time_until_hit: float = hit_time - visual_song_time

	if (
		not judged
		and not tracking
		and time_until_hit > NoteMotion.get_approach_time()
	):
		visible = false
		return

	visible = true
	_update_geometry(screen_size, visual_song_time)
	if judged:
		if visual_song_time >= end_time + VISUAL_CLEANUP_DELAY:
			queue_free()
		else:
			queue_redraw()
		return

	if tracking:
		if not InputManager.is_finger_pressed(active_finger_id):
			_resolve("MISS", song_time - end_time)
			return

		var finger_position: Vector2 = InputManager.get_finger_position(
			active_finger_id
		)

		if _is_tracking_position(finger_position, song_time):
			off_path_time = 0.0
		else:
			off_path_time += delta

			if off_path_time > OFF_PATH_GRACE:
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
	if judged or tracking:
		return false

	if not _is_head_position_inside(touch_position):
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
	if judged or tracking:
		return

	var error: float = input_time - hit_time

	if not JudgementSystem.is_inside_hit_window(error):
		return

	tracking = true
	active_finger_id = finger_id
	head_error = error
	head_judgement = JudgementSystem.get_judgement(error)
	next_sustain_tick_time = (
		maxf(hit_time, input_time)
		+ ScoreManager.SUSTAIN_TICK_INTERVAL_SECONDS
	)
	remove_from_group("hittable_notes")
	queue_redraw()


func receive_move(
	_position: Vector2,
	_velocity: Vector2,
	_input_time: float,
	_finger_id: int
) -> void:
	# Tracking is evaluated every frame so a stationary finger can fail too.
	pass


func receive_release(
	touch_position: Vector2,
	input_time: float,
	finger_id: int
) -> void:
	if judged or not is_tracking_finger(finger_id):
		return

	_award_sustain_ticks(minf(input_time, end_time))
	var release_error: float = input_time - end_time
	var timing_is_valid: bool = (
		absf(release_error) <= RELEASE_WINDOW
		if release_required
		else input_time >= end_time - JudgementSystem.BAD_WINDOW
	)
	if (
		timing_is_valid
		and _is_tracking_position(touch_position, end_time)
	):
		if release_required:
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
		else:
			_resolve(head_judgement, head_error)
	else:
		_resolve("MISS", release_error)


func is_tracking_finger(finger_id: int) -> bool:
	return tracking and active_finger_id == finger_id


func _is_head_position_inside(touch_position: Vector2) -> bool:
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)
	var start_position: float = NoteMotion.x_position(
		note_x,
		screen_size
	)
	var half_width: float = note_width * gameplay_width / 2.0

	return abs(touch_position.x - start_position) <= half_width


func _is_tracking_position(
	touch_position: Vector2,
	song_time: float
) -> bool:
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)
	var expected_x: float = NoteMotion.x_position(
		_get_expected_x(song_time),
		screen_size
	)
	var tolerance: float = (
		note_width * gameplay_width * TRACKING_TOLERANCE_RATIO
	)

	return abs(touch_position.x - expected_x) <= tolerance


func _limit_path_density(points: Array[Dictionary]) -> Array[Dictionary]:
	if points.size() <= 2:
		return points.duplicate(true)

	var first: Dictionary = points[0]
	var last: Dictionary = points[-1]
	var output: Array[Dictionary] = [first.duplicate(true)]
	var previous_time: float = float(first["time"])

	for index: int in range(1, points.size() - 1):
		var point: Dictionary = points[index]
		var point_time: float = float(point["time"])
		if point_time - previous_time < PATH_POINT_INTERVAL:
			continue
		output.append(point.duplicate(true))
		previous_time = point_time

	output.append(last.duplicate(true))
	return output


func _get_expected_x(song_time: float) -> float:
	if song_time <= hit_time:
		return note_x
	if song_time >= end_time:
		return end_x

	var segment_index: int = _find_segment(song_time)
	var start: Dictionary = slide_path[segment_index]
	var finish: Dictionary = slide_path[segment_index + 1]
	var start_time: float = float(start["time"])
	var finish_time: float = float(finish["time"])
	var weight: float = inverse_lerp(start_time, finish_time, song_time)

	if interpolation == "smooth":
		return _smooth_segment_x(segment_index, weight)
	return lerpf(float(start["x"]), float(finish["x"]), weight)


func _find_segment(song_time: float) -> int:
	for index: int in range(slide_path.size() - 1):
		if song_time <= float(slide_path[index + 1]["time"]):
			return index
	return slide_path.size() - 2


func _smooth_segment_x(segment_index: int, weight: float) -> float:
	var start: Dictionary = slide_path[segment_index]
	var finish: Dictionary = slide_path[segment_index + 1]
	var previous: Dictionary = slide_path[maxi(0, segment_index - 1)]
	var following: Dictionary = slide_path[
		mini(slide_path.size() - 1, segment_index + 2)
	]
	var start_time: float = float(start["time"])
	var finish_time: float = float(finish["time"])
	var duration: float = finish_time - start_time
	var start_slope: float = _point_slope(previous, finish)
	var finish_slope: float = _point_slope(start, following)
	var weight_squared: float = weight * weight
	var weight_cubed: float = weight_squared * weight
	var start_basis: float = 2.0 * weight_cubed - 3.0 * weight_squared + 1.0
	var start_slope_basis: float = weight_cubed - 2.0 * weight_squared + weight
	var finish_basis: float = -2.0 * weight_cubed + 3.0 * weight_squared
	var finish_slope_basis: float = weight_cubed - weight_squared
	var value: float = (
		start_basis * float(start["x"])
		+ start_slope_basis * duration * start_slope
		+ finish_basis * float(finish["x"])
		+ finish_slope_basis * duration * finish_slope
	)
	return clampf(value, 0.0, 1.0)


func _point_slope(left: Dictionary, right: Dictionary) -> float:
	var time_difference: float = float(right["time"]) - float(left["time"])
	if time_difference <= 0.0:
		return 0.0
	return (float(right["x"]) - float(left["x"])) / time_difference


func _update_geometry(
	screen_size: Vector2,
	song_time: float
) -> void:
	var path_start_time: float = (
		clampf(song_time, hit_time, end_time)
		if tracking or judged
		else hit_time
	)
	var samples: Array[Dictionary] = _make_render_samples(path_start_time)
	ribbon_centers.clear()
	ribbon_half_widths.clear()
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)

	for sample: Dictionary in samples:
		var sample_time: float = float(sample["time"])
		var progress: float = NoteMotion.approach_progress(
			sample_time,
			song_time
		)
		var center: Vector2 = Vector2(
			NoteMotion.x_position_at_progress(
				float(sample["x"]),
				progress,
				screen_size
			),
			NoteMotion.y_at_progress(progress, screen_size)
		)
		var width_scale: float = NoteMotion.perspective_scale(progress)
		ribbon_centers.append(center)
		ribbon_half_widths.append(
			note_width * gameplay_width * width_scale / 2.0
		)

	if ribbon_centers.is_empty():
		return

	position = ribbon_centers[0]
	for index: int in range(ribbon_centers.size()):
		ribbon_centers[index] -= position

	tail_scale = _scale_for_sample(samples[-1], song_time)


func _make_render_samples(start_time: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = [{
		"time": start_time,
		"x": _get_expected_x(start_time),
	}]

	for segment_index: int in range(slide_path.size() - 1):
		var segment_start: float = float(slide_path[segment_index]["time"])
		var segment_end: float = float(slide_path[segment_index + 1]["time"])
		if segment_end <= start_time:
			continue

		for sample_index: int in range(1, SAMPLES_PER_SEGMENT + 1):
			var sample_time: float = lerpf(
				segment_start,
				segment_end,
				float(sample_index) / float(SAMPLES_PER_SEGMENT)
			)
			if sample_time <= start_time:
				continue
			samples.append({
				"time": sample_time,
				"x": _get_expected_x(sample_time),
			})

	return samples


func _scale_for_sample(sample: Dictionary, song_time: float) -> float:
	return NoteMotion.perspective_scale(
		NoteMotion.approach_progress(float(sample["time"]), song_time)
	)


func _award_sustain_ticks(song_time: float) -> void:
	if next_sustain_tick_time == INF:
		return

	var tick_limit: float = minf(song_time, end_time)
	while next_sustain_tick_time <= tick_limit:
		if (
			InputManager.is_finger_pressed(active_finger_id)
			and _is_tracking_position(
				InputManager.get_finger_position(active_finger_id),
				next_sustain_tick_time
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
	tracking = false
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
		else Color(0.35, 1.0, 0.60, 0.80)
		if tracking
		else Color(0.72, 0.35, 1.0, 0.70)
	)
	if ribbon_centers.size() >= 2:
		for index: int in range(ribbon_centers.size() - 1):
			var start: Vector2 = ribbon_centers[index]
			var finish: Vector2 = ribbon_centers[index + 1]
			if (
				start.distance_squared_to(finish) < 0.01
				or absf(start.y - finish.y) < 0.01
			):
				continue
			var start_width: float = ribbon_half_widths[index]
			var finish_width: float = ribbon_half_widths[index + 1]
			draw_colored_polygon(
				PackedVector2Array([
					start - Vector2(start_width, 0.0),
					start + Vector2(start_width, 0.0),
					finish + Vector2(finish_width, 0.0),
					finish - Vector2(finish_width, 0.0),
				]),
				body_color
			)

	if ribbon_centers.is_empty():
		return

	var tail_offset: Vector2 = ribbon_centers[-1]
	if release_required:
		var marker_radius: float = maxf(8.0, 18.0 * tail_scale)
		draw_circle(
			tail_offset,
			marker_radius * 1.45,
			RELEASE_MARKER_COLOR
		)
		draw_circle(
			tail_offset,
			marker_radius * 0.72,
			RELEASE_MARKER_INNER_COLOR
		)
		draw_line(
			tail_offset + Vector2(-marker_radius * 0.42, 0.0),
			tail_offset + Vector2(marker_radius * 0.42, 0.0),
			Color.WHITE,
			maxf(2.0, 5.0 * tail_scale),
			true
		)
