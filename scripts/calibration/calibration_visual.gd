class_name CalibrationVisual
extends Node2D

const NOTE_COLOR: Color = Color(0.35, 0.92, 1.0, 1.0)
const NOTE_GLOW_COLOR: Color = Color(0.28, 0.85, 1.0, 0.30)
const FLASH_COLOR: Color = Color(0.72, 0.96, 1.0, 0.22)
const CIRCLE_FILL_COLOR: Color = Color(0.025, 0.18, 0.28, 0.94)
const CIRCLE_EDGE_COLOR: Color = Color(0.25, 0.85, 1.0, 1.0)
const CIRCLE_GLOW_COLOR: Color = Color(0.30, 0.72, 0.92, 0.24)
const TAP_ACKNOWLEDGE_COLOR: Color = Color(0.55, 1.0, 0.72, 1.0)
const NOTE_WIDTH_RATIO: float = 0.14
const NOTE_HEIGHT: float = 34.0
const CIRCLE_RADIUS: float = 150.0
const FLASH_DURATION_SECONDS: float = 0.14
const PULSE_DURATION_SECONDS: float = 0.26
const TAP_ACKNOWLEDGE_DURATION_SECONDS: float = 0.16

var calibration_active: bool = false
var visual_mode: bool = false
var clock_time: float = 0.0
var next_target_time: float = 0.0
var flash_remaining: float = 0.0
var pulse_remaining: float = 0.0
var acknowledge_remaining: float = 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	if (
		flash_remaining > 0.0
		or pulse_remaining > 0.0
		or acknowledge_remaining > 0.0
	):
		flash_remaining = maxf(0.0, flash_remaining - delta)
		pulse_remaining = maxf(0.0, pulse_remaining - delta)
		acknowledge_remaining = maxf(0.0, acknowledge_remaining - delta)
		queue_redraw()


func set_timing(
	is_active: bool,
	is_visual_mode: bool,
	current_clock: float,
	target_time: float
) -> void:
	calibration_active = is_active
	visual_mode = is_visual_mode
	clock_time = current_clock
	next_target_time = target_time
	queue_redraw()


func pulse() -> void:
	pulse_remaining = PULSE_DURATION_SECONDS
	queue_redraw()


func acknowledge_tap() -> void:
	acknowledge_remaining = TAP_ACKNOWLEDGE_DURATION_SECONDS
	queue_redraw()


func flash() -> void:
	flash_remaining = FLASH_DURATION_SECONDS
	pulse()


func _draw() -> void:
	if not calibration_active:
		return

	if visual_mode:
		_draw_visual_test()
	else:
		_draw_metronome_circle()


func _draw_metronome_circle() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = screen_size / 2.0
	var pulse_strength: float = clampf(
		pulse_remaining / PULSE_DURATION_SECONDS,
		0.0,
		1.0
	)
	var acknowledge_strength: float = clampf(
		acknowledge_remaining / TAP_ACKNOWLEDGE_DURATION_SECONDS,
		0.0,
		1.0
	)
	var glow_color: Color = CIRCLE_GLOW_COLOR
	glow_color.a *= 0.45 + pulse_strength * 0.55
	draw_circle(
		center,
		CIRCLE_RADIUS + 34.0 + pulse_strength * 42.0,
		glow_color
	)
	draw_circle(center, CIRCLE_RADIUS, CIRCLE_FILL_COLOR)
	var edge_color: Color = CIRCLE_EDGE_COLOR.lerp(
		Color.WHITE,
		pulse_strength * 0.75
	)
	draw_arc(
		center,
		CIRCLE_RADIUS + pulse_strength * 12.0,
		0.0,
		TAU,
		96,
		edge_color,
		10.0 + pulse_strength * 10.0,
		true
	)
	if acknowledge_strength > 0.0:
		var acknowledge_color: Color = TAP_ACKNOWLEDGE_COLOR
		acknowledge_color.a *= acknowledge_strength
		draw_arc(
			center,
			CIRCLE_RADIUS - 28.0,
			0.0,
			TAU,
			96,
			acknowledge_color,
			14.0,
			true
		)
	var font: Font = ThemeDB.fallback_font
	var text: String = "TAP"
	var font_size: int = 52
	var text_size: Vector2 = font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	draw_string(
		font,
		center + Vector2(-text_size.x / 2.0, text_size.y / 3.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(0.86, 0.97, 1.0, 1.0)
	)


func _draw_visual_test() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var flash_strength: float = clampf(
		flash_remaining / FLASH_DURATION_SECONDS,
		0.0,
		1.0
	)
	if flash_strength > 0.0:
		var flash_color: Color = FLASH_COLOR
		flash_color.a *= flash_strength
		draw_rect(Rect2(Vector2.ZERO, screen_size), flash_color)

	var visual_clock: float = (
		clock_time + SettingsManager.visual_offset_seconds
	)
	var time_until_target: float = next_target_time - visual_clock
	if time_until_target > NoteMotion.get_approach_time():
		return
	if time_until_target < -0.12:
		return

	var position: Vector2 = NoteMotion.position_for_time(
		0.5,
		next_target_time,
		visual_clock,
		screen_size
	)
	var perspective_scale: float = NoteMotion.scale_for_time(
		next_target_time,
		visual_clock
	)
	var note_width: float = (
		NoteMotion.gameplay_width(screen_size)
		* NOTE_WIDTH_RATIO
		* perspective_scale
	)
	var note_height: float = NOTE_HEIGHT * perspective_scale
	var note_rect: Rect2 = Rect2(
		position - Vector2(note_width, note_height) / 2.0,
		Vector2(note_width, note_height)
	)
	var glow_rect: Rect2 = note_rect.grow(18.0 * perspective_scale)
	draw_rect(glow_rect, NOTE_GLOW_COLOR)
	draw_rect(note_rect, NOTE_COLOR)
	draw_line(
		Vector2(note_rect.position.x, position.y),
		Vector2(note_rect.end.x, position.y),
		Color.WHITE,
		4.0 * perspective_scale,
		true
	)
