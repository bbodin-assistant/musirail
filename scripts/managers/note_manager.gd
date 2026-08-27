extends Node

signal hit_feedback_requested(position: Vector2, result: String)

var active_gestures: Dictionary = {}


func _ready() -> void:
	InputManager.finger_pressed.connect(_on_finger_pressed)
	InputManager.finger_released.connect(_on_finger_released)
	InputManager.finger_moved.connect(_on_finger_moved)


func _process(_delta: float) -> void:
	for finger_id: Variant in active_gestures.keys():
		var note: Variant = active_gestures[finger_id]

		if not is_instance_valid(note):
			active_gestures.erase(finger_id)


func request_hit_feedback(position: Vector2, result: String) -> void:
	if result == "MISS":
		return

	hit_feedback_requested.emit(position, result)

	var duration_ms: int = 16
	var amplitude: float = 0.18

	match result:
		"GREAT":
			duration_ms = 20
			amplitude = 0.24
		"GOOD":
			duration_ms = 28
			amplitude = 0.32
		"BAD":
			duration_ms = 38
			amplitude = 0.42

	Input.vibrate_handheld(duration_ms, amplitude)


func release_active_gesture(finger_id: int, note: Node) -> void:
	if active_gestures.get(finger_id) == note:
		active_gestures.erase(finger_id)


func _on_finger_pressed(
	finger_id: int,
	position: Vector2,
	input_time: float
) -> void:
	if active_gestures.has(finger_id):
		return

	var notes: Array = get_tree().get_nodes_in_group("hittable_notes")

	var best_note: Node = null
	var best_error: float = INF

	for note: Node in notes:
		if not is_instance_valid(note):
			continue

		if not note.has_method("can_receive_press"):
			continue

		var can_receive: bool = bool(
			note.call(
				"can_receive_press",
				position,
				input_time
			)
		)

		if not can_receive:
			continue

		var timing_error: float = abs(
			float(
				note.call(
					"get_timing_error",
					input_time
				)
			)
		)

		if timing_error < best_error:
			best_error = timing_error
			best_note = note

	if best_note != null:
		best_note.call(
			"receive_press",
			position,
			input_time,
			finger_id
		)

		if (
			best_note.has_method("is_tracking_finger")
			and bool(
				best_note.call(
					"is_tracking_finger",
					finger_id
				)
			)
		):
			active_gestures[finger_id] = best_note


func _on_finger_moved(
	finger_id: int,
	position: Vector2,
	velocity: Vector2,
	input_time: float
) -> void:
	if active_gestures.has(finger_id):
		var active_note: Variant = active_gestures[finger_id]

		if (
			is_instance_valid(active_note)
			and active_note.has_method("receive_move")
		):
			active_note.call(
				"receive_move",
				position,
				velocity,
				input_time,
				finger_id
			)

		return

	var notes: Array = get_tree().get_nodes_in_group("hittable_notes")
	var best_note: Node = null
	var best_error: float = INF

	for note: Node in notes:
		if not is_instance_valid(note):
			continue

		if not note.has_method("can_receive_flick"):
			continue

		if not bool(
			note.call(
				"can_receive_flick",
				position,
				velocity,
				input_time
			)
		):
			continue

		var timing_error: float = abs(
			float(note.call("get_timing_error", input_time))
		)

		if timing_error < best_error:
			best_error = timing_error
			best_note = note

	if best_note != null:
		best_note.call(
			"receive_flick",
			position,
			velocity,
			input_time,
			finger_id
		)


func _on_finger_released(
	finger_id: int,
	position: Vector2,
	input_time: float
) -> void:
	if not active_gestures.has(finger_id):
		return

	var note: Variant = active_gestures[finger_id]
	active_gestures.erase(finger_id)

	if not is_instance_valid(note):
		return

	if note.has_method("receive_release"):
		note.call(
			"receive_release",
			position,
			input_time,
			finger_id
		)
