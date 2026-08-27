extends Node

signal tap_pressed(position: Vector2, input_time: float)

signal finger_pressed(
	finger_id: int,
	position: Vector2,
	input_time: float
)

signal finger_released(
	finger_id: int,
	position: Vector2,
	input_time: float
)

signal finger_moved(
	finger_id: int,
	position: Vector2,
	velocity: Vector2,
	input_time: float
)


var fingers: Dictionary = {}
var gameplay_input_enabled: bool = true


func _ready() -> void:
	# Continue tracking releases from pause-menu touches while gameplay is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_gameplay_input_enabled(enabled: bool) -> void:
	gameplay_input_enabled = enabled


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)

	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var finger_id: int = event.index

	if gameplay_input_enabled:
		print(
			"Finger ",
			finger_id,
			" | pressed = ",
			event.pressed,
			" | position = ",
			event.position
		)

	if event.pressed:
		fingers[finger_id] = {
			"finger_id": finger_id,
			"position": event.position,
			"pressed": true,
			"velocity": Vector2.ZERO
		}

		if not gameplay_input_enabled:
			return

		var input_time: float = SettingsManager.correct_input_time(
			float(GameManager.song_clock.get_song_time())
		)

		finger_pressed.emit(
			finger_id,
			event.position,
			input_time
		)

		# Conservé pour nos Tap existants.
		tap_pressed.emit(
			event.position,
			input_time
		)

	else:
		if gameplay_input_enabled:
			var input_time: float = SettingsManager.correct_input_time(
				float(GameManager.song_clock.get_song_time())
			)

			finger_released.emit(
				finger_id,
				event.position,
				input_time
			)

		fingers.erase(finger_id)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	var finger_id: int = event.index

	if gameplay_input_enabled:
		print(
			"Finger ",
			finger_id,
			" | position = ",
			event.position,
			" | velocity = ",
			event.screen_velocity
		)

	if not fingers.has(finger_id):
		fingers[finger_id] = {
			"finger_id": finger_id,
			"position": event.position,
			"pressed": true,
			"velocity": event.screen_velocity
		}

	else:
		var finger: Dictionary = fingers[finger_id]

		finger["position"] = event.position
		finger["pressed"] = true
		finger["velocity"] = event.screen_velocity

		fingers[finger_id] = finger

	if not gameplay_input_enabled:
		return

	var input_time: float = SettingsManager.correct_input_time(
		float(GameManager.song_clock.get_song_time())
	)

	finger_moved.emit(
		finger_id,
		event.position,
		event.screen_velocity,
		input_time
	)


func is_finger_pressed(finger_id: int) -> bool:
	return fingers.has(finger_id)


func get_finger_position(finger_id: int) -> Vector2:
	if not fingers.has(finger_id):
		return Vector2.ZERO

	return fingers[finger_id]["position"]


func get_finger_velocity(finger_id: int) -> Vector2:
	if not fingers.has(finger_id):
		return Vector2.ZERO

	return fingers[finger_id]["velocity"]


func get_pressed_fingers() -> Dictionary:
	return fingers
