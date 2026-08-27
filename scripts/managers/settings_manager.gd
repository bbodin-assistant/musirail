extends Node

const MUSIC_BUS: StringName = &"Music"
const EFFECTS_BUS: StringName = &"Effects"
const SETTINGS_PATH: String = "user://settings.json"
const SETTINGS_VERSION: int = 4
const SCORE_HISTORY_LIMIT: int = 10
const SAVE_DELAY_SECONDS: float = 0.25
const TIMING_OFFSET_LIMIT_SECONDS: float = 0.250
const DEFAULT_MUSIC_VOLUME: float = 1.0
const DEFAULT_EFFECTS_VOLUME: float = 1.0

var music_volume: float = DEFAULT_MUSIC_VOLUME
var effects_volume: float = DEFAULT_EFFECTS_VOLUME
var note_visibility_seconds: float = NoteMotion.DEFAULT_APPROACH_TIME
var audio_offset_seconds: float = 0.0
var input_offset_seconds: float = 0.0
var visual_offset_seconds: float = 0.0
var best_scores: Dictionary = {}
var score_history: Dictionary = {}
var save_timer: Timer


func _ready() -> void:
	_load_settings()
	_apply_volume(MUSIC_BUS, music_volume)
	_apply_volume(EFFECTS_BUS, effects_volume)
	NoteMotion.set_approach_time(note_visibility_seconds)

	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = SAVE_DELAY_SECONDS
	save_timer.timeout.connect(save_settings)
	add_child(save_timer)


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume(MUSIC_BUS, music_volume)
	_schedule_save()


func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	_apply_volume(EFFECTS_BUS, effects_volume)
	_schedule_save()


func set_note_visibility(value: float) -> void:
	note_visibility_seconds = clampf(
		value,
		NoteMotion.MIN_APPROACH_TIME,
		NoteMotion.MAX_APPROACH_TIME
	)
	NoteMotion.set_approach_time(note_visibility_seconds)
	_schedule_save()


func set_audio_offset(value: float) -> void:
	audio_offset_seconds = _clamp_timing_offset(value)
	_schedule_save()


func set_input_offset(value: float) -> void:
	input_offset_seconds = _clamp_timing_offset(value)
	_schedule_save()


func set_visual_offset(value: float) -> void:
	visual_offset_seconds = _clamp_timing_offset(value)
	_schedule_save()


func correct_input_time(gameplay_time: float) -> float:
	return gameplay_time + input_offset_seconds


func get_visual_time(gameplay_time: float) -> float:
	return gameplay_time + visual_offset_seconds


