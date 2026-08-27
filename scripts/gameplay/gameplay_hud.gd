extends CanvasLayer

@onready var score_label: Label = $Root/ScoreLabel
@onready var grade_label: Label = $Root/GradeLabel
@onready var combo_label: Label = $Root/ComboLabel
@onready var judgement_label: Label = $Root/JudgementLabel
@onready var life_bar: ProgressBar = $Root/LifeBar
@onready var recovery_label: Label = $Root/RecoveryLabel
@onready var judgement_timer: Timer = $Root/JudgementTimer

var judgement_tween: Tween
var combo_tween: Tween


func _ready() -> void:
	ScoreManager.score_changed.connect(_on_score_changed)
	LifeManager.life_changed.connect(_on_life_changed)
	JudgementSystem.judgement_made.connect(_on_judgement_made)
	judgement_timer.timeout.connect(_on_judgement_timer_timeout)

	get_viewport().size_changed.connect(_update_layout)

	_refresh()

	judgement_label.visible = false

	# On attend une frame pour être sûr que Godot connaît
	# correctement la taille des Labels.
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_update_layout()


func _refresh() -> void:
	score_label.text = "SCORE %d" % ScoreManager.score
	_update_grade()
	combo_label.text = "COMBO %d" % ScoreManager.combo
	life_bar.value = LifeManager.life
	_update_recovery_multiplier()


func _update_layout() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size

	var margin_x: float = screen.x * 0.03
	var margin_y: float = screen.y * 0.04

	# -------------------------
	# SCORE : haut gauche
	# -------------------------

	score_label.position = Vector2(
		margin_x,
		margin_y
	)
	grade_label.position = Vector2(
		margin_x + score_label.get_combined_minimum_size().x + 28.0,
		margin_y - screen.y * 0.025
	)

	# -------------------------
	# LIFE : haut droite
	# -------------------------

	var life_width: float = screen.x * 0.28
	var life_height: float = screen.y * 0.045

	life_bar.size = Vector2(
		life_width,
		life_height
	)

	life_bar.position = Vector2(
		screen.x - life_width - margin_x,
		margin_y
	)
	recovery_label.position = Vector2(
		screen.x - life_width - margin_x,
		margin_y + life_height + 8.0
	)
	recovery_label.size.x = life_width

	# -------------------------
	# JUGEMENT : centre
	# -------------------------

	var judgement_size: Vector2 = judgement_label.get_combined_minimum_size()

	judgement_label.position = Vector2(
		(screen.x - judgement_size.x) * 0.5,
		screen.y * 0.52
	)

	# -------------------------
	# COMBO : sous le jugement
	# -------------------------

	var combo_size: Vector2 = combo_label.get_combined_minimum_size()

	combo_label.position = Vector2(
		(screen.x - combo_size.x) * 0.5,
		screen.y * 0.62
	)

func _on_score_changed(
	new_score: int,
	new_combo: int,
	_max_combo: int,
	_new_accuracy: float
) -> void:
	score_label.text = "SCORE %d" % new_score
	_update_grade()
	combo_label.text = "COMBO %d" % new_combo
	_update_recovery_multiplier()

	_update_layout()

	if new_combo > 0:
		_animate_combo()


func _update_grade() -> void:
	var grade: String = ScoreManager.get_grade()
	grade_label.text = grade
	grade_label.add_theme_color_override(
		"font_color",
		ScoreGrade.grade_color(grade)
	)


func _on_life_changed(new_life: float) -> void:
	life_bar.value = new_life


func _update_recovery_multiplier() -> void:
	var multiplier: int = LifeManager.get_recovery_multiplier()
	recovery_label.visible = multiplier > 0
	recovery_label.text = "RECOVERY ×%d" % multiplier


func _on_judgement_made(result: String, _error: float) -> void:
	judgement_label.text = result
	judgement_label.visible = true

	_update_layout()
	_animate_judgement(result)

	judgement_timer.start(0.55)


func _on_judgement_timer_timeout() -> void:
	if judgement_tween != null and judgement_tween.is_valid():
		judgement_tween.kill()

	judgement_tween = create_tween().set_parallel(true)
	judgement_tween.set_trans(Tween.TRANS_QUAD)
	judgement_tween.set_ease(Tween.EASE_IN)
	judgement_tween.tween_property(
		judgement_label,
		"modulate:a",
		0.0,
		0.16
	)
	judgement_tween.tween_property(
		judgement_label,
		"scale",
		Vector2.ONE * 1.08,
		0.16
	)
	judgement_tween.finished.connect(_hide_judgement_after_fade)


func _animate_judgement(result: String) -> void:
	if judgement_tween != null and judgement_tween.is_valid():
		judgement_tween.kill()

	var color: Color = _get_judgement_color(result)
	color.a = 0.25
	judgement_label.modulate = color
	judgement_label.scale = Vector2.ONE * 0.58
	judgement_label.pivot_offset = judgement_label.size / 2.0

	judgement_tween = create_tween().set_parallel(true)
	judgement_tween.set_trans(Tween.TRANS_BACK)
	judgement_tween.set_ease(Tween.EASE_OUT)
	judgement_tween.tween_property(
		judgement_label,
		"scale",
		Vector2.ONE,
		0.18
	)
	judgement_tween.tween_property(
		judgement_label,
		"modulate:a",
		1.0,
		0.10
	)


func _animate_combo() -> void:
	if combo_tween != null and combo_tween.is_valid():
		combo_tween.kill()

	combo_label.pivot_offset = combo_label.size / 2.0
	combo_label.scale = Vector2.ONE * 1.18
	combo_tween = create_tween()
	combo_tween.set_trans(Tween.TRANS_BACK)
	combo_tween.set_ease(Tween.EASE_OUT)
	combo_tween.tween_property(
		combo_label,
		"scale",
		Vector2.ONE,
		0.17
	)


func _hide_judgement_after_fade() -> void:
	if judgement_timer.is_stopped():
		judgement_label.visible = false


func _get_judgement_color(result: String) -> Color:
	match result:
		"PERFECT":
			return Color(0.58, 0.95, 1.0)
		"GREAT":
			return Color(0.48, 1.0, 0.66)
		"GOOD":
			return Color(1.0, 0.88, 0.36)
		"BAD":
			return Color(1.0, 0.48, 0.24)
		_:
			return Color(1.0, 0.38, 0.42)
