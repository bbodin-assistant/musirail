class_name TimingDistribution
extends Control

const BACKGROUND_COLOR: Color = Color(0.025, 0.07, 0.12, 0.96)
const AXIS_COLOR: Color = Color(0.42, 0.72, 0.86, 0.75)
const USED_COLOR: Color = Color(0.30, 0.90, 1.0, 1.0)
const OUTLIER_COLOR: Color = Color(1.0, 0.48, 0.22, 1.0)
const MEDIAN_COLOR: Color = Color(1.0, 0.84, 0.35, 1.0)
const MARGIN_X: float = 72.0
const AXIS_Y_RATIO: float = 0.68

var samples: Array[float] = []
var used_mask: Array[bool] = []
var median: float = 0.0
var display_limit: float = 0.5


func set_distribution(
	values: Array[float],
	value_used_mask: Array[bool],
	median_value: float,
	limit: float
) -> void:
	samples = values.duplicate()
	used_mask = value_used_mask.duplicate()
	median = median_value
	display_limit = maxf(0.001, limit)
	queue_redraw()


func _draw() -> void:
	var drawing_size: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, drawing_size), BACKGROUND_COLOR)
	var axis_y: float = drawing_size.y * AXIS_Y_RATIO
	var left: float = MARGIN_X
	var right: float = drawing_size.x - MARGIN_X
	draw_line(Vector2(left, axis_y), Vector2(right, axis_y), AXIS_COLOR, 3.0)

	var font: Font = ThemeDB.fallback_font
	for tick_ms: int in range(-500, 501, 100):
		var tick_seconds: float = tick_ms / 1000.0
		if absf(tick_seconds) > display_limit + 0.001:
			continue
		var tick_x: float = _time_to_x(tick_seconds, left, right)
		draw_line(
			Vector2(tick_x, axis_y - 8.0),
			Vector2(tick_x, axis_y + 8.0),
			AXIS_COLOR,
			2.0
		)
		var label: String = "%+d" % tick_ms
		var label_size: Vector2 = font.get_string_size(
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			18
		)
		draw_string(
			font,
			Vector2(tick_x - label_size.x / 2.0, axis_y + 34.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			18,
			AXIS_COLOR
		)

	var median_x: float = _time_to_x(median, left, right)
	draw_line(
		Vector2(median_x, 12.0),
		Vector2(median_x, axis_y + 10.0),
		MEDIAN_COLOR,
		5.0
	)

	for index: int in range(samples.size()):
		var sample_x: float = _time_to_x(samples[index], left, right)
		var sample_y: float = 35.0 + float(index % 4) * 24.0
		var is_used: bool = (
			bool(used_mask[index]) if index < used_mask.size() else true
		)
		var color: Color = USED_COLOR if is_used else OUTLIER_COLOR
		draw_circle(Vector2(sample_x, sample_y), 9.0, color)
		if not is_used:
			draw_line(
				Vector2(sample_x - 6.0, sample_y - 6.0),
				Vector2(sample_x + 6.0, sample_y + 6.0),
				Color.WHITE,
				2.0
			)


func _time_to_x(value: float, left: float, right: float) -> float:
	var weight: float = inverse_lerp(-display_limit, display_limit, value)
	return lerpf(left, right, clampf(weight, 0.0, 1.0))