func save_settings() -> void:
	if save_timer != null:
		save_timer.stop()

	var settings: Dictionary = {
		"version": SETTINGS_VERSION,
		"audio": {
			"music_volume": music_volume,
			"effects_volume": effects_volume,
		},
		"gameplay": {
			"note_visibility_seconds": note_visibility_seconds,
		},
		"timing": {
			"audio_offset_ms": audio_offset_seconds * 1000.0,
			"input_offset_ms": input_offset_seconds * 1000.0,
			"visual_offset_ms": visual_offset_seconds * 1000.0,
		},
		"best_scores": best_scores,
		"score_history": score_history,
	}
	var file: FileAccess = FileAccess.open(
		SETTINGS_PATH,
		FileAccess.WRITE
	)

	if file == null:
		push_error("Unable to save settings to " + SETTINGS_PATH)
		return

	file.store_string(JSON.stringify(settings, "\t") + "\n")
	file.close()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return

	var file: FileAccess = FileAccess.open(
		SETTINGS_PATH,
		FileAccess.READ
	)

	if file == null:
		push_warning("Unable to read settings from " + SETTINGS_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		push_warning("Ignoring invalid settings file: " + SETTINGS_PATH)
		return

	var settings: Dictionary = parsed
	var audio_value: Variant = settings.get("audio", {})
	var gameplay_value: Variant = settings.get("gameplay", {})
	var timing_value: Variant = settings.get("timing", {})
	var best_scores_value: Variant = settings.get("best_scores", {})
	var score_history_value: Variant = settings.get("score_history", {})

	if audio_value is Dictionary:
		var audio: Dictionary = audio_value
		music_volume = clampf(
			float(audio.get("music_volume", DEFAULT_MUSIC_VOLUME)),
			0.0,
			1.0
		)
		effects_volume = clampf(
			float(audio.get("effects_volume", DEFAULT_EFFECTS_VOLUME)),
			0.0,
			1.0
		)

	if gameplay_value is Dictionary:
		var gameplay: Dictionary = gameplay_value
		note_visibility_seconds = clampf(
			float(gameplay.get(
				"note_visibility_seconds",
				NoteMotion.DEFAULT_APPROACH_TIME
			)),
			NoteMotion.MIN_APPROACH_TIME,
			NoteMotion.MAX_APPROACH_TIME
		)

	if best_scores_value is Dictionary:
		best_scores = best_scores_value.duplicate(true)
	if score_history_value is Dictionary:
		score_history = score_history_value.duplicate(true)

	if timing_value is Dictionary:
		var timing: Dictionary = timing_value
		audio_offset_seconds = _clamp_timing_offset(
			float(timing.get("audio_offset_ms", 0.0)) / 1000.0
		)
		input_offset_seconds = _clamp_timing_offset(
			float(timing.get("input_offset_ms", 0.0)) / 1000.0
		)
		visual_offset_seconds = _clamp_timing_offset(
			float(timing.get("visual_offset_ms", 0.0)) / 1000.0
		)


func get_best_score(song_id: String, difficulty_id: String) -> int:
	var record: Dictionary = get_best_result(song_id, difficulty_id)
	return maxi(0, int(record.get("score", 0)))


func get_best_result(song_id: String, difficulty_id: String) -> Dictionary:
	var song_scores_value: Variant = best_scores.get(song_id, {})

	if not song_scores_value is Dictionary:
		return {}

	var song_scores: Dictionary = song_scores_value
	var record_value: Variant = song_scores.get(difficulty_id, {})

	if not record_value is Dictionary:
		return {}

	return record_value.duplicate(true)


func delete_song_scores(song_id: String) -> void:
	if song_id.is_empty():
		return
	best_scores.erase(song_id)
	score_history.erase(song_id)
	save_settings()


func register_best_result(
	song_id: String,
	difficulty_id: String,
	summary: Dictionary
) -> bool:
	var is_new_best: bool = _update_best_result(
		song_id,
		difficulty_id,
		summary
	)
	if is_new_best:
		save_settings()
	return is_new_best


func register_result(
	song_id: String,
	difficulty_id: String,
	summary: Dictionary
) -> bool:
	_append_score_history(song_id, difficulty_id, summary)
	var is_new_best: bool = _update_best_result(
		song_id,
		difficulty_id,
		summary
	)
	save_settings()
	return is_new_best


func get_score_history(
	song_id: String,
	difficulty_id: String
) -> Array[Dictionary]:
	var song_history_value: Variant = score_history.get(song_id, {})
	if song_history_value is Dictionary:
		var song_history: Dictionary = song_history_value
		var records_value: Variant = song_history.get(difficulty_id, [])
		if records_value is Array and not records_value.is_empty():
			var records: Array[Dictionary] = []
			for record_value: Variant in records_value:
				if record_value is Dictionary:
					records.append(record_value.duplicate(true))
			return records

	# Settings written before score history existed still contribute their best.
	var legacy_best: Dictionary = get_best_result(song_id, difficulty_id)
	if legacy_best.is_empty():
		return []
	legacy_best["legacy"] = true
	return [legacy_best]


func _update_best_result(
	song_id: String,
	difficulty_id: String,
	summary: Dictionary
) -> bool:
	if not bool(summary.get("cleared", true)):
		return false
	var song_scores_value: Variant = best_scores.get(song_id, {})
	var song_scores: Dictionary = (
		song_scores_value.duplicate(true)
		if song_scores_value is Dictionary
		else {}
	)
	var has_record: bool = song_scores.get(difficulty_id, null) is Dictionary
	var previous_score: int = get_best_score(song_id, difficulty_id)
	var new_score: int = maxi(0, int(summary.get("score", 0)))

	if has_record and new_score <= previous_score:
		return false

	song_scores[difficulty_id] = _make_result_record(summary, false)
	best_scores[song_id] = song_scores
	return true


func _append_score_history(
	song_id: String,
	difficulty_id: String,
	summary: Dictionary
) -> void:
	var song_history_value: Variant = score_history.get(song_id, {})
	var song_history: Dictionary = (
		song_history_value.duplicate(true)
		if song_history_value is Dictionary
		else {}
	)
	var records_value: Variant = song_history.get(difficulty_id, [])
	var records: Array = (
		records_value.duplicate(true)
		if records_value is Array
		else []
	)
	records.push_front(_make_result_record(summary, true))
	if records.size() > SCORE_HISTORY_LIMIT:
		records.resize(SCORE_HISTORY_LIMIT)
	song_history[difficulty_id] = records
	score_history[song_id] = song_history


func _make_result_record(
	summary: Dictionary,
	include_attempt_data: bool
) -> Dictionary:
	var judgements_value: Variant = summary.get("judgements", {})
	var record: Dictionary = {
		"score": maxi(0, int(summary.get("score", 0))),
		"maximum_score": maxi(0, int(summary.get("maximum_score", 0))),
		"grade": str(summary.get("grade", "F")),
		"accuracy": float(summary.get("accuracy", 0.0)),
		"max_combo": maxi(0, int(summary.get("max_combo", 0))),
		"achievement": str(summary.get("achievement", "CLEARED")),
		"judgements": (
			judgements_value.duplicate(true)
			if judgements_value is Dictionary
			else {}
		),
	}
	if include_attempt_data:
		record["cleared"] = bool(summary.get("cleared", true))
		record["life_percentage"] = clampf(
			float(summary.get("life_percentage", 0.0)),
			0.0,
			100.0
		)
		record["played_at"] = int(Time.get_unix_time_from_system())
	return record


func _schedule_save() -> void:
	if save_timer != null:
		save_timer.start()


func _clamp_timing_offset(value: float) -> float:
	return clampf(
		value,
		-TIMING_OFFSET_LIMIT_SECONDS,
		TIMING_OFFSET_LIMIT_SECONDS
	)


func _apply_volume(bus_name: StringName, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index < 0:
		push_warning("Audio bus not found: " + str(bus_name))
		return

	AudioServer.set_bus_mute(bus_index, value <= 0.0)
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(maxf(value, 0.0001))
	)
