extends Node

const TAP_NOTE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/tap_note.tscn"
)
const HOLD_NOTE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/hold_note.tscn"
)
const FLICK_NOTE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/flick_note.tscn"
)
const SLIDE_NOTE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/slide_note.tscn"
)
const CHART_VERSION: int = 4
const DIFFICULTY_ORDER: Array[String] = [
	"easy",
	"normal",
	"hard",
	"expert",
	"master",
]


func load_chart(
	chart_path: String,
	note_parent: Node,
	difficulty_id: String = "normal"
) -> void:
	var chart: Dictionary = _read_chart(chart_path)

	if chart.is_empty():
		return

	var difficulty: Dictionary = _resolve_difficulty(
		chart,
		difficulty_id
	)

	if difficulty.is_empty():
		return

	var notes_value: Variant = difficulty.get("notes", [])

	if not notes_value is Array:
		push_error("The selected chart difficulty has no notes array.")
		return

	var notes: Array = notes_value
	ScoreManager.set_maximum_score(
		ScoreGrade.maximum_score_for_notes(notes)
	)

	for note_data: Variant in notes:
		if not note_data is Dictionary:
			continue

		create_note(note_data, note_parent)

	print(
		"Chart loaded: ",
		notes.size(),
		" notes (",
		difficulty.get("label", difficulty_id.capitalize()),
		")"
	)


func get_difficulties(chart_path: String) -> Array[Dictionary]:
	var chart: Dictionary = _read_chart(chart_path)

	if chart.is_empty():
		return []

	var difficulties_value: Variant = chart.get("difficulties")

	if difficulties_value is Dictionary:
		var difficulty_map: Dictionary = difficulties_value
		var difficulty_ids: Array[String] = []

		for difficulty_id: Variant in difficulty_map.keys():
			difficulty_ids.append(str(difficulty_id))

		difficulty_ids.sort_custom(_difficulty_precedes)
		var result: Array[Dictionary] = []

		for difficulty_id: String in difficulty_ids:
			var difficulty_value: Variant = difficulty_map[difficulty_id]

			if not difficulty_value is Dictionary:
				continue

			var difficulty: Dictionary = difficulty_value
			var notes_value: Variant = difficulty.get("notes", [])
			var note_count: int = (
			notes_value.size() if notes_value is Array else 0
			)

			result.append({
				"id": difficulty_id,
				"label": str(
					difficulty.get(
						"label",
						difficulty_id.capitalize()
					)
				),
				"stars": clampi(
					int(difficulty.get("stars", 1)),
					1,
					5
				),
				"note_count": note_count,
				"max_score": (
					ScoreGrade.maximum_score_for_notes(notes_value)
					if notes_value is Array
					else 0
				),
			})

		return result

	push_error("The chart contains no playable difficulty: " + chart_path)
	return []


