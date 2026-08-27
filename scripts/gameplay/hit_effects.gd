extends Node2D

const EFFECT_DURATION: float = 0.36
const RAY_COUNT: int = 8
const RESULT_COLORS: Dictionary = {
	"PERFECT": Color(0.58, 0.95, 1.0),
	"GREAT": Color(0.48, 1.0, 0.66),
	"GOOD": Color(1.0, 0.88, 0.36),
	"BAD": Color(1.0, 0.48, 0.24),
}

var active_effects: Array[Dictionary] = []


func _ready() -> void:
	NoteManager.hit_feedback_requested.connect(_on_hit_feedback_requested)
	set_process(false)


func _process(delta: float) -> void:
	for index: int in range(active_effects.size() - 1, -1, -1):
		active_effects[index]["age"] = (
			float(active_effects[index]["age"]) + delta
		)

		if float(active_effects[index]["age"]) >= EFFECT_DURATION:
			active_effects.remove_at(index)

	set_process(not active_effects.is_empty())
	queue_redraw()


func _draw() -> void:
	for effect: Dictionary in active_effects:
		var progress: float = clampf(
			float(effect["age"]) / EFFECT_DURATION,
			0.0,
			1.0
		)
		var eased_progress: float = 1.0 - pow(1.0 - progress, 3.0)
		var alpha: float = pow(1.0 - progress, 2.0)
		var color: Color = effect["color"]
		color.a = alpha
		var center: Vector2 = effect["position"]
		var radius: float = lerpf(24.0, 118.0, eased_progress)
		var line_width: float = lerpf(10.0, 2.0, progress)

		draw_arc(
			center,
			radius,
			0.0,
			TAU,
			48,
			color,
			line_width,
			true
		)
		draw_circle(
			center,
			lerpf(22.0, 2.0, progress),
			color
		)

		for ray_index: int in range(RAY_COUNT):
			var angle: float = TAU * float(ray_index) / float(RAY_COUNT)
			var direction: Vector2 = Vector2.from_angle(angle)
			var ray_start: Vector2 = center + direction * radius * 0.72
			var ray_end: Vector2 = center + direction * (
				radius + lerpf(34.0, 8.0, progress)
			)
			draw_line(ray_start, ray_end, color, line_width * 0.65, true)


func _on_hit_feedback_requested(
	position: Vector2,
	result: String
) -> void:
	active_effects.append({
		"position": position,
		"color": RESULT_COLORS.get(result, Color.WHITE),
		"age": 0.0,
	})
	set_process(true)
	queue_redraw()


func get_active_effect_count() -> int:
	return active_effects.size()
