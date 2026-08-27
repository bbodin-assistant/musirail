extends Node

signal life_changed(life: float)
signal life_depleted

const MAX_LIFE: float = 100.0
const MISS_DAMAGE: float = 4.0
const BAD_DAMAGE: float = 1.5
const COMBO_NOTES_PER_MULTIPLIER: int = 10
const MAX_RECOVERY_MULTIPLIER: int = 5
const RECOVERY_PER_MULTIPLIER: float = 0.30

var life: float = MAX_LIFE


func reset() -> void:
	life = MAX_LIFE
	life_changed.emit(life)


func register_judgement(result: String) -> void:
	match result:
		"BAD":
			change_life(-BAD_DAMAGE)
			return

		"MISS":
			change_life(-MISS_DAMAGE)
			return

	var multiplier: int = get_recovery_multiplier()
	if multiplier > 0:
		change_life(RECOVERY_PER_MULTIPLIER * multiplier)


func get_recovery_multiplier() -> int:
	return clampi(
		floori(
			float(ScoreManager.combo) / float(COMBO_NOTES_PER_MULTIPLIER)
		),
		0,
		MAX_RECOVERY_MULTIPLIER
	)


func is_cleared() -> bool:
	return life > 0.0


func change_life(amount: float) -> void:
	life = clamp(
		life + amount,
		0.0,
		MAX_LIFE
	)

	life_changed.emit(life)

	if life <= 0.0:
		life_depleted.emit()
