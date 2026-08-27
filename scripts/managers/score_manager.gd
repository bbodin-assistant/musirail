extends Node

const SUSTAIN_TICK_INTERVAL_SECONDS: float = (
	ScoreGrade.SUSTAIN_TICK_INTERVAL_SECONDS
)
const SUSTAIN_TICK_POINTS: int = ScoreGrade.SUSTAIN_TICK_POINTS

signal score_changed(
	score: int,
	combo: int,
	max_combo: int,
	accuracy: float
)

var score: int = 0
var combo: int = 0
var max_combo: int = 0

var perfect_count: int = 0
var great_count: int = 0
var good_count: int = 0
var bad_count: int = 0
var miss_count: int = 0

var total_accuracy_points: float = 0.0
var total_judged_notes: int = 0
var maximum_score: int = 0


func reset() -> void:
	score = 0
	combo = 0
	max_combo = 0

	perfect_count = 0
	great_count = 0
	good_count = 0
	bad_count = 0
	miss_count = 0

	total_accuracy_points = 0.0
	total_judged_notes = 0
	maximum_score = 0

	_emit_score_changed()


func register_judgement(result: String) -> void:
	total_judged_notes += 1

	match result:
		"PERFECT":
			score += ScoreGrade.PERFECT_POINTS
			total_accuracy_points += 1.0
			perfect_count += 1
			_add_combo()

		"GREAT":
			score += ScoreGrade.GREAT_POINTS
			total_accuracy_points += 0.8
			great_count += 1
			_add_combo()

		"GOOD":
			score += ScoreGrade.GOOD_POINTS
			total_accuracy_points += 0.5
			good_count += 1
			_add_combo()

		"BAD":
			score += ScoreGrade.BAD_POINTS
			total_accuracy_points += 0.2
			bad_count += 1
			combo = 0

		"MISS":
			miss_count += 1
			combo = 0

	_emit_score_changed()


func register_sustain_tick() -> void:
	score += SUSTAIN_TICK_POINTS
	_emit_score_changed()


func set_maximum_score(value: int) -> void:
	maximum_score = maxi(0, value)
	_emit_score_changed()


func get_grade() -> String:
	return ScoreGrade.grade_for_score(score, maximum_score)


func _add_combo() -> void:
	combo += 1

	if combo > max_combo:
		max_combo = combo


func get_accuracy() -> float:
	if total_judged_notes == 0:
		return 100.0

	return (
		total_accuracy_points
		/ float(total_judged_notes)
	) * 100.0


func get_result_summary() -> Dictionary:
	return {
		"score": score,
		"maximum_score": maximum_score,
		"grade": get_grade(),
		"accuracy": get_accuracy(),
		"max_combo": max_combo,
		"achievement": _get_achievement(),
		"judgements": {
			"perfect": perfect_count,
			"great": great_count,
			"good": good_count,
			"bad": bad_count,
			"miss": miss_count,
		},
	}


func _get_achievement() -> String:
	if total_judged_notes > 0 and perfect_count == total_judged_notes:
		return "ALL PERFECT"

	if total_judged_notes > 0 and bad_count == 0 and miss_count == 0:
		return "FULL COMBO"

	return "CLEARED"


func _emit_score_changed() -> void:
	score_changed.emit(
		score,
		combo,
		max_combo,
		get_accuracy()
	)
