extends Node2D

const RAIL_COLOR: Color = Color(0.025, 0.09, 0.16, 0.84)
const RAIL_INNER_COLOR: Color = Color(0.04, 0.18, 0.28, 0.24)
const EDGE_COLOR: Color = Color(0.25, 0.85, 1.0, 0.92)
const LANE_COLOR: Color = Color(0.30, 0.72, 0.92, 0.34)
const DEPTH_LINE_COLOR: Color = Color(0.42, 0.82, 1.0, 0.20)


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var top_y: float = NoteMotion.spawn_y(screen_size)
	var hit_y: float = NoteMotion.hit_y(screen_size)
	var bottom_y: float = NoteMotion.rail_bottom_y(screen_size)
	var top_left: Vector2 = Vector2(
		NoteMotion.x_position_at_progress(0.0, 0.0, screen_size),
		top_y
	)
	var top_right: Vector2 = Vector2(
		NoteMotion.x_position_at_progress(1.0, 0.0, screen_size),
		top_y
	)
	var bottom_left: Vector2 = Vector2(
		NoteMotion.rail_bottom_x(0.0, screen_size),
		bottom_y
	)
	var bottom_right: Vector2 = Vector2(
		NoteMotion.rail_bottom_x(1.0, screen_size),
		bottom_y
	)

	draw_colored_polygon(
		PackedVector2Array([
			top_left,
			top_right,
			bottom_right,
			bottom_left
		]),
		RAIL_COLOR
	)

	var hit_left: Vector2 = Vector2(
		NoteMotion.x_position(0.0, screen_size),
		hit_y
	)
	var hit_right: Vector2 = Vector2(
		NoteMotion.x_position(1.0, screen_size),
		hit_y
	)
	draw_colored_polygon(
		PackedVector2Array([
			top_left,
			top_right,
			hit_right,
			hit_left
		]),
		RAIL_INNER_COLOR
	)

	_draw_guide_line(0.0, EDGE_COLOR, 6.0, top_y, bottom_y, screen_size)
	_draw_guide_line(1.0, EDGE_COLOR, 6.0, top_y, bottom_y, screen_size)

	for normalized_x: float in NoteMotion.NOTE_LANE_POSITIONS:
		_draw_guide_line(
			normalized_x,
			LANE_COLOR,
			2.0,
			top_y,
			bottom_y,
			screen_size
		)

	for depth_index: int in range(1, 8):
		var progress: float = float(depth_index) / 8.0
		var y: float = NoteMotion.y_at_progress(progress, screen_size)
		var left: Vector2 = Vector2(
			NoteMotion.x_position_at_progress(0.0, progress, screen_size),
			y
		)
		var right: Vector2 = Vector2(
			NoteMotion.x_position_at_progress(1.0, progress, screen_size),
			y
		)

		draw_line(left, right, DEPTH_LINE_COLOR, 2.0, true)


func _draw_guide_line(
	normalized_x: float,
	color: Color,
	width: float,
	top_y: float,
	bottom_y: float,
	screen_size: Vector2
) -> void:
	var line_top: Vector2 = Vector2(
		NoteMotion.x_position_at_progress(
			normalized_x,
			0.0,
			screen_size
		),
		top_y
	)
	var line_bottom: Vector2 = Vector2(
		NoteMotion.rail_bottom_x(normalized_x, screen_size),
		bottom_y
	)
	draw_line(line_top, line_bottom, color, width, true)
