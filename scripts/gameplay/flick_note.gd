extends Node2D

@export var hit_time: float = 2.0
@export var note_x: float = 0.5
@export var note_width: float = 0.20
@export_enum("any", "up", "down", "left", "right")
var flick_direction: String = "up"
@export var minimum_speed: float = 650.0

const NOTE_HEIGHT: float = 42.0
const MINIMUM_DIRECTION_DOT: float = 0.5

var judged: bool = false


func _ready() -> void:
	add_to_group("hittable_notes")


func _process(_delta: float) -> void:
	if judged:
		return

	var screen_size: Vector2 = get_viewport_rect().size
	var song_time: float = float(
		GameManager.song_clock.get_song_time()
	)
	var visual_song_time: float = SettingsManager.get_visual_time(song_time)
	var time_until_hit: float = hit_time - visual_song_time

	if time_until_hit > NoteMotion.get_approach_time():
		visible = false
		return

	visible = true
	_update_position(screen_size, visual_song_time)

	var late_error: float = song_time - hit_time

	if late_error > JudgementSystem.BAD_WINDOW:
		_judge("MISS", late_error)
		return

	queue_redraw()


func can_receive_flick(
	touch_position: Vector2,
	velocity: Vector2,
	input_time: float
) -> bool:
	if judged or not _is_position_inside(touch_position):
		return false

	if not JudgementSystem.is_inside_hit_window(input_time - hit_time):
		return false

	return _matches_direction(velocity)


func get_timing_error(input_time: float) -> float:
	return input_time - hit_time


func receive_flick(
	_touch_position: Vector2,
	_velocity: Vector2,
	input_time: float,
	_finger_id: int
) -> void:
	if judged:
		return

	var error: float = input_time - hit_time
	_judge(JudgementSystem.get_judgement(error), error)


func _matches_direction(velocity: Vector2) -> bool:
	if velocity.length() < minimum_speed:
		return false

	if flick_direction == "any":
		return true

	var expected_direction: Vector2 = _get_direction_vector()
	return velocity.normalized().dot(expected_direction) >= (
		MINIMUM_DIRECTION_DOT
	)


func _get_direction_vector() -> Vector2:
	match flick_direction:
		"down":
			return Vector2.DOWN

		"left":
			return Vector2.LEFT

		"right":
			return Vector2.RIGHT

		_:
			return Vector2.UP


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
	position = NoteMotion.position_for_time(
		note_x,
		hit_time,
		song_time,
		screen_size
	)
	var perspective_scale: float = NoteMotion.scale_for_time(
		hit_time,
		song_time
	)
	scale = Vector2.ONE * perspective_scale


func _judge(result: String, error: float) -> void:
	if judged:
		return

	judged = true
	ScoreManager.register_judgement(result)
	LifeManager.register_judgement(result)
	JudgementSystem.announce_judgement(result, error)
	NoteManager.request_hit_feedback(global_position, result)
	queue_free()

