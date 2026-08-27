class_name RecordedTrackGesture
extends RefCounted

const HOLD_MIN_DURATION: float = 0.32
const FLICK_MAX_DURATION: float = 0.30
const FLICK_MIN_DISTANCE_PIXELS: float = 54.0
const FLICK_MIN_SPEED_PIXELS: float = 620.0
const SLIDE_MIN_DISTANCE: float = 0.065
const PATH_SAMPLE_INTERVAL: float = 0.045
const PATH_SAMPLE_DISTANCE: float = 0.012
const PATH_SIMPLIFICATION_ERROR: float = 0.009
const OUTPUT_PATH_SAMPLE_INTERVAL: float = 1.0 / 6.0

var finger_id: int = 0
var start_time: float = 0.0
var start_x: float = 0.5
var start_position: Vector2 = Vector2.ZERO
var last_time: float = 0.0
var last_x: float = 0.5
var last_position: Vector2 = Vector2.ZERO
var max_screen_speed: float = 0.0
var max_screen_displacement: float = 0.0
var max_x_displacement: float = 0.0
var path: Array[Dictionary] = []


func configure(
	input_finger_id: int,
	input_time: float,
	normalized_x: float,
	screen_position: Vector2
) -> void:
	finger_id = input_finger_id
	start_time = input_time
	start_x = normalized_x
	start_position = screen_position
	last_time = input_time
	last_x = normalized_x
	last_position = screen_position
	path = [_path_point(input_time, normalized_x)]


func add_sample(
	input_time: float,
	normalized_x: float,
	screen_position: Vector2,
	velocity: Vector2 = Vector2.ZERO,
	force: bool = false
) -> void:
	var safe_time: float = maxf(input_time, last_time)
	var safe_x: float = clampf(normalized_x, 0.0, 1.0)
	var elapsed: float = maxf(safe_time - last_time, 0.000001)
	var movement: Vector2 = screen_position - last_position
	var measured_speed: float = maxf(
		velocity.length(),
		movement.length() / elapsed
	)
	max_screen_speed = maxf(max_screen_speed, measured_speed)
	max_screen_displacement = maxf(
		max_screen_displacement,
		screen_position.distance_to(start_position)
	)
	max_x_displacement = maxf(
		max_x_displacement,
		absf(safe_x - start_x)
	)

	var last_path_point: Dictionary = path[-1]
	if (
		force
		or safe_time - float(last_path_point["time"]) >= PATH_SAMPLE_INTERVAL
		or absf(safe_x - float(last_path_point["x"])) >= PATH_SAMPLE_DISTANCE
	):
		_append_path_point(safe_time, safe_x, force)

	last_time = safe_time
	last_x = safe_x
	last_position = screen_position


func build_note(
	end_time: float,
	end_x: float,
	end_position: Vector2,
	width: float
) -> Dictionary:
	add_sample(end_time, end_x, end_position, Vector2.ZERO, true)
	var duration: float = maxf(last_time - start_time, 0.0)
	var displacement: Vector2 = last_position - start_position
	var average_speed: float = (
		displacement.length() / maxf(duration, 0.000001)
	)

	if (
		duration <= FLICK_MAX_DURATION
		and displacement.length() >= FLICK_MIN_DISTANCE_PIXELS
		and maxf(max_screen_speed, average_speed) >= FLICK_MIN_SPEED_PIXELS
	):
		return {
			"time": _clean_time(start_time),
			"x": _clean_x(start_x),
			"width": width,
			"type": "flick",
			"direction": _flick_direction(displacement),
			"min_speed": FLICK_MIN_SPEED_PIXELS,
		}

	if max_x_displacement >= SLIDE_MIN_DISTANCE:
		var sampled_path: Array[Dictionary] = _resample_path(path)
		var slide_path: Array[Dictionary] = _simplify_path(sampled_path)
		if slide_path.size() >= 2:
			return {
				"type": "slide",
				"path": slide_path,
				"width": width,
				"interpolation": "smooth",
				"release_required": true,
			}

	if duration >= HOLD_MIN_DURATION:
		return {
			"time": _clean_time(start_time),
			"x": _clean_x(start_x),
			"end_time": _clean_time(last_time),
			"width": width,
			"type": "hold",
			"release_required": true,
		}

	return {
		"time": _clean_time(start_time),
		"x": _clean_x(start_x),
		"width": width,
		"type": "tap",
	}


