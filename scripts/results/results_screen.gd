class_name ResultsScreen
extends CanvasLayer

signal restart_requested
signal return_requested

@onready var overlay: ColorRect = $Overlay
@onready var song_label: Label = (
	$Overlay/Center/Panel/Margin/Content/SongLabel
)
@onready var achievement_label: Label = (
	$Overlay/Center/Panel/Margin/Content/AchievementLabel
)
@onready var new_best_label: Label = (
	$Overlay/Center/Panel/Margin/Content/NewBestLabel
)
@onready var score_label: Label = (
	$Overlay/Center/Panel/Margin/Content/ScoreRow/Score
)
@onready var best_score_label: Label = (
	$Overlay/Center/Panel/Margin/Content/ScoreRow/BestScore
)
@onready var accuracy_label: Label = (
	$Overlay/Center/Panel/Margin/Content/StatsRow/Accuracy
)
@onready var max_combo_label: Label = (
	$Overlay/Center/Panel/Margin/Content/StatsRow/MaxCombo
)
@onready var perfect_count: Label = (
	$Overlay/Center/Panel/Margin/Content/Judgements/Perfect/Count
)
@onready var great_count: Label = (
	$Overlay/Center/Panel/Margin/Content/Judgements/Great/Count
)
@onready var good_count: Label = (
	$Overlay/Center/Panel/Margin/Content/Judgements/Good/Count
)
@onready var bad_count: Label = (
	$Overlay/Center/Panel/Margin/Content/Judgements/Bad/Count
)
@onready var miss_count: Label = (
	$Overlay/Center/Panel/Margin/Content/Judgements/Miss/Count
)
@onready var restart_button: Button = (
	$Overlay/Center/Panel/Margin/Content/Actions/RestartButton
)
@onready var return_button: Button = (
	$Overlay/Center/Panel/Margin/Content/Actions/ReturnButton
)


func _ready() -> void:
	overlay.visible = false
	restart_button.pressed.connect(restart_requested.emit)
	return_button.pressed.connect(return_requested.emit)
	get_tree().root.go_back_requested.connect(_on_go_back_requested)


func _unhandled_input(event: InputEvent) -> void:
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return_requested.emit()


func show_results(
	song: Dictionary,
	summary: Dictionary,
	best_score: int,
	is_new_best: bool
) -> void:
	var title: String = str(song.get("title", "Unknown Song"))
	var difficulty: String = str(song.get("difficulty", "Normal"))
	song_label.text = "%s  •  %s" % [title, difficulty]

	var achievement: String = str(summary["achievement"])
	achievement_label.text = achievement
	achievement_label.add_theme_color_override(
		"font_color",
		_get_achievement_color(achievement)
	)
	new_best_label.visible = is_new_best

	score_label.text = "SCORE  %09d" % int(summary["score"])
	best_score_label.text = "BEST  %09d" % best_score
	accuracy_label.text = "ACCURACY  %.2f%%" % float(summary["accuracy"])
	max_combo_label.text = "MAX COMBO  %d" % int(summary["max_combo"])

	var counts: Dictionary = summary["judgements"]
	perfect_count.text = str(int(counts["perfect"]))
	great_count.text = str(int(counts["great"]))
	good_count.text = str(int(counts["good"]))
	bad_count.text = str(int(counts["bad"]))
	miss_count.text = str(int(counts["miss"]))

	overlay.visible = true
	restart_button.grab_focus()


func is_showing() -> bool:
	return overlay.visible


func _on_go_back_requested() -> void:
	if overlay.visible:
		return_requested.emit()


func _get_achievement_color(achievement: String) -> Color:
	match achievement:
		"FAILED":
			return Color(1.0, 0.38, 0.42)
		"ALL PERFECT":
			return Color(0.58, 0.95, 1.0)
		"FULL COMBO":
			return Color(1.0, 0.88, 0.36)
		_:
			return Color(0.62, 1.0, 0.72)
