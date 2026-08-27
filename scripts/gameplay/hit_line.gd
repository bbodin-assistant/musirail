extends Node2D

const ZONE_COLOR: Color = Color(0.20, 0.80, 1.0, 0.10)
const GLOW_COLOR: Color = Color(0.20, 0.80, 1.0, 0.24)
const LINE_COLOR: Color = Color(0.86, 0.97, 1.0, 1.0)
const ZONE_HALF_HEIGHT_RATIO: float = 0.026
const MINIMUM_HALF_HEIGHT: float = 22.0
const MAXIMUM_HALF_HEIGHT: float = 40.0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var hit_y: float = NoteMotion.hit_y(screen_size)
	var half_height: float = clampf(
		screen_size.y * ZONE_HALF_HEIGHT_RATIO,
		MINIMUM_HALF_HEIGHT,
		MAXIMUM_HALF_HEIGHT
	)
	var upper_y: float = hit_y - half_height
	var lower_y: float = hit_y + half_height
	var upper_left: Vector2 = Vector2(
		NoteMotion.rail_x_at_y(0.0, upper_y, screen_size),
		upper_y
	)
	var upper_right: Vector2 = Vector2(
		NoteMotion.rail_x_at_y(1.0, upper_y, screen_size),
		upper_y
	)
	var lower_left: Vector2 = Vector2(
		NoteMotion.rail_x_at_y(0.0, lower_y, screen_size),
		lower_y
	)
	var lower_right: Vector2 = Vector2(
		NoteMotion.rail_x_at_y(1.0, lower_y, screen_size),
		lower_y
	)

	draw_colored_polygon(
		PackedVector2Array([
			upper_left,
			upper_right,
			lower_right,
			lower_left,
		]),
		ZONE_COLOR
	)
	draw_line(upper_left, upper_right, GLOW_COLOR, 20.0, true)
	draw_line(lower_left, lower_right, GLOW_COLOR, 20.0, true)
	draw_line(upper_left, upper_right, LINE_COLOR, 6.0, true)
	draw_line(lower_left, lower_right, LINE_COLOR, 6.0, true)
