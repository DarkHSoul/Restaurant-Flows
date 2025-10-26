extends CanvasLayer
class_name PauseMenu

## Pause menu UI - appears when player presses ESC during gameplay

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var resume_button: Button = $Panel/VBoxContainer/Buttons/ResumeButton
@onready var shop_button: Button = $Panel/VBoxContainer/Buttons/ShopButton
@onready var settings_button: Button = $Panel/VBoxContainer/Buttons/SettingsButton
@onready var main_menu_button: Button = $Panel/VBoxContainer/Buttons/MainMenuButton
@onready var quit_button: Button = $Panel/VBoxContainer/Buttons/QuitButton

var game_manager: GameManager
var settings_menu: Node  # SettingsMenu - avoid circular dependency
var shop_ui: ShopUI
var is_paused: bool = false

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance

	# Find settings menu and shop UI
	await get_tree().process_frame
	settings_menu = get_tree().get_first_node_in_group("settings_menu")
	shop_ui = get_tree().get_first_node_in_group("shop_ui") as ShopUI

	# Connect buttons
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# Start hidden
	hide_pause_menu()

func _input(event: InputEvent) -> void:
	# Only handle ESC if no other menu is open
	if event.is_action_pressed("ui_cancel"):
		if settings_menu and settings_menu.is_open:
			# Let settings menu handle it
			return

		if shop_ui and shop_ui.is_open:
			# Let shop UI handle it
			return

		if is_paused:
			_on_resume_pressed()
		else:
			# Only show pause menu if game is playing
			if game_manager and game_manager.current_state == GameManager.GameState.PLAYING:
				show_pause_menu()

		get_viewport().set_input_as_handled()

func show_pause_menu() -> void:
	"""Show the pause menu and pause the game."""
	if not game_manager:
		return

	is_paused = true
	visible = true

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Pause the game
	if game_manager.current_state == GameManager.GameState.PLAYING:
		game_manager.pause_game()

	# Focus the resume button
	if resume_button:
		resume_button.grab_focus()

func hide_pause_menu() -> void:
	"""Hide the pause menu."""
	is_paused = false
	visible = false

	# Hide mouse cursor when returning to gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed() -> void:
	"""Resume the game."""
	hide_pause_menu()

	# Resume the game
	if game_manager and game_manager.current_state == GameManager.GameState.PAUSED:
		game_manager.resume_game()

func _on_shop_pressed() -> void:
	"""Open the shop menu."""
	if not shop_ui:
		shop_ui = get_tree().get_first_node_in_group("shop_ui") as ShopUI
		if not shop_ui:
			push_warning("ShopUI not found")
			return

	# Hide pause menu temporarily
	panel.visible = false
	shop_ui.show_shop()

func _on_settings_pressed() -> void:
	"""Open the settings menu."""
	if not settings_menu:
		settings_menu = get_tree().get_first_node_in_group("settings_menu")
		if not settings_menu:
			push_warning("SettingsMenu not found")
			return

	# Hide pause menu temporarily
	panel.visible = false
	settings_menu.show_settings(self)

func _on_main_menu_pressed() -> void:
	"""Return to main menu."""
	# TODO: Implement main menu transition
	# For now, just resume and show a message
	print("Main menu not yet implemented")
	_on_resume_pressed()

func _on_quit_pressed() -> void:
	"""Quit the game."""
	get_tree().quit()

func on_settings_closed() -> void:
	"""Called when settings menu is closed."""
	panel.visible = true
	if resume_button:
		resume_button.grab_focus()
