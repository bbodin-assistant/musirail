extends Control

const START_MENU_SCENE: String = (
	"res://scenes/start_menu/start_menu.tscn"
)
const CALIBRATION_SCENE: String = (
	"res://scenes/calibration/calibration.tscn"
)
const MUSIC_SAMPLE_START_SECONDS: float = 5.0
const EFFECT_SAMPLE_DURATION: float = 0.16
const EFFECT_SAMPLE_FREQUENCY: float = 880.0
const EFFECT_SAMPLE_RATE: int = 44100

@onready var music_label: Label = (
	$Background/Center/Panel/Music/Label
)
@onready var music_slider: HSlider = (
	$Background/Center/Panel/Music/Slider
)
@onready var effects_label: Label = (
	$Background/Center/Panel/Effects/Label
)
@onready var effects_slider: HSlider = (
	$Background/Center/Panel/Effects/Slider
)
@onready var audio_offset_label: Label = (
	$Background/Center/Panel/Timing/AudioOffset/Label
)
@onready var audio_offset_slider: HSlider = (
	$Background/Center/Panel/Timing/AudioOffset/Slider
)
@onready var input_offset_label: Label = (
	$Background/Center/Panel/Timing/InputOffset/Label
)
@onready var input_offset_slider: HSlider = (
	$Background/Center/Panel/Timing/InputOffset/Slider
)
@onready var visual_offset_label: Label = (
	$Background/Center/Panel/Timing/VisualOffset/Label
)
@onready var visual_offset_slider: HSlider = (
	$Background/Center/Panel/Timing/VisualOffset/Slider
)
@onready var calibrate_button: Button = (
	$Background/Center/Panel/CalibrateButton
)
@onready var back_button: Button = $Background/Center/Panel/BackButton
@onready var music_preview: AudioStreamPlayer = $MusicPreview
@onready var effects_preview: AudioStreamPlayer = $EffectsPreview
@onready var music_preview_timer: Timer = $MusicPreviewTimer
@onready var effects_preview_timer: Timer = $EffectsPreviewTimer
@onready var music_stop_timer: Timer = $MusicStopTimer


func _ready() -> void:
	music_slider.value = SettingsManager.music_volume
	effects_slider.value = SettingsManager.effects_volume
	audio_offset_slider.value = SettingsManager.audio_offset_seconds * 1000.0
	input_offset_slider.value = SettingsManager.input_offset_seconds * 1000.0
	visual_offset_slider.value = SettingsManager.visual_offset_seconds * 1000.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	effects_slider.value_changed.connect(_on_effects_volume_changed)
	audio_offset_slider.value_changed.connect(_on_audio_offset_changed)
	input_offset_slider.value_changed.connect(_on_input_offset_changed)
	visual_offset_slider.value_changed.connect(_on_visual_offset_changed)
	calibrate_button.pressed.connect(_open_calibration)
	back_button.pressed.connect(_go_back)
	get_tree().root.go_back_requested.connect(_go_back)
	music_preview_timer.timeout.connect(_play_music_preview)
	effects_preview_timer.timeout.connect(_play_effects_preview)
	music_stop_timer.timeout.connect(music_preview.stop)
	_configure_music_preview()
	effects_preview.stream = _create_effect_sample()
	_update_volume_labels()
	_update_offset_labels()
	music_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _on_music_volume_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)
	_update_volume_labels()
	music_preview_timer.start()


func _on_effects_volume_changed(value: float) -> void:
	SettingsManager.set_effects_volume(value)
	_update_volume_labels()
	effects_preview_timer.start()


func _update_volume_labels() -> void:
	music_label.text = "MUSIC VOLUME: %d%%" % int(
		round(SettingsManager.music_volume * 100.0)
	)
	effects_label.text = "EFFECTS VOLUME: %d%%" % int(
		round(SettingsManager.effects_volume * 100.0)
	)


func _on_audio_offset_changed(value_ms: float) -> void:
	SettingsManager.set_audio_offset(value_ms / 1000.0)
	_update_offset_labels()


func _on_input_offset_changed(value_ms: float) -> void:
	SettingsManager.set_input_offset(value_ms / 1000.0)
	_update_offset_labels()


func _on_visual_offset_changed(value_ms: float) -> void:
	SettingsManager.set_visual_offset(value_ms / 1000.0)
	_update_offset_labels()


func _update_offset_labels() -> void:
	audio_offset_label.text = _format_offset(
		"AUDIO OFFSET",
		SettingsManager.audio_offset_seconds
	)
	input_offset_label.text = _format_offset(
		"INPUT OFFSET",
		SettingsManager.input_offset_seconds
	)
	visual_offset_label.text = _format_offset(
		"VISUAL OFFSET",
		SettingsManager.visual_offset_seconds
	)


func _format_offset(label: String, seconds: float) -> String:
	return "%s: %+.0f ms" % [label, seconds * 1000.0]


func _open_calibration() -> void:
	SettingsManager.save_settings()
	get_tree().change_scene_to_file(CALIBRATION_SCENE)


func _go_back() -> void:
	SettingsManager.save_settings()
	get_tree().change_scene_to_file(START_MENU_SCENE)


func _play_music_preview() -> void:
	if music_preview.stream != null:
		music_preview.play(minf(
			MUSIC_SAMPLE_START_SECONDS,
			maxf(music_preview.stream.get_length() - 0.5, 0.0)
		))


func _configure_music_preview() -> void:
	for song: Dictionary in SongLibrary.get_all_songs():
		if not SongLibrary.is_song_playable(song):
			continue
		var stream: AudioStream = SongLibrary.load_audio(
			SongLibrary.get_audio_path(song)
		)
		if stream != null:
			music_preview.stream = stream
			return
	music_stop_timer.start()


func _play_effects_preview() -> void:
	effects_preview.play()


func _create_effect_sample() -> AudioStreamWAV:
	var frame_count: int = int(
		EFFECT_SAMPLE_RATE * EFFECT_SAMPLE_DURATION
	)
	var audio_data: PackedByteArray = PackedByteArray()
	audio_data.resize(frame_count * 2)

	for frame: int in range(frame_count):
		var time: float = float(frame) / float(EFFECT_SAMPLE_RATE)
		var progress: float = float(frame) / float(frame_count)
		var envelope: float = pow(1.0 - progress, 2.0)
		var tone: float = (
			sin(TAU * EFFECT_SAMPLE_FREQUENCY * time) * 0.72
			+ sin(TAU * EFFECT_SAMPLE_FREQUENCY * 2.0 * time) * 0.18
		)
		var sample: int = clampi(
			int(tone * envelope * 32767.0),
			-32768,
			32767
		)
		audio_data.encode_s16(frame * 2, sample)

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = EFFECT_SAMPLE_RATE
	stream.stereo = false
	stream.data = audio_data
	return stream
