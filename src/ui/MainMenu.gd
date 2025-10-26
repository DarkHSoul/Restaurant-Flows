extends CanvasLayer
class_name MainMenu

## Main menu UI - start screen before gameplay

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var subtitle_label: Label = $Panel/VBoxContainer/Subtitle
@onready var start_button: Button = $Panel/VBoxContainer/Buttons/StartButton
@onready var settings_button: Button = $Panel/VBoxContainer/Buttons/SettingsButton
@onready var credits_button: Button = $Panel/VBoxContainer/Buttons/CreditsButton
@onready var quit_button: Button = $Panel/VBoxContainer/Buttons/QuitButton

var game_manager: GameManager
var settings_menu: Node  # SettingsMenu - avoid circular dependency
var menu_visible: bool = true

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance

	# Find settings menu
	await get_tree().process_frame
	settings_menu = get_tree().get_first_node_in_group("settings_menu")

	# Connect buttons
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if credits_button:
		credits_button.pressed.connect(_on_credits_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# Show main menu by default at startup
	show_main_menu()

func show_main_menu() -> void:
	"""Show the main menu."""
	menu_visible = true
	visible = true

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Unpause the game
	get_tree().paused = false

	# Set game state to menu
	if game_manager:
		game_manager.current_state = GameManager.GameState.MENU

	# Focus start button
	if start_button:
		start_button.grab_focus()

func hide_main_menu() -> void:
	"""Hide the main menu."""
	menu_visible = false
	visible = false

	# Hide mouse cursor when entering gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_start_pressed() -> void:
	"""Start a new game."""
	hide_main_menu()

	# Start the game
	if game_manager:
		game_manager.start_game()

func _on_settings_pressed() -> void:
	"""Open settings menu."""
	if not settings_menu:
		settings_menu = get_tree().get_first_node_in_group("settings_menu")
		if not settings_menu:
			push_warning("SettingsMenu not found")
			return

	# Hide main menu temporarily
	panel.visible = false
	settings_menu.show_settings(self)

func _on_credits_pressed() -> void:
	"""Show credits."""
	# TODO: Implement credits screen
	print("Credits:")
	print("Game developed with Godot Engine")
	print("Claude Code assistance")

func _on_quit_pressed() -> void:
	"""Quit the game."""
	get_tree().quit()

func on_settings_closed() -> void:
	"""Called when settings menu is closed."""
	panel.visible = true
	if start_button:
		start_button.grab_focus()
