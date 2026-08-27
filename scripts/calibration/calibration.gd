extends Node

const CONFIG_SCENE: String = "res://scenes/config/config_menu.tscn"
const SAMPLE_COUNT: int = 12
const START_DELAY_SECONDS: float = 2.2
const BEAT_INTERVAL_SECONDS: float = 1.10
# Generous by design: the robust median rejects stray taps afterwards. The
# previous 500 ms gate could reject a valid touch near the midpoint between
# two slow calibration pulses, especially on devices with high latency.
const TAP_WINDOW_SECONDS: float = 0.75
const OFFSET_LIMIT_SECONDS: float = 0.250
const CLICK_DURATION_SECONDS: float = 0.10
const CLICK_FREQUENCY: float = 1100.0
const CLICK_SAMPLE_RATE: int = 44100

enum CalibrationMode {
	IDLE,
	METRONOME,
	VISUAL,
}

@onready var top_panel: VBoxContainer = $UI/Root/TopPanel
@onready var instruction_label: Label = $UI/Root/TopPanel/Instruction
@onready var explanation_label: Label = $UI/Root/TopPanel/Explanation
@onready var progress_label: Label = $UI/Root/TopPanel/Progress
@onready var offsets_label: Label = $UI/Root/TopPanel/Offsets
@onready var actions: HBoxContainer = $UI/Root/Actions
@onready var metronome_button: Button = (
	$UI/Root/Actions/MetronomeButton
)
@onready var visual_button: Button = $UI/Root/Actions/VisualButton
@onready var reset_button: Button = $UI/Root/Actions/ResetButton
@onready var back_button: Button = $UI/Root/Actions/BackButton
@onready var cancel_button: Button = $UI/Root/Actions/CancelButton
@onready var result_panel: PanelContainer = $UI/Root/ResultPanel
@onready var result_title: Label = $UI/Root/ResultPanel/Content/Title
@onready var distribution: TimingDistribution = (
	$UI/Root/ResultPanel/Content/Distribution
)
@onready var samples_label: Label = (
	$UI/Root/ResultPanel/Content/Samples
)
@onready var median_label: Label = $UI/Root/ResultPanel/Content/Median
@onready var current_label: Label = $UI/Root/ResultPanel/Content/Current
@onready var suggested_label: Label = (
	$UI/Root/ResultPanel/Content/Suggested
)
@onready var result_explanation: Label = (
	$UI/Root/ResultPanel/Content/Explanation
)
@onready var apply_button: Button = (
	$UI/Root/ResultPanel/Content/ResultActions/ApplyButton
)
@onready var retry_button: Button = (
	$UI/Root/ResultPanel/Content/ResultActions/RetryButton
)
@onready var discard_button: Button = (
	$UI/Root/ResultPanel/Content/ResultActions/DiscardButton
)
@onready var click_player: AudioStreamPlayer = $ClickPlayer
@onready var calibration_visual: CalibrationVisual = $CalibrationVisual

var mode: CalibrationMode = CalibrationMode.IDLE
var next_beat_time: float = 0.0
var last_beat_time: float = -1.0
var beat_number: int = 0
var tapped_beat_number: int = -1
var rejected_tap_count: int = 0
var tap_errors: Array[float] = []
var result_visible: bool = false
var pending_mode: CalibrationMode = CalibrationMode.IDLE
var pending_offset_seconds: float = 0.0


func _ready() -> void:
	metronome_button.pressed.connect(_start_metronome_calibration)
	visual_button.pressed.connect(_start_visual_calibration)
	reset_button.pressed.connect(_reset_offsets)
	back_button.pressed.connect(_go_back)
	cancel_button.pressed.connect(_cancel_calibration)
	apply_button.pressed.connect(_apply_result)
	retry_button.pressed.connect(_retry_result)
	discard_button.pressed.connect(_discard_result)
	get_tree().root.go_back_requested.connect(_on_back_requested)
	click_player.stream = _create_click_sample()
	_update_offset_label()
	_show_idle_instructions()
	metronome_button.grab_focus()


