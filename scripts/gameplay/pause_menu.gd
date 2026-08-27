class_name GameplayPauseMenu
extends CanvasLayer

signal pause_requested
signal resume_ready
signal restart_requested
signal quit_requested

enum ConfirmationAction {
	NONE,
	RESTART,
	QUIT
}

const COUNTDOWN_STEP_SECONDS: float = 0.65
const GO_DISPLAY_SECONDS: float = 0.35

@onready var pause_button: Button = $Root/PauseButton
@onready var overlay: ColorRect = $Root/Overlay
@onready var menu_panel: VBoxContainer = (
	$Root/Overlay/Center/MenuPanel
)
@onready var resume_button: Button = (
	$Root/Overlay/Center/MenuPanel/ResumeButton
)
@onready var restart_button: Button = (
	$Root/Overlay/Center/MenuPanel/RestartButton
)
@onready var quit_button: Button = (
	$Root/Overlay/Center/MenuPanel/QuitButton
)
@onready var confirmation_panel: VBoxContainer = (
	$Root/Overlay/Center/ConfirmationPanel
)
@onready var confirmation_label: Label = (
	$Root/Overlay/Center/ConfirmationPanel/ConfirmationLabel
)
@onready var cancel_button: Button = (
	$Root/Overlay/Center/ConfirmationPanel/Actions/CancelButton
)
@onready var confirm_button: Button = (
	$Root/Overlay/Center/ConfirmationPanel/Actions/ConfirmButton
)
@onready var countdown_label: Label = $Root/Overlay/CountdownLabel

var pause_available: bool = true
var paused: bool = false
var countdown_running: bool = false
var pending_action: ConfirmationAction = ConfirmationAction.NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false
	confirmation_panel.visible = false
	countdown_label.visible = false
	get_tree().root.go_back_requested.connect(_handle_back_request)

	pause_button.pressed.connect(_on_pause_button_pressed)
	resume_button.pressed.connect(_on_resume_button_pressed)
	restart_button.pressed.connect(_show_restart_confirmation)
	quit_button.pressed.connect(_show_quit_confirmation)
	cancel_button.pressed.connect(_cancel_confirmation)
	confirm_button.pressed.connect(_confirm_action)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	get_viewport().set_input_as_handled()
	_handle_back_request()


func show_paused() -> void:
	paused = true
	pause_button.visible = false
	overlay.visible = true
	menu_panel.visible = true
	confirmation_panel.visible = false
	countdown_label.visible = false
	pending_action = ConfirmationAction.NONE
	resume_button.grab_focus()


func set_pause_available(available: bool) -> void:
	pause_available = available
	pause_button.visible = available and not paused


func _handle_back_request() -> void:
	if countdown_running:
		return

	if confirmation_panel.visible:
		_cancel_confirmation()
	elif paused:
		_on_resume_button_pressed()
	elif pause_available:
		pause_requested.emit()


func _on_pause_button_pressed() -> void:
	if pause_available and not paused:
		pause_requested.emit()


func _on_resume_button_pressed() -> void:
	if not paused or countdown_running:
		return

	_start_resume_countdown()


func _start_resume_countdown() -> void:
	countdown_running = true
	menu_panel.visible = false
	confirmation_panel.visible = false
	countdown_label.visible = true

	for count: int in range(3, 0, -1):
		countdown_label.text = str(count)
		await get_tree().create_timer(
			COUNTDOWN_STEP_SECONDS,
			true
		).timeout

	countdown_label.text = "GO!"
	await get_tree().create_timer(
		GO_DISPLAY_SECONDS,
		true
	).timeout

	countdown_label.visible = false
	overlay.visible = false
	countdown_running = false
	paused = false
	pause_button.visible = pause_available
	resume_ready.emit()


func _show_restart_confirmation() -> void:
	_show_confirmation(
		ConfirmationAction.RESTART,
		"Restart this song?\nYour current score will be lost.",
		"RESTART"
	)


func _show_quit_confirmation() -> void:
	_show_confirmation(
		ConfirmationAction.QUIT,
		"Quit to song selection?\nYour current score will be lost.",
		"QUIT"
	)


func _show_confirmation(
	action: ConfirmationAction,
	message: String,
	confirm_text: String
) -> void:
	pending_action = action
	confirmation_label.text = message
	confirm_button.text = confirm_text
	menu_panel.visible = false
	confirmation_panel.visible = true
	cancel_button.grab_focus()


func _cancel_confirmation() -> void:
	pending_action = ConfirmationAction.NONE
	confirmation_panel.visible = false
	menu_panel.visible = true
	resume_button.grab_focus()


func _confirm_action() -> void:
	match pending_action:
		ConfirmationAction.RESTART:
			restart_requested.emit()

		ConfirmationAction.QUIT:
			quit_requested.emit()

		_:
			_cancel_confirmation()