func _append_path_point(
	input_time: float,
	normalized_x: float,
	force: bool = false
) -> void:
	var clean_time: float = _clean_time(input_time)
	var clean_x: float = _clean_x(normalized_x)
	if not path.is_empty():
		var previous_time: float = float(path[-1]["time"])
		if clean_time <= previous_time:
			clean_time = previous_time + 0.000001
		if (
			not force
			and is_equal_approx(clean_x, float(path[-1]["x"]))
			and clean_time - previous_time < PATH_SAMPLE_INTERVAL
		):
			return
	path.append(_path_point(clean_time, clean_x))


func _simplify_path(points: Array[Dictionary]) -> Array[Dictionary]:
	if points.size() <= 2:
		return points.duplicate(true)
	var simplified: Array[Dictionary] = [points[0].duplicate(true)]
	_append_simplified_segment(points, 0, points.size() - 1, simplified)
	return simplified


func _resample_path(points: Array[Dictionary]) -> Array[Dictionary]:
	if points.size() <= 2:
		return points.duplicate(true)

	var first: Dictionary = points[0]
	var last: Dictionary = points[-1]
	var first_time: float = float(first["time"])
	var last_time_value: float = float(last["time"])
	var output: Array[Dictionary] = [first.duplicate(true)]
	var segment_index: int = 0
	var sample_time: float = first_time + OUTPUT_PATH_SAMPLE_INTERVAL

	while sample_time < last_time_value:
		while (
			segment_index < points.size() - 2
			and float(points[segment_index + 1]["time"]) < sample_time
		):
			segment_index += 1

		var segment_start: Dictionary = points[segment_index]
		var segment_end: Dictionary = points[segment_index + 1]
		var segment_start_time: float = float(segment_start["time"])
		var segment_end_time: float = float(segment_end["time"])
		var weight: float = inverse_lerp(
			segment_start_time,
			segment_end_time,
			sample_time
		)
		output.append(_path_point(
			sample_time,
			lerpf(
				float(segment_start["x"]),
				float(segment_end["x"]),
				weight
			)
		))
		sample_time += OUTPUT_PATH_SAMPLE_INTERVAL

	output.append(last.duplicate(true))
	return output


func _append_simplified_segment(
	points: Array[Dictionary],
	start_index: int,
	end_index: int,
	output: Array[Dictionary]
) -> void:
	if end_index <= start_index + 1:
		output.append(points[end_index].duplicate(true))
		return

	var start: Dictionary = points[start_index]
	var finish: Dictionary = points[end_index]
	var time_span: float = maxf(
		float(finish["time"]) - float(start["time"]),
		0.000001
	)
	var largest_error: float = 0.0
	var split_index: int = -1
	for index: int in range(start_index + 1, end_index):
		var point: Dictionary = points[index]
		var progress: float = (
			(float(point["time"]) - float(start["time"])) / time_span
		)
		var expected_x: float = lerpf(
			float(start["x"]),
			float(finish["x"]),
			progress
		)
		var error: float = absf(float(point["x"]) - expected_x)
		if error > largest_error:
			largest_error = error
			split_index = index

	if largest_error > PATH_SIMPLIFICATION_ERROR and split_index >= 0:
		_append_simplified_segment(
			points,
			start_index,
			split_index,
			output
		)
		_append_simplified_segment(
			points,
			split_index,
			end_index,
			output
		)
	else:
		output.append(finish.duplicate(true))


func _flick_direction(displacement: Vector2) -> String:
	if absf(displacement.x) > absf(displacement.y):
		return "right" if displacement.x > 0.0 else "left"
	return "down" if displacement.y > 0.0 else "up"


func _path_point(input_time: float, normalized_x: float) -> Dictionary:
	return {
		"time": _clean_time(input_time),
		"x": _clean_x(normalized_x),
	}


func _clean_time(value: float) -> float:
	return snappedf(maxf(value, 0.0), 0.000001)


func _clean_x(value: float) -> float:
	return snappedf(clampf(value, 0.0, 1.0), 0.001)
