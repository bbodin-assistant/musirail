class_name NoteMotion
extends RefCounted

# Shared note approach settings used by every note type.
const MIN_APPROACH_TIME: float = 0.02
const MAX_APPROACH_TIME: float = 3.00
const DEFAULT_APPROACH_TIME: float = 1.10
const NOTE_LANE_POSITIONS: Array[float] = [0.15, 0.30, 0.50, 0.70, 0.85]
const VANISH_Y_RATIO: float = -0.12
const SPAWN_Y_RATIO: float = 0.0
const HIT_Y_RATIO: float = 0.72
const GAME_WIDTH_RATIO: float = 0.56
const PERSPECTIVE_POWER: float = 2.35
const RAIL_BOTTOM_Y_RATIO: float = 1.04
const VISIBLE_START_WIDTH_SCALE: float = (
	(SPAWN_Y_RATIO - VANISH_Y_RATIO)
	/ (HIT_Y_RATIO - VANISH_Y_RATIO)
)
const RAIL_BOTTOM_WIDTH_SCALE: float = (
	(RAIL_BOTTOM_Y_RATIO - VANISH_Y_RATIO)
	/ (HIT_Y_RATIO - VANISH_Y_RATIO)
)

static var approach_time: float = DEFAULT_APPROACH_TIME


static func set_approach_time(value: float) -> void:
	approach_time = clampf(
		value,
		MIN_APPROACH_TIME,
		MAX_APPROACH_TIME
	)


static func get_approach_time() -> float:
	return approach_time


static func gameplay_width(screen_size: Vector2) -> float:
	return screen_size.x * GAME_WIDTH_RATIO


static func x_position(
	normalized_x: float,
	screen_size: Vector2
) -> float:
	return x_position_at_progress(normalized_x, 1.0, screen_size)


static func x_position_at_progress(
	normalized_x: float,
	linear_progress: float,
	screen_size: Vector2
) -> float:
	var width: float = rail_width_at_progress(
		linear_progress,
		screen_size
	)

	return screen_size.x / 2.0 + (normalized_x - 0.5) * width


static func position_for_time(
	normalized_x: float,
	event_time: float,
	song_time: float,
	screen_size: Vector2
) -> Vector2:
	var progress: float = approach_progress(event_time, song_time)

	return Vector2(
		x_position_at_progress(normalized_x, progress, screen_size),
		y_at_progress(progress, screen_size)
	)


static func approach_progress(
	event_time: float,
	song_time: float
) -> float:
	return 1.0 - clampf(
		(event_time - song_time) / approach_time,
		0.0,
		1.0
	)


static func perspective_progress(linear_progress: float) -> float:
	return pow(
		clampf(linear_progress, 0.0, 1.0),
		PERSPECTIVE_POWER
	)


static func perspective_scale(linear_progress: float) -> float:
	return lerpf(
		VISIBLE_START_WIDTH_SCALE,
		1.0,
		perspective_progress(linear_progress)
	)


static func scale_for_time(event_time: float, song_time: float) -> float:
	return perspective_scale(approach_progress(event_time, song_time))


static func rail_width_at_progress(
	linear_progress: float,
	screen_size: Vector2
) -> float:
	return gameplay_width(screen_size) * perspective_scale(linear_progress)


static func rail_bottom_width(screen_size: Vector2) -> float:
	return gameplay_width(screen_size) * RAIL_BOTTOM_WIDTH_SCALE


static func rail_bottom_x(
	normalized_x: float,
	screen_size: Vector2
) -> float:
	return (
		screen_size.x / 2.0
		+ (normalized_x - 0.5) * rail_bottom_width(screen_size)
	)


static func rail_x_at_y(
	normalized_x: float,
	y: float,
	screen_size: Vector2
) -> float:
	var width_scale: float = (
		(y - vanish_y(screen_size))
		/ (hit_y(screen_size) - vanish_y(screen_size))
	)
	var width: float = gameplay_width(screen_size) * width_scale
	return screen_size.x / 2.0 + (normalized_x - 0.5) * width


static func spawn_y(screen_size: Vector2) -> float:
	return screen_size.y * SPAWN_Y_RATIO


static func vanish_y(screen_size: Vector2) -> float:
	return screen_size.y * VANISH_Y_RATIO


static func hit_y(screen_size: Vector2) -> float:
	return screen_size.y * HIT_Y_RATIO


static func rail_bottom_y(screen_size: Vector2) -> float:
	return screen_size.y * RAIL_BOTTOM_Y_RATIO


static func y_at_progress(
	linear_progress: float,
	screen_size: Vector2
) -> float:
	return lerpf(
		spawn_y(screen_size),
		hit_y(screen_size),
		perspective_progress(linear_progress)
	)
