extends CanvasLayer
class_name PauseMenu

## Pause menu UI - appears when player presses ESC during gameplay

@onready var blur_background: ColorRect = $BlurBackground
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Title
@onready var resume_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/ResumeButton
@onready var save_game_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/SaveGameButton
@onready var load_game_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/LoadGameButton
@onready var shop_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/ShopButton
@onready var settings_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/SettingsButton
@onready var main_menu_button: Button = $Panel/MarginContainer/VBoxContainer/Buttons/MainMenuButton

var game_manager: GameManager
var settings_menu: Node  # SettingsMenu - avoid circular dependency
var shop_ui: ShopUI
var is_paused: bool = false
var currently_focused_button: Button = null

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
	if save_game_button:
		save_game_button.pressed.connect(_on_save_game_pressed)
	if load_game_button:
		load_game_button.pressed.connect(_on_load_game_pressed)
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)

	# Connect hover and focus animations
	for button in [resume_button, save_game_button, load_game_button, shop_button, settings_button, main_menu_button]:
		if button:
			button.mouse_entered.connect(_on_button_hover.bind(button))
			button.mouse_exited.connect(_on_button_unhover.bind(button))
			button.focus_entered.connect(_on_button_focus_entered.bind(button))
			button.focus_exited.connect(_on_button_focus_exited.bind(button))

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

	# Hide pause menu temporarily (including blur)
	blur_background.visible = false
	panel.visible = false
	shop_ui.show_shop()

func _on_save_game_pressed() -> void:
	"""Open the save game menu."""
	print("[PAUSE_MENU] Save Game button pressed")

	# Load the SaveGameMenu scene
	var save_menu_scene := preload("res://src/ui/scenes/SaveGameMenu.tscn")
	var save_menu := save_menu_scene.instantiate()

	# Connect signals
	save_menu.back_pressed.connect(_on_save_menu_back_pressed.bind(save_menu))
	save_menu.game_saved.connect(_on_game_saved)

	# Hide pause menu temporarily (including blur)
	blur_background.visible = false
	panel.visible = false

	# Add save menu to tree
	add_child(save_menu)

func _on_settings_pressed() -> void:
	"""Open the settings menu."""
	if not settings_menu:
		settings_menu = get_tree().get_first_node_in_group("settings_menu")
		if not settings_menu:
			push_warning("SettingsMenu not found")
			return

	# Hide pause menu temporarily (including blur)
	# IMPORTANT: Don't unpause the game, just hide the menu
	blur_background.visible = false
	panel.visible = false
	settings_menu.show_settings(self)

func _on_main_menu_pressed() -> void:
	"""Return to main menu."""
	print("[PAUSE_MENU] Returning to main menu...")

	# Hide pause menu
	hide_pause_menu()

	# Reset game state to MENU
	if game_manager:
		game_manager.current_state = GameManager.GameState.MENU
		game_manager.resume_game()  # Unpause the tree

	# Find and show the main menu
	var main_menu = get_tree().get_first_node_in_group("main_menu")
	if main_menu and main_menu.has_method("show_main_menu"):
		main_menu.show_main_menu()
	else:
		push_warning("[PAUSE_MENU] Main menu not found!")

func _on_load_game_pressed() -> void:
	"""Open the load game menu."""
	print("[PAUSE_MENU] Load Game button pressed")

	# Load the LoadGameMenu scene
	var load_menu_scene := preload("res://src/ui/scenes/LoadGameMenu.tscn")
	var load_menu := load_menu_scene.instantiate()

	# Connect signals
	load_menu.back_pressed.connect(_on_load_menu_back_pressed.bind(load_menu))

	# Hide pause menu temporarily (including blur)
	blur_background.visible = false
	panel.visible = false

	# Add load menu to tree
	add_child(load_menu)

func on_settings_closed() -> void:
	"""Called when settings menu is closed."""
	# Show pause menu again (including blur)
	blur_background.visible = true
	panel.visible = true
	if resume_button:
		resume_button.grab_focus()

func _on_save_menu_back_pressed(save_menu: Control) -> void:
	"""Called when save menu back button is pressed."""
	# Show pause menu again (including blur)
	blur_background.visible = true
	panel.visible = true
	if save_game_button:
		save_game_button.grab_focus()

func _on_load_menu_back_pressed(load_menu: Control) -> void:
	"""Called when load menu back button is pressed."""
	# Show pause menu again (including blur)
	blur_background.visible = true
	panel.visible = true
	if load_game_button:
		load_game_button.grab_focus()

func _on_game_saved() -> void:
	"""Called when game is successfully saved."""
	print("[PAUSE_MENU] Game saved successfully!")

# ============================================================================
# BUTTON ANIMATION FUNCTIONS
# ============================================================================

func _on_button_hover(button: Button) -> void:
	"""Add scale effect on mouse hover."""
	# When mouse enters a button, transfer focus to it (for better UX)
	# This ensures keyboard focus follows mouse movement
	if button.has_method("grab_focus"):
		button.grab_focus()

	# Kill any existing scale tween
	if button.has_meta("scale_tween"):
		var old_tween = button.get_meta("scale_tween")
		if old_tween:
			old_tween.kill()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.3)
	button.set_meta("scale_tween", tween)

	# Also enlarge text inside button
	_enlarge_button_text(button)

func _on_button_unhover(button: Button) -> void:
	"""Reset scale when mouse leaves (only if not focused via keyboard)."""
	if button != currently_focused_button:
		# Kill any existing scale tween
		if button.has_meta("scale_tween"):
			var old_tween = button.get_meta("scale_tween")
			if old_tween:
				old_tween.kill()

		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.2)
		button.set_meta("scale_tween", tween)

		_reset_button_text(button)

func _on_button_focus_entered(button: Button) -> void:
	"""Keyboard/gamepad focus entered - prominent visual feedback."""
	currently_focused_button = button

	# Kill any existing scale tween
	if button.has_meta("scale_tween"):
		var old_tween = button.get_meta("scale_tween")
		if old_tween:
			old_tween.kill()

	# Scale button
	var tween_button = create_tween()
	tween_button.set_ease(Tween.EASE_OUT)
	tween_button.set_trans(Tween.TRANS_ELASTIC)
	tween_button.tween_property(button, "scale", Vector2(1.1, 1.1), 0.4)
	button.set_meta("scale_tween", tween_button)

	# Enlarge button text prominently
	_enlarge_button_text(button, 1.2)  # More prominent for keyboard focus

	# Add pulsing glow effect
	_start_button_pulse(button)

func _on_button_focus_exited(button: Button) -> void:
	"""Keyboard/gamepad focus lost - reset."""
	if currently_focused_button == button:
		currently_focused_button = null

	# Stop pulse and reset
	_stop_button_pulse(button)

	# Kill any existing scale tween
	if button.has_meta("scale_tween"):
		var old_tween = button.get_meta("scale_tween")
		if old_tween:
			old_tween.kill()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.3)
	button.set_meta("scale_tween", tween)

	_reset_button_text(button)

func _enlarge_button_text(button: Button, scale_factor: float = 1.15) -> void:
	"""Enlarge the text/label inside a button."""
	# Kill any existing text tween
	if button.has_meta("text_tween"):
		var old_tween = button.get_meta("text_tween")
		if old_tween:
			old_tween.kill()

	# Get original size based on button type
	# Resume button: 32px, others: 24px (from PauseMenu.tscn)
	var original_size = 32 if button == resume_button else 24
	var target_size = int(original_size * scale_factor)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "theme_override_font_sizes/font_size", target_size, 0.2)
	button.set_meta("text_tween", tween)

func _reset_button_text(button: Button) -> void:
	"""Reset button text to original size."""
	# Kill any existing text tween
	if button.has_meta("text_tween"):
		var old_tween = button.get_meta("text_tween")
		if old_tween:
			old_tween.kill()

	var original_size = 32 if button == resume_button else 24
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "theme_override_font_sizes/font_size", original_size, 0.15)
	button.set_meta("text_tween", tween)

func _start_button_pulse(button: Button) -> void:
	"""Start pulsing glow effect on focused button."""
	var tween = create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "modulate:a", 0.7, 0.8)
	tween.tween_property(button, "modulate:a", 1.0, 0.8)

	# Store tween reference for cleanup
	button.set_meta("pulse_tween", tween)

func _stop_button_pulse(button: Button) -> void:
	"""Stop pulsing effect."""
	if button.has_meta("pulse_tween"):
		var tween = button.get_meta("pulse_tween")
		if tween:
			tween.kill()
		button.remove_meta("pulse_tween")

	# Reset alpha
	button.modulate.a = 1.0