func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)
	var width_pixels: float = note_width * gameplay_width

	var half_width: float = width_pixels / 2.0
	var half_height: float = NOTE_HEIGHT / 2.0

	# ------------------------------------------------------------
	# BASE NOTE GLOW
	# ------------------------------------------------------------

	# Outer soft glow.
	draw_rect(
		Rect2(
			-half_width - 12.0,
			-half_height - 8.0,
			width_pixels + 24.0,
			NOTE_HEIGHT + 16.0
		),
		Color(1.0, 0.55, 0.0, 0.18)
	)

	# Secondary glow.
	draw_rect(
		Rect2(
			-half_width - 6.0,
			-half_height - 4.0,
			width_pixels + 12.0,
			NOTE_HEIGHT + 8.0
		),
		Color(1.0, 0.72, 0.08, 0.35)
	)

	# Orange/gold outer body.
	draw_rect(
		Rect2(
			-half_width,
			-half_height,
			width_pixels,
			NOTE_HEIGHT
		),
		Color(1.0, 0.58, 0.05)
	)

	# Bright inner body.
	var border: float = 5.0

	draw_rect(
		Rect2(
			-half_width + border,
			-half_height + border,
			width_pixels - border * 2.0,
			NOTE_HEIGHT - border * 2.0
		),
		Color(1.0, 0.94, 0.66)
	)

	# White-yellow center highlight.
	draw_rect(
		Rect2(
			-half_width + 14.0,
			-half_height + 8.0,
			width_pixels - 28.0,
			NOTE_HEIGHT * 0.42
		),
		Color(1.0, 1.0, 0.88, 0.75)
	)

	# ------------------------------------------------------------
	# FLOATING FLICK ARROW
	# ------------------------------------------------------------

	var direction: Vector2 = _get_direction_vector()
	var perpendicular: Vector2 = Vector2(
		-direction.y,
		direction.x
	)

	var arrow_width: float = min(width_pixels * 0.42, 78.0)
	var arrow_height: float = 38.0

	# Push arrow away from the note in its flick direction.
	var arrow_center: Vector2 = direction * 58.0

	# Chevron construction:
	#
	#        ^
	#       / \
	#      /   \
	#     /     \
	#
	# instead of a solid triangle.

	var tip: Vector2 = arrow_center + direction * arrow_height

	var outer_left: Vector2 = (
		arrow_center
		- direction * arrow_height * 0.15
		+ perpendicular * arrow_width
	)

	var outer_right: Vector2 = (
		arrow_center
		- direction * arrow_height * 0.15
		- perpendicular * arrow_width
	)

	var inner_left: Vector2 = (
		arrow_center
		+ direction * arrow_height * 0.22
		+ perpendicular * arrow_width * 0.47
	)

	var inner_right: Vector2 = (
		arrow_center
		+ direction * arrow_height * 0.22
		- perpendicular * arrow_width * 0.47
	)

	# ------------------------------------------------------------
	# ARROW GLOW
	# ------------------------------------------------------------

	var glow_points := PackedVector2Array([
		tip + direction * 8.0,
		outer_left + perpendicular * 7.0,
		inner_left,
		arrow_center + direction * 4.0,
		inner_right,
		outer_right - perpendicular * 7.0
	])

	draw_colored_polygon(
		glow_points,
		Color(1.0, 0.65, 0.0, 0.22)
	)

	# ------------------------------------------------------------
	# OUTER GOLD CHEVRON
	# ------------------------------------------------------------

	var outer_arrow := PackedVector2Array([
		tip,
		outer_left,
		inner_left,
		arrow_center + direction * 10.0,
		inner_right,
		outer_right
	])

	draw_colored_polygon(
		outer_arrow,
		Color(1.0, 0.55, 0.0)
	)

	# ------------------------------------------------------------
	# INNER BRIGHT CHEVRON
	# ------------------------------------------------------------

	var inset_width: float = arrow_width * 0.72
	var inset_height: float = arrow_height * 0.72

	var inner_tip: Vector2 = (
		arrow_center
		+ direction * inset_height
	)

	var bright_outer_left: Vector2 = (
		arrow_center
		- direction * inset_height * 0.08
		+ perpendicular * inset_width
	)

	var bright_outer_right: Vector2 = (
		arrow_center
		- direction * inset_height * 0.08
		- perpendicular * inset_width
	)

	var bright_inner_left: Vector2 = (
		arrow_center
		+ direction * inset_height * 0.26
		+ perpendicular * inset_width * 0.46
	)

	var bright_inner_right: Vector2 = (
		arrow_center
		+ direction * inset_height * 0.26
		- perpendicular * inset_width * 0.46
	)

	var bright_arrow := PackedVector2Array([
		inner_tip,
		bright_outer_left,
		bright_inner_left,
		arrow_center + direction * 12.0,
		bright_inner_right,
		bright_outer_right
	])

	draw_colored_polygon(
		bright_arrow,
		Color(1.0, 0.91, 0.25)
	)

	# ------------------------------------------------------------
	# WHITE CENTER HIGHLIGHT
	# ------------------------------------------------------------

	var highlight_tip: Vector2 = (
		arrow_center
		+ direction * arrow_height * 0.55
	)

	var highlight_left: Vector2 = (
		arrow_center
		+ direction * arrow_height * 0.18
		+ perpendicular * arrow_width * 0.37
	)

	var highlight_right: Vector2 = (
		arrow_center
		+ direction * arrow_height * 0.18
		- perpendicular * arrow_width * 0.37
	)

	var highlight := PackedVector2Array([
		highlight_tip,
		highlight_left,
		arrow_center + direction * arrow_height * 0.32,
		highlight_right
	])

	draw_colored_polygon(
		highlight,
		Color(1.0, 1.0, 0.82, 0.85)
	)