func _process(_delta: float) -> void:
	var now: float = _clock_seconds()
	calibration_visual.set_timing(
		mode != CalibrationMode.IDLE,
		mode == CalibrationMode.VISUAL,
		now,
		next_beat_time
	)

	if mode == CalibrationMode.IDLE:
		return

	var event_time: float = _get_next_event_time()
	if last_beat_time < 0.0 and now < event_time:
		progress_label.text = "STARTS IN %.1f s" % (event_time - now)
	if now - event_time > BEAT_INTERVAL_SECONDS:
		last_beat_time = -1.0
		next_beat_time = now + START_DELAY_SECONDS
		progress_label.text = "GET READY"
		return

	while now >= event_time:
		_emit_beat()
		next_beat_time += BEAT_INTERVAL_SECONDS
		event_time = _get_next_event_time()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_requested()
		return

	if mode == CalibrationMode.IDLE:
		return

	var is_tap: bool = (
		event is InputEventScreenTouch and event.pressed
	) or (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	)
	if is_tap:
		_record_tap()


func _start_metronome_calibration() -> void:
	_start_calibration(CalibrationMode.METRONOME)
	instruction_label.text = "Tap the large circle whenever you hear a click."
	explanation_label.text = (
		"This test proposes INPUT offset: it corrects when the device "
		+ "timestamps your touch too early or too late."
	)


func _start_visual_calibration() -> void:
	_start_calibration(CalibrationMode.VISUAL)
	instruction_label.text = (
		"Tap when the note reaches the target zone and the screen flashes."
	)
	explanation_label.text = (
		"This test proposes VISUAL offset: it moves only rendered notes; "
		+ "judgement timing does not change."
	)


func _start_calibration(new_mode: CalibrationMode) -> void:
	result_visible = false
	result_panel.visible = false
	top_panel.visible = true
	actions.visible = true
	mode = new_mode
	tap_errors.clear()
	rejected_tap_count = 0
	beat_number = 0
	tapped_beat_number = -1
	last_beat_time = -1.0
	next_beat_time = _clock_seconds() + START_DELAY_SECONDS
	progress_label.text = "GET READY"
	_set_test_controls_enabled(false)


func _get_next_event_time() -> float:
	var event_time: float = next_beat_time
	if mode == CalibrationMode.VISUAL:
		event_time -= SettingsManager.visual_offset_seconds
	return event_time


func _emit_beat() -> void:
	last_beat_time = next_beat_time
	beat_number += 1
	if mode == CalibrationMode.METRONOME:
		click_player.play()
		calibration_visual.pulse()
	elif mode == CalibrationMode.VISUAL:
		calibration_visual.flash()


func _record_tap() -> void:
	if last_beat_time < 0.0:
		progress_label.text = "WAIT FOR THE FIRST PULSE"
		return
	var corrected_time: float = (
		_clock_seconds() + SettingsManager.input_offset_seconds
	)
	# Associate the touch with the closest pulse. This also accepts touches a
	# little before the upcoming pulse instead of comparing them only with the
	# previous one and incorrectly reporting "too far".
	var target_beat_number: int = beat_number
	var target_beat_time: float = last_beat_time
	var previous_error: float = corrected_time - last_beat_time
	var next_error: float = corrected_time - next_beat_time
	if absf(next_error) < absf(previous_error):
		target_beat_number = beat_number + 1
		target_beat_time = next_beat_time
	if tapped_beat_number == target_beat_number:
		return

	var error: float = corrected_time - target_beat_time
	if absf(error) > TAP_WINDOW_SECONDS:
		rejected_tap_count += 1
		progress_label.text = "TOO FAR FROM THE PULSE — TRY THE NEXT ONE"
		return

	tapped_beat_number = target_beat_number
	tap_errors.append(error)
	calibration_visual.acknowledge_tap()
	progress_label.text = "TAPS  %d / %d" % [
		tap_errors.size(),
		SAMPLE_COUNT,
	]

	if tap_errors.size() >= SAMPLE_COUNT:
		_finish_calibration()


