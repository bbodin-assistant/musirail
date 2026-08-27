class_name ScoreGrade
extends RefCounted

const PERFECT_POINTS: int = 1000
const GREAT_POINTS: int = 800
const GOOD_POINTS: int = 500
const BAD_POINTS: int = 200
const SUSTAIN_TICK_INTERVAL_SECONDS: float = 0.20
const SUSTAIN_TICK_POINTS: int = 100

const GRADE_ORDER: Array[String] = ["F", "E", "D", "C", "B", "A", "S"]
const GRADE_THRESHOLDS: Dictionary = {
	"F": 0.00,
	"E": 0.30,
	"D": 0.50,
	"C": 0.65,
	"B": 0.75,
	"A": 0.85,
	"S": 0.95,
}


static func maximum_score_for_notes(notes: Array) -> int:
	var maximum_score: int = 0
	for note_value: Variant in notes:
		if not note_value is Dictionary:
			continue
		var note: Dictionary = note_value
		maximum_score += PERFECT_POINTS
		var duration: float = _sustain_duration(note)
		if duration <= 0.0:
			continue
		var tick_count: int = int(floor(
			(duration + 0.000001) / SUSTAIN_TICK_INTERVAL_SECONDS
		))
		maximum_score += tick_count * SUSTAIN_TICK_POINTS
	return maximum_score


static func grade_for_score(score: int, maximum_score: int) -> String:
	if maximum_score <= 0:
		return "F"
	var ratio: float = clampf(
		float(maxi(0, score)) / float(maximum_score),
		0.0,
		1.0
	)
	var grade: String = "F"
	for candidate: String in GRADE_ORDER:
		if ratio >= float(GRADE_THRESHOLDS[candidate]):
			grade = candidate
	return grade


static func grade_rank(grade: String) -> int:
	return maxi(0, GRADE_ORDER.find(grade))


static func grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color(1.0, 0.78, 0.25, 1.0)
		"A":
			return Color(0.45, 0.92, 1.0, 1.0)
		"B":
			return Color(0.45, 1.0, 0.62, 1.0)
		"C":
			return Color(0.95, 0.92, 0.38, 1.0)
		"D":
			return Color(1.0, 0.66, 0.28, 1.0)
		"E":
			return Color(1.0, 0.46, 0.30, 1.0)
		_:
			return Color(0.72, 0.40, 0.46, 1.0)


static func _sustain_duration(note: Dictionary) -> float:
	var note_type: String = str(note.get("type", ""))
	if note_type == "hold":
		return maxf(
			float(note.get("end_time", 0.0))
			- float(note.get("time", 0.0)),
			0.0
		)
	if note_type == "slide":
		var path_value: Variant = note.get("path", [])
		if not path_value is Array:
			return 0.0
		var path: Array = path_value
		if path.size() < 2:
			return 0.0
		var first_value: Variant = path[0]
		var last_value: Variant = path[-1]
		if not first_value is Dictionary or not last_value is Dictionary:
			return 0.0
		return maxf(
			float(last_value.get("time", 0.0))
			- float(first_value.get("time", 0.0)),
			0.0
		)
	return 0.0
