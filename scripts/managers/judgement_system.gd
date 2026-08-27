extends Node

signal judgement_made(result: String, error: float)

const PERFECT_WINDOW: float = 0.040
const GREAT_WINDOW: float = 0.080
const GOOD_WINDOW: float = 0.120
const BAD_WINDOW: float = 0.160


func get_judgement(
	error: float,
	bad_window: float = BAD_WINDOW
) -> String:
	var absolute_error: float = abs(error)

	if absolute_error <= PERFECT_WINDOW:
		return "PERFECT"

	if absolute_error <= GREAT_WINDOW:
		return "GREAT"

	if absolute_error <= GOOD_WINDOW:
		return "GOOD"

	if absolute_error <= bad_window:
		return "BAD"

	return "MISS"


func is_inside_hit_window(
	error: float,
	bad_window: float = BAD_WINDOW
) -> bool:
	return abs(error) <= bad_window


func get_worst_judgement(first: String, second: String) -> String:
	const JUDGEMENT_RANK: Dictionary = {
		"PERFECT": 0,
		"GREAT": 1,
		"GOOD": 2,
		"BAD": 3,
		"MISS": 4,
	}
	return (
		second
		if int(JUDGEMENT_RANK.get(second, 4))
		> int(JUDGEMENT_RANK.get(first, 4))
		else first
	)

func announce_judgement(result: String, error: float) -> void:
	judgement_made.emit(result, error)