func _finish_calibration() -> void:
	pending_mode = mode
	var result: Dictionary = CalibrationMath.filtered_median(tap_errors)
	var median_error: float = float(result.get("median", 0.0))
	var used_count: int = int(result.get("used_count", 0))
	var discarded_count: int = int(result.get("discarded_count", 0))
	var used_mask: Array[bool] = []
	var used_mask_value: Variant = result.get("used_mask", [])
	if used_mask_value is Array:
		for value: Variant in used_mask_value:
			used_mask.append(bool(value))

	var current_audio: float = SettingsManager.audio_offset_seconds
	var current_input: float = SettingsManager.input_offset_seconds
	var current_visual: float = SettingsManager.visual_offset_seconds
	var suggested_input: float = current_input
	var suggested_visual: float = current_visual
	if pending_mode == CalibrationMode.METRONOME:
		suggested_input = clampf(
			current_input - median_error,
			-OFFSET_LIMIT_SECONDS,
			OFFSET_LIMIT_SECONDS
		)
		pending_offset_seconds = suggested_input
	else:
		suggested_visual = clampf(
			current_visual + median_error,
			-OFFSET_LIMIT_SECONDS,
			OFFSET_LIMIT_SECONDS
		)
		pending_offset_seconds = suggested_visual

	mode = CalibrationMode.IDLE
	click_player.stop()
	calibration_visual.set_timing(false, false, 0.0, 0.0)
	result_visible = true
	top_panel.visible = false
	actions.visible = false
	result_panel.visible = true
	result_title.text = (
		"METRONOME RESULT"
		if pending_mode == CalibrationMode.METRONOME
		else "VISUAL RESULT"
	)
	distribution.set_distribution(
		tap_errors,
		used_mask,
		median_error,
		TAP_WINDOW_SECONDS
	)
	samples_label.text = "ALL TAPS (ms): " + _format_samples(tap_errors)
	median_label.text = (
		"MEDIAN ERROR: %+.0f ms   •   %d KEPT   •   %d OUTLIER(S)"
		% [median_error * 1000.0, used_count, discarded_count]
	)
	if rejected_tap_count > 0:
		median_label.text += "   •   %d OUTSIDE WINDOW" % rejected_tap_count
	current_label.text = "BEFORE: " + _format_offsets(
		current_audio,
		current_input,
		current_visual
	)
	suggested_label.text = "IF APPLIED: " + _format_offsets(
		current_audio,
		suggested_input,
		suggested_visual
	)
	if pending_mode == CalibrationMode.METRONOME:
		apply_button.text = "APPLY INPUT %+.0f ms" % (
			suggested_input * 1000.0
		)
		result_explanation.text = (
			"Only INPUT will change. AUDIO and VISUAL stay untouched. "
			+ "Blue dots are retained taps; orange dots are discarded outliers."
		)
	else:
		apply_button.text = "APPLY VISUAL %+.0f ms" % (
			suggested_visual * 1000.0
		)
		result_explanation.text = (
			"Only VISUAL will change. AUDIO and INPUT stay untouched. "
			+ "Blue dots are retained taps; orange dots are discarded outliers."
		)
	apply_button.grab_focus()


func _apply_result() -> void:
	if not result_visible:
		return
	var applied_name: String
	if pending_mode == CalibrationMode.METRONOME:
		SettingsManager.set_input_offset(pending_offset_seconds)
		applied_name = "INPUT"
	else:
		SettingsManager.set_visual_offset(pending_offset_seconds)
		applied_name = "VISUAL"
	SettingsManager.save_settings()
	_close_result()
	_update_offset_label()
	instruction_label.text = "%s OFFSET APPLIED" % applied_name
	progress_label.text = "SAVED ON THIS DEVICE"


func _retry_result() -> void:
	if not result_visible:
		return
	var retry_mode: CalibrationMode = pending_mode
	_close_result()
	if retry_mode == CalibrationMode.METRONOME:
		_start_metronome_calibration()
	else:
		_start_visual_calibration()