func _read_chart(chart_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(
		chart_path,
		FileAccess.READ
	)

	if file == null:
		push_error("Unable to open chart: " + chart_path)
		return {}

	var json_text: String = file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(json_text)

	if data == null:
		push_error("Invalid chart JSON: " + chart_path)
		return {}

	if not data is Dictionary:
		push_error("The chart root must be a JSON object: " + chart_path)
		return {}

	var chart: Dictionary = data
	if int(chart.get("version", 0)) != CHART_VERSION:
		push_error(
			"Unsupported chart version in %s: expected %d."
			% [chart_path, CHART_VERSION]
		)
		return {}

	return chart


func _resolve_difficulty(
	chart: Dictionary,
	difficulty_id: String
) -> Dictionary:
	var difficulties_value: Variant = chart.get("difficulties")

	if difficulties_value is Dictionary:
		var difficulty_map: Dictionary = difficulties_value

		if not difficulty_map.has(difficulty_id):
			push_error(
				"Chart difficulty not found: " + difficulty_id
			)
			return {}

		var difficulty_value: Variant = difficulty_map[difficulty_id]

		if not difficulty_value is Dictionary:
			push_error("Invalid chart difficulty: " + difficulty_id)
			return {}

		return difficulty_value

	push_error("The chart contains no notes.")
	return {}


func _difficulty_precedes(left: String, right: String) -> bool:
	var left_rank: int = DIFFICULTY_ORDER.find(left)
	var right_rank: int = DIFFICULTY_ORDER.find(right)

	if left_rank == -1:
		left_rank = DIFFICULTY_ORDER.size()
	if right_rank == -1:
		right_rank = DIFFICULTY_ORDER.size()
	if left_rank == right_rank:
		return left < right

	return left_rank < right_rank


func create_note(note_data: Dictionary, note_parent: Node) -> void:
	var note_type: String = str(note_data.get("type", ""))
	var note: Node2D
	var slide_path: Array[Dictionary] = []

	if note_type == "slide":
		if not note_data.has("release_required"):
			push_warning(
				"Slide invalide : release_required est obligatoire."
			)
			return
		slide_path = _get_slide_path(note_data)
		if slide_path.size() < 2:
			return

	match note_type:
		"tap":
			note = TAP_NOTE_SCENE.instantiate() as Node2D

		"hold":
			note = HOLD_NOTE_SCENE.instantiate() as Node2D

		"flick":
			note = FLICK_NOTE_SCENE.instantiate() as Node2D

		"slide":
			note = SLIDE_NOTE_SCENE.instantiate() as Node2D

		_:
			push_warning("Type de note non supporté : " + note_type)
			return

	if note == null:
		push_error("Impossible de créer la note : " + note_type)
		return

	var hit_time: float = (
		float(slide_path[0]["time"])
		if note_type == "slide"
		else float(note_data.get("time", 0.0))
	)
	var note_x: float = (
		float(slide_path[0]["x"])
		if note_type == "slide"
		else float(note_data.get("x", 0.5))
	)
	note.set("hit_time", hit_time)
	note.set("note_x", note_x)
	note.set("note_width", float(note_data.get("width", 0.2)))

	if note_type == "hold":
		if not note_data.has("release_required"):
			push_warning(
				"Hold invalide : release_required est obligatoire."
			)
			note.free()
			return
		if not _configure_sustained_note(
			note,
			note_data,
			hit_time,
			note_type
		):
			return
		note.set(
			"release_required",
			bool(note_data["release_required"])
		)

	if note_type == "flick":
		note.set(
			"flick_direction",
			str(note_data.get("direction", "up"))
		)
		note.set(
			"minimum_speed",
			float(note_data.get("min_speed", 650.0))
		)

	if note_type == "slide":
		var last_point: Dictionary = slide_path[-1]
		note.set("end_time", float(last_point["time"]))
		note.set("end_x", float(last_point["x"]))
		note.call(
			"configure_path",
			slide_path,
			str(note_data.get("interpolation", "linear")),
			bool(note_data["release_required"])
		)

	note_parent.add_child(note)


func _get_slide_path(note_data: Dictionary) -> Array[Dictionary]:
	var raw_path_value: Variant = note_data.get("path")
	if not raw_path_value is Array:
		push_warning("Slide invalide : le nouveau format path est obligatoire.")
		return []
	var raw_path: Array = raw_path_value

	if raw_path.size() < 2:
		push_warning("Slide invalide : path doit contenir au moins 2 points.")
		return []

	var normalized: Array[Dictionary] = []
	var previous_time: float = -INF
	for raw_point: Variant in raw_path:
		if not raw_point is Dictionary:
			push_warning("Slide invalide : chaque point doit être un objet.")
			return []

		var point: Dictionary = raw_point
		if not point.has("time") or not point.has("x"):
			push_warning("Slide invalide : un point n'a pas time ou x.")
			return []

		var point_time: float = float(point["time"])
		var point_x: float = float(point["x"])
		if not is_finite(point_time) or not is_finite(point_x):
			push_warning("Slide invalide : time et x doivent être finis.")
			return []
		if point_time <= previous_time:
			push_warning(
				"Slide invalide : les temps du path doivent être croissants."
			)
			return []

		normalized.append({
			"time": point_time,
			"x": clampf(point_x, 0.0, 1.0),
		})
		previous_time = point_time

	return normalized


func _configure_sustained_note(
	note: Node2D,
	note_data: Dictionary,
	hit_time: float,
	note_type: String
) -> bool:
	var duration: float = float(
		note_data.get("duration", 0.0)
	)
	var end_time: float = float(
		note_data.get(
			"end_time",
			hit_time + duration
		)
	)

	if end_time <= hit_time:
		push_warning(
			note_type.capitalize()
			+ " invalide : end_time doit être après time."
		)
		note.free()
		return false

	note.set("end_time", end_time)
	return true
