extends Node2D

@export var hit_time: float = 2.0
@export var note_x: float = 0.25
@export var note_width: float = 0.20

const TAP_HIT_WINDOW: float = 0.190

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

	# Ne pas afficher les notes trop longtemps à l'avance.
	if time_until_hit > NoteMotion.get_approach_time():
		visible = false
		return

	visible = true

	position = NoteMotion.position_for_time(
		note_x,
		hit_time,
		visual_song_time,
		screen_size
	)
	var perspective_scale: float = NoteMotion.scale_for_time(
		hit_time,
		visual_song_time
	)
	scale = Vector2.ONE * perspective_scale

	var late_error: float = song_time - hit_time

	if late_error > TAP_HIT_WINDOW:
		judge("MISS", late_error)

	queue_redraw()


func can_receive_press(
	touch_position: Vector2,
	input_time: float
) -> bool:
	if judged:
		return false

	var screen_size: Vector2 = get_viewport_rect().size

	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)

	var note_center_x: float = (
		NoteMotion.x_position(note_x, screen_size)
	)

	var note_width_pixels: float = (
		note_width * gameplay_width
	)

	var note_left: float = (
		note_center_x - note_width_pixels / 2.0
	)

	var note_right: float = (
		note_center_x + note_width_pixels / 2.0
	)

	if touch_position.x < note_left:
		return false

	if touch_position.x > note_right:
		return false

	var error: float = input_time - hit_time

	return JudgementSystem.is_inside_hit_window(error, TAP_HIT_WINDOW)


func get_timing_error(input_time: float) -> float:
	return input_time - hit_time


func receive_press(
	_touch_position: Vector2,
	input_time: float,
	_finger_id: int
) -> void:
	if judged:
		return

	var error: float = input_time - hit_time

	if not JudgementSystem.is_inside_hit_window(error, TAP_HIT_WINDOW):
		return

	var result: String = (
		JudgementSystem.get_judgement(error, TAP_HIT_WINDOW)
	)

	judge(result, error)


func judge(result: String, error: float) -> void:
	if judged:
		return

	judged = true

	ScoreManager.register_judgement(result)
	LifeManager.register_judgement(result)
	JudgementSystem.announce_judgement(
		result,
		error
	)
	NoteManager.request_hit_feedback(global_position, result)

	queue_free()


func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var gameplay_width: float = NoteMotion.gameplay_width(screen_size)

	var width_pixels: float = (
		note_width * gameplay_width
	)

	draw_rect(
		Rect2(
			-width_pixels / 2.0,
			-18.0,
			width_pixels,
			36.0
		),
		Color.WHITE
	)