func _discard_result() -> void:
	_close_result()
	instruction_label.text = "RESULT DISCARDED — NO OFFSET WAS CHANGED"
	progress_label.text = "CHOOSE A TEST"


func _close_result() -> void:
	result_visible = false
	pending_mode = CalibrationMode.IDLE
	result_panel.visible = false
	top_panel.visible = true
	actions.visible = true
	_set_test_controls_enabled(true)


func _cancel_calibration() -> void:
	mode = CalibrationMode.IDLE
	tap_errors.clear()
	click_player.stop()
	calibration_visual.set_timing(false, false, 0.0, 0.0)
	_set_test_controls_enabled(true)
	_show_idle_instructions()


func _reset_offsets() -> void:
	SettingsManager.set_audio_offset(0.0)
	SettingsManager.set_input_offset(0.0)
	SettingsManager.set_visual_offset(0.0)
	SettingsManager.save_settings()
	_update_offset_label()
	progress_label.text = "ALL OFFSETS RESET"


func _set_test_controls_enabled(enabled: bool) -> void:
	actions.visible = true
	metronome_button.visible = enabled
	visual_button.visible = enabled
	reset_button.visible = enabled
	back_button.visible = enabled
	cancel_button.visible = not enabled
	if enabled:
		metronome_button.grab_focus()
	else:
		cancel_button.grab_focus()


func _show_idle_instructions() -> void:
	instruction_label.text = "Choose what you want to calibrate."
	explanation_label.text = (
		"AUDIO = moves the chart clock against the music (manual).   "
		+ "INPUT = corrects touch timestamps (metronome).   "
		+ "VISUAL = moves only rendered notes (visual test).\n"
		+ "Positive AUDIO/VISUAL moves earlier; positive INPUT counts "
		+ "the tap later. Negative values do the opposite."
	)
	progress_label.text = "CHOOSE A TEST"


func _update_offset_label() -> void:
	offsets_label.text = _format_offsets(
		SettingsManager.audio_offset_seconds,
		SettingsManager.input_offset_seconds,
		SettingsManager.visual_offset_seconds
	)


func _format_offsets(
	audio_offset: float,
	input_offset: float,
	visual_offset: float
) -> String:
	return "AUDIO %+.0f ms    INPUT %+.0f ms    VISUAL %+.0f ms" % [
		audio_offset * 1000.0,
		input_offset * 1000.0,
		visual_offset * 1000.0,
	]


func _format_samples(samples: Array[float]) -> String:
	var formatted: Array[String] = []
	for sample: float in samples:
		formatted.append("%+.0f" % (sample * 1000.0))
	return ", ".join(formatted)


func _on_back_requested() -> void:
	if result_visible:
		_discard_result()
	elif mode != CalibrationMode.IDLE:
		_cancel_calibration()
	else:
		_go_back()


func _go_back() -> void:
	SettingsManager.save_settings()
	get_tree().change_scene_to_file(CONFIG_SCENE)


func _clock_seconds() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _create_click_sample() -> AudioStreamWAV:
	var frame_count: int = int(
		CLICK_SAMPLE_RATE * CLICK_DURATION_SECONDS
	)
	var audio_data: PackedByteArray = PackedByteArray()
	audio_data.resize(frame_count * 2)

	for frame: int in range(frame_count):
		var time: float = float(frame) / float(CLICK_SAMPLE_RATE)
		var progress: float = float(frame) / float(frame_count)
		var envelope: float = pow(1.0 - progress, 3.0)
		var tone: float = (
			sin(TAU * CLICK_FREQUENCY * time) * 0.72
			+ sin(TAU * CLICK_FREQUENCY * 2.0 * time) * 0.20
		)
		var sample: int = clampi(
			int(tone * envelope * 32767.0),
			-32768,
			32767
		)
		audio_data.encode_s16(frame * 2, sample)

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CLICK_SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream
