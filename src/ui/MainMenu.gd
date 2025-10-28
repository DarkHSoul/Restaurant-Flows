extends CanvasLayer
class_name MainMenu

## Main menu UI - start screen before gameplay with beautiful animated visuals

@onready var panel: Control = $Panel
@onready var title_label: Label = $Panel/CenterContainer/MenuContainer/TitleSection/Title
@onready var subtitle_label: Label = $Panel/CenterContainer/MenuContainer/TitleSection/Subtitle
@onready var tagline_label: Label = $Panel/CenterContainer/MenuContainer/TitleSection/Tagline
@onready var continue_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/ContinueButton
@onready var new_game_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/NewGameButton
@onready var load_game_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/LoadGameButton
@onready var settings_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/SettingsButton
@onready var credits_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/CreditsButton
@onready var quit_button: Button = $Panel/CenterContainer/MenuContainer/ButtonsPanel/Buttons/QuitButton
@onready var background_gradient: ColorRect = $BackgroundGradient
@onready var background_pattern: ColorRect = $BackgroundPattern
@onready var animation_timer: Timer = $AnimationTimer
@onready var falling_food_layer: Control = $FallingFoodLayer
@onready var floating_particles_layer: Control = $FloatingParticlesLayer

var game_manager: GameManager
var settings_menu: Node  # SettingsMenu - avoid circular dependency
var menu_visible: bool = true
var animation_time: float = 0.0
var currently_focused_button: Button = null

# Background color animation
var bg_colors: Array[Color] = [
	Color(0.15, 0.12, 0.1, 1),   # Original dark brown
	Color(0.18, 0.14, 0.11, 1),  # Slightly lighter
	Color(0.13, 0.10, 0.09, 1),  # Slightly darker
]
var current_bg_index: int = 0
var bg_transition_time: float = 0.0
var bg_transition_duration: float = 45.0  # 45 seconds per transition

# Text wave animation
var wave_time: float = 0.0

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance

	# Find settings menu
	await get_tree().process_frame
	settings_menu = get_tree().get_first_node_in_group("settings_menu")

	# Connect buttons (mouse + keyboard focus)
	_setup_button(continue_button)
	_setup_button(new_game_button)
	_setup_button(load_game_button)
	_setup_button(settings_button)
	_setup_button(credits_button)
	_setup_button(quit_button)

	# Connect animation timer
	if animation_timer:
		animation_timer.timeout.connect(_on_animation_tick)

	# Show main menu by default ONLY if game is in MENU state or no SaveManager flags are set
	# This prevents main menu from showing when loading a game or starting a new game
	if game_manager and game_manager.current_state == GameManager.GameState.MENU:
		# Check if we're loading a game or starting a new game
		if SaveManager.instance:
			if not SaveManager.instance.should_start_loaded_game and not SaveManager.instance.should_start_new_game:
				show_main_menu()
				# Animate title on start
				_animate_title_entrance()
			else:
				# Hide menu immediately - game will start automatically
				_hide_menu_immediately()
		else:
			# No SaveManager, show menu normally
			show_main_menu()
			# Animate title on start
			_animate_title_entrance()
	else:
		# Game is not in MENU state, hide menu
		_hide_menu_immediately()

func _hide_menu_immediately() -> void:
	"""Hide menu and all background layers immediately without animation."""
	visible = false
	menu_visible = false

	# Stop animation timer
	if animation_timer:
		animation_timer.stop()

	# Hide all background layers
	if falling_food_layer:
		falling_food_layer.visible = false
		var food_manager = falling_food_layer.get_node_or_null("FallingFoodManager")
		if food_manager and food_manager.has_method("set_visible"):
			food_manager.set_visible(false)

	if floating_particles_layer:
		floating_particles_layer.visible = false
		var sparkle_manager = floating_particles_layer.get_node_or_null("FloatingSparkles")
		if sparkle_manager and sparkle_manager.has_method("set_visible"):
			sparkle_manager.set_visible(false)

	if background_gradient:
		background_gradient.visible = false
	if background_pattern:
		background_pattern.visible = false

func _setup_button(button: Button) -> void:
	"""Setup button with all animations and event handlers."""
	if not button:
		return

	# Connect press events
	match button.name:
		"ContinueButton":
			button.pressed.connect(_on_continue_pressed)
		"NewGameButton":
			button.pressed.connect(_on_new_game_pressed)
		"LoadGameButton":
			button.pressed.connect(_on_load_game_pressed)
		"SettingsButton":
			button.pressed.connect(_on_settings_pressed)
		"CreditsButton":
			button.pressed.connect(_on_credits_pressed)
		"QuitButton":
			button.pressed.connect(_on_quit_pressed)

	# Connect hover and focus events
	button.mouse_entered.connect(_on_button_hover.bind(button))
	button.mouse_exited.connect(_on_button_unhover.bind(button))
	button.focus_entered.connect(_on_button_focus_entered.bind(button))
	button.focus_exited.connect(_on_button_focus_exited.bind(button))

func _on_animation_tick() -> void:
	"""Subtle background and text animations."""
	# Don't animate if menu is not visible
	if not visible or not menu_visible:
		return

	animation_time += 0.016
	wave_time += 0.016

	# Subtle pulsing effect on background pattern
	if background_pattern:
		var pulse = 0.05 + sin(animation_time * 0.5) * 0.02
		background_pattern.modulate.a = pulse

	# Subtle title glow effect
	if title_label:
		var glow = 0.8 + sin(animation_time * 2.0) * 0.2
		title_label.modulate = Color(1, 1, 1, glow)

	# Text wave animation (subtle vertical movement)
	if title_label:
		title_label.position.y = sin(wave_time * 0.8) * 3.0

	if subtitle_label:
		subtitle_label.position.y = sin(wave_time * 0.8 + 0.5) * 2.0

	# Background color transition
	_animate_background_color()

	# Parallax effect on title (subtle horizontal movement based on time)
	if title_label:
		var parallax_offset = sin(animation_time * 0.3) * 5.0
		title_label.position.x = parallax_offset * 1.5  # Foreground layer

	if subtitle_label:
		var parallax_offset = sin(animation_time * 0.3) * 5.0
		subtitle_label.position.x = parallax_offset * 1.0  # Mid layer

	if tagline_label:
		var parallax_offset = sin(animation_time * 0.3) * 5.0
		tagline_label.position.x = parallax_offset * 0.5  # Background layer

func _animate_background_color() -> void:
	"""Smoothly transition between background colors."""
	bg_transition_time += 0.016

	if bg_transition_time >= bg_transition_duration:
		# Move to next color
		current_bg_index = (current_bg_index + 1) % bg_colors.size()
		bg_transition_time = 0.0

	if background_gradient:
		# Calculate interpolation factor (0 to 1)
		var t = bg_transition_time / bg_transition_duration
		var next_index = (current_bg_index + 1) % bg_colors.size()

		# Smooth interpolation between colors
		background_gradient.color = bg_colors[current_bg_index].lerp(bg_colors[next_index], t)

func _animate_title_entrance() -> void:
	"""Animate title sliding in."""
	if title_label:
		title_label.modulate.a = 0.0
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(title_label, "modulate:a", 1.0, 0.8)

	if subtitle_label:
		subtitle_label.modulate.a = 0.0
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(subtitle_label, "modulate:a", 0.9, 0.6).set_delay(0.3)

	if tagline_label:
		tagline_label.modulate.a = 0.0
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(tagline_label, "modulate:a", 0.7, 0.5).set_delay(0.5)

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

	# Get original size first
	var original_size = 36 if button == continue_button else 28
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

	var original_size = 36 if button == continue_button else 28
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

func show_main_menu() -> void:
	"""Show the main menu."""
	menu_visible = true
	visible = true

	# Show background layers (food and sparkles)
	if falling_food_layer:
		falling_food_layer.visible = true
		# Also show all food labels inside
		var food_manager = falling_food_layer.get_node_or_null("FallingFoodManager")
		if food_manager and food_manager.has_method("set_visible"):
			food_manager.set_visible(true)

	if floating_particles_layer:
		floating_particles_layer.visible = true
		# Also show all sparkle labels inside
		var sparkle_manager = floating_particles_layer.get_node_or_null("FloatingSparkles")
		if sparkle_manager and sparkle_manager.has_method("set_visible"):
			sparkle_manager.set_visible(true)
	if background_gradient:
		background_gradient.visible = true
	if background_pattern:
		background_pattern.visible = true

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Unpause the game
	get_tree().paused = false

	# Set game state to menu
	if game_manager:
		game_manager.current_state = GameManager.GameState.MENU

	# Focus continue button
	if continue_button:
		continue_button.grab_focus()

	# Restart animations
	animation_time = 0.0
	wave_time = 0.0
	if animation_timer:
		animation_timer.start()

func hide_main_menu() -> void:
	"""Hide the main menu with curtain wipe animation."""
	menu_visible = false

	# Stop animation timer to freeze background animations
	if animation_timer:
		animation_timer.stop()

	# Hide background layers IMMEDIATELY
	if falling_food_layer:
		falling_food_layer.visible = false
		var food_manager = falling_food_layer.get_node_or_null("FallingFoodManager")
		if food_manager and food_manager.has_method("set_visible"):
			food_manager.set_visible(false)

	if floating_particles_layer:
		floating_particles_layer.visible = false
		var sparkle_manager = floating_particles_layer.get_node_or_null("FloatingSparkles")
		if sparkle_manager and sparkle_manager.has_method("set_visible"):
			sparkle_manager.set_visible(false)

	if background_gradient:
		background_gradient.visible = false
	if background_pattern:
		background_pattern.visible = false

	# Play curtain wipe animation
	await _animate_menu_exit()

	# Hide the entire MainMenu CanvasLayer after animation
	visible = false

	# Reset panel for next time
	if panel:
		panel.modulate.a = 1.0
		panel.position = Vector2.ZERO

	# Hide mouse cursor when entering gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _animate_menu_exit() -> void:
	"""Animate menu exit with curtain wipe effect."""
	if not panel:
		return

	# Create parallel tweens for smooth exit
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Slide panel up (curtain wipe effect)
	var screen_height = get_viewport().get_visible_rect().size.y
	tween.tween_property(panel, "position:y", -screen_height, 0.4)

	# Fade out simultaneously
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)

	# Wait for animation to complete
	await tween.finished

func _on_continue_pressed() -> void:
	"""Continue the last saved game."""
	print("[MAIN_MENU] Continue button pressed")

	if not SaveManager.instance:
		push_error("SaveManager not found!")
		return

	# Find most recent save
	var latest_slot := SaveManager.instance.get_latest_save_slot()

	if latest_slot < 1:
		print("[MAIN_MENU] No save found, showing warning")
		push_warning("No save data found! Starting new game instead.")
		_on_new_game_pressed()
		return

	# Load the game from latest slot
	print("[MAIN_MENU] Loading game from slot %d" % latest_slot)
	if SaveManager.instance.load_game(latest_slot):
		hide_main_menu()
		# Change scene to Main3D (GameManager will auto-start the loaded game)
		get_tree().change_scene_to_file("res://src/main/scenes/Main3D.tscn")
	else:
		push_error("Failed to load save from slot %d" % latest_slot)

func _on_new_game_pressed() -> void:
	"""Start a brand new game."""
	print("[MAIN_MENU] New Game button pressed")

	# Reset play time for new game and set flag to start new game
	if SaveManager.instance:
		SaveManager.instance.reset_play_time()
		SaveManager.instance.should_start_new_game = true
		SaveManager.instance.should_start_loaded_game = false  # Ensure NOT auto-starting a save
		SaveManager.instance._loaded_game_data.clear()  # Clear any cached load data

	hide_main_menu()

	# Change scene to Main3D - GameManager will start the game
	get_tree().change_scene_to_file("res://src/main/scenes/Main3D.tscn")

func _on_load_game_pressed() -> void:
	"""Load a saved game."""
	print("[MAIN_MENU] Load Game button pressed")

	# Load the LoadGameMenu scene
	var load_menu_scene := preload("res://src/ui/scenes/LoadGameMenu.tscn")
	var load_menu := load_menu_scene.instantiate()

	# Connect back button
	load_menu.back_pressed.connect(_on_load_menu_back_pressed.bind(load_menu))

	# Hide main menu panel
	panel.visible = false

	# Add load menu to tree
	add_child(load_menu)

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
	print("\n╔════════════════════════════════════════╗")
	print("║          RESTAURANT FLOWS              ║")
	print("╠════════════════════════════════════════╣")
	print("║  Game Development: Solo Developer      ║")
	print("║  Engine: Godot 4.5                     ║")
	print("║  AI Assistant: Claude Code             ║")
	print("║                                        ║")
	print("║  Special Thanks:                       ║")
	print("║  - Godot Community                     ║")
	print("║  - Open Source Contributors            ║")
	print("║                                        ║")
	print("║  Created with passion for              ║")
	print("║  restaurant management simulation!     ║")
	print("╚════════════════════════════════════════╝\n")

func _on_quit_pressed() -> void:
	"""Quit the game."""
	print("[MAIN_MENU] Quitting game...")

	# Fade out before quit
	if panel:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(panel, "modulate:a", 0.0, 0.3)
		await tween.finished

	get_tree().quit()

func on_settings_closed() -> void:
	"""Called when settings menu is closed."""
	panel.visible = true
	if continue_button:
		continue_button.grab_focus()

func _on_load_menu_back_pressed(load_menu: Control) -> void:
	"""Called when load menu back button is pressed."""
	panel.visible = true
	if load_game_button:
		load_game_button.grab_focus()

func set_theme_colors(theme_data: Dictionary) -> void:
	if theme_data.has("background"):
		var new_bg_color = theme_data["background"]
		# Update the bg_colors array for the animation
		bg_colors = [new_bg_color, new_bg_color.lerp(Color.WHITE, 0.1), new_bg_color.lerp(Color.BLACK, 0.1)]
		# Immediately set the background color
		if background_gradient:
			background_gradient.color = new_bg_color
