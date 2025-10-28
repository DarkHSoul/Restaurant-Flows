extends CanvasLayer
class_name SettingsMenu

## Modern settings menu with sidebar navigation

# Nodes
@onready var sidebar_menu = $Panel/MarginContainer/HBoxContainer/Sidebar/SidebarMenu
@onready var close_button = $Panel/MarginContainer/HBoxContainer/Content/Header/CloseButton
@onready var panel = $Panel
@onready var background = $Background

# Category containers
@onready var sound_settings = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings
@onready var graphics_settings = $Panel/MarginContainer/HBoxContainer/Content/Categories/GraphicsSettings
@onready var color_settings = $Panel/MarginContainer/HBoxContainer/Content/Categories/ColorSettings
@onready var gui_settings = $Panel/MarginContainer/HBoxContainer/Content/Categories/GUISettings
@onready var about_settings = $Panel/MarginContainer/HBoxContainer/Content/Categories/AboutSettings

# Sound controls
@onready var master_slider = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/MasterVolume/HBox/Slider
@onready var master_value = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/MasterVolume/HBox/ValueLabel
@onready var music_slider = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/MusicVolume/HBox/Slider
@onready var music_value = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/MusicVolume/HBox/ValueLabel
@onready var sfx_slider = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/SFXVolume/HBox/Slider
@onready var sfx_value = $Panel/MarginContainer/HBoxContainer/Content/Categories/SoundSettings/SFXVolume/HBox/ValueLabel

# Graphics controls
@onready var shadow_quality = $Panel/MarginContainer/HBoxContainer/Content/Categories/GraphicsSettings/ShadowQuality/SegmentedButton
@onready var vsync_toggle = $Panel/MarginContainer/HBoxContainer/Content/Categories/GraphicsSettings/Toggles/VSync/Toggle
@onready var fullscreen_toggle = $Panel/MarginContainer/HBoxContainer/Content/Categories/GraphicsSettings/Toggles/Fullscreen/Toggle
@onready var show_fps_toggle = $Panel/MarginContainer/HBoxContainer/Content/Categories/GraphicsSettings/Toggles/ShowFPS/Toggle

# GUI controls
@onready var gui_scale_slider = $Panel/MarginContainer/HBoxContainer/Content/Categories/GUISettings/GUIScale/HBox/Slider
@onready var gui_scale_value = $Panel/MarginContainer/HBoxContainer/Content/Categories/GUISettings/GUIScale/HBox/ValueLabel

# Color/Theme controls
@onready var theme_buttons_container = $Panel/MarginContainer/HBoxContainer/Content/Categories/ColorSettings/ThemeColor/ThemeButtons

# State
var is_open := false
var return_to_menu: Node = null
var fps_display: Node = null
var current_gui_scale := 1.0
var current_theme := "default"

# Audio bus indices
const MASTER_BUS := 0
const MUSIC_BUS := 1
const SFX_BUS := 2

# Config file path
const CONFIG_PATH := "user://settings.cfg"

# Theme definitions
const THEMES := {
	"default": {
		"name": "🍂 Warm Brown",
		"primary": Color(0.8, 0.6, 0.3),      # Gold accent
		"background": Color(0.15, 0.12, 0.1),  # Dark brown
		"text": Color(1.0, 0.95, 0.85)         # Cream white
	},
	"blue": {
		"name": "🌊 Ocean Blue",
		"primary": Color(0.3, 0.6, 0.9),       # Blue accent
		"background": Color(0.1, 0.12, 0.15),  # Dark blue-gray
		"text": Color(0.9, 0.95, 1.0)          # Ice white
	},
	"green": {
		"name": "🌿 Forest Green",
		"primary": Color(0.4, 0.8, 0.5),       # Green accent
		"background": Color(0.08, 0.12, 0.08), # Dark green
		"text": Color(0.9, 1.0, 0.9)           # Mint white
	},
	"purple": {
		"name": "🌸 Royal Purple",
		"primary": Color(0.7, 0.4, 0.9),       # Purple accent
		"background": Color(0.12, 0.08, 0.15), # Dark purple
		"text": Color(1.0, 0.95, 1.0)          # Lavender white
	},
	"red": {
		"name": "🔥 Fiery Red",
		"primary": Color(0.9, 0.3, 0.3),       # Red accent
		"background": Color(0.15, 0.08, 0.08), # Dark red-brown
		"text": Color(1.0, 0.95, 0.9)          # Warm white
	}
}

func _ready() -> void:
	# Connect sidebar
	sidebar_menu.category_selected.connect(_on_category_selected)

	# Connect close button
	close_button.pressed.connect(_on_close_pressed)

	# Connect audio sliders
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)

	# Connect slider focus events for label animation
	master_slider.focus_entered.connect(_on_slider_focused.bind(master_value))
	master_slider.focus_exited.connect(_on_slider_unfocused.bind(master_value))
	music_slider.focus_entered.connect(_on_slider_focused.bind(music_value))
	music_slider.focus_exited.connect(_on_slider_unfocused.bind(music_value))
	sfx_slider.focus_entered.connect(_on_slider_focused.bind(sfx_value))
	sfx_slider.focus_exited.connect(_on_slider_unfocused.bind(sfx_value))

	# Connect graphics controls
	shadow_quality.option_selected.connect(_on_shadow_changed)
	vsync_toggle.state_changed.connect(_on_vsync_changed)
	fullscreen_toggle.state_changed.connect(_on_fullscreen_changed)
	show_fps_toggle.state_changed.connect(_on_show_fps_changed)

	# Connect GUI scale
	gui_scale_slider.value_changed.connect(_on_gui_scale_changed)
	gui_scale_slider.focus_entered.connect(_on_slider_focused.bind(gui_scale_value))
	gui_scale_slider.focus_exited.connect(_on_slider_unfocused.bind(gui_scale_value))

	# Find FPS display
	await get_tree().process_frame
	fps_display = get_tree().get_first_node_in_group("fps_display")

	# Load settings
	_load_settings()

	# Create theme buttons
	_create_theme_buttons()

	# Setup focus
	_setup_focus()

	# Start hidden
	visible = false

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func show_settings(caller: Node = null) -> void:
	is_open = true
	visible = true
	return_to_menu = caller
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Only pause if not already paused (e.g., coming from main menu)
	# If called from PauseMenu, game is already paused
	if not get_tree().paused:
		get_tree().paused = true

	# Show Graphics Settings by default
	_on_category_selected("graphics")

	# Give focus to Graphics Settings button (index 1) for keyboard navigation
	await get_tree().process_frame
	if sidebar_menu and sidebar_menu.buttons.size() > 1:
		sidebar_menu.buttons[1].grab_focus()  # Graphics Settings is index 1

func hide_settings() -> void:
	is_open = false
	visible = false
	_save_settings()

	# Check if we should unpause
	# If return_to_menu is PauseMenu, don't unpause (game should stay paused)
	# If return_to_menu is null or MainMenu, unpause
	var should_unpause := true
	if return_to_menu and return_to_menu.has_method("show_pause_menu"):
		# This is PauseMenu - keep game paused
		should_unpause = false

	if get_tree().paused and should_unpause:
		get_tree().paused = false

	if return_to_menu:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if return_to_menu and return_to_menu.has_method("on_settings_closed"):
		return_to_menu.on_settings_closed()

	return_to_menu = null

func _on_category_selected(category_id: String) -> void:
	# Hide all categories
	sound_settings.visible = false
	graphics_settings.visible = false
	color_settings.visible = false
	gui_settings.visible = false
	about_settings.visible = false

	# Show selected category with fade
	var category_node: Control
	match category_id:
		"sound":
			category_node = sound_settings
		"graphics":
			category_node = graphics_settings
		"color":
			category_node = color_settings
		"gui":
			category_node = gui_settings
		"about":
			category_node = about_settings

	if category_node:
		category_node.visible = true
		category_node.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(category_node, "modulate:a", 1.0, 0.2)

		var first_focusable = _get_first_focusable_child(category_node)
		if first_focusable:
			for button in sidebar_menu.buttons:
				button.focus_neighbor_right = button.get_path_to(first_focusable)

func _get_first_focusable_child(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			return child
		var focusable_child = _get_first_focusable_child(child)
		if focusable_child:
			return focusable_child
	return null

func _setup_focus() -> void:
	# Sound Settings
	var sound_button = sidebar_menu.get_button_by_category("sound")
	master_slider.focus_neighbor_left = master_slider.get_path_to(sound_button)
	music_slider.focus_neighbor_left = music_slider.get_path_to(sound_button)
	sfx_slider.focus_neighbor_left = sfx_slider.get_path_to(sound_button)
	sound_button.focus_neighbor_right = sound_button.get_path_to(master_slider)

	master_slider.focus_neighbor_top = master_slider.get_path_to(master_slider)
	master_slider.focus_neighbor_bottom = master_slider.get_path_to(music_slider)
	music_slider.focus_neighbor_top = music_slider.get_path_to(master_slider)
	music_slider.focus_neighbor_bottom = music_slider.get_path_to(sfx_slider)
	sfx_slider.focus_neighbor_top = sfx_slider.get_path_to(music_slider)
	sfx_slider.focus_neighbor_bottom = sfx_slider.get_path_to(sfx_slider)

	# Graphics Settings
	var graphics_button = sidebar_menu.get_button_by_category("graphics")
	var shadow_buttons = shadow_quality.get_children()
	for i in range(shadow_buttons.size()):
		var button = shadow_buttons[i]
		if i == 0:
			button.focus_neighbor_left = button.get_path_to(graphics_button)
		else:
			button.focus_neighbor_left = button.get_path_to(shadow_buttons[i-1])
		if i < shadow_buttons.size() - 1:
			button.focus_neighbor_right = button.get_path_to(shadow_buttons[i+1])
		else:
			button.focus_neighbor_right = button.get_path_to(button)

	vsync_toggle.focus_neighbor_left = vsync_toggle.get_path_to(graphics_button)
	vsync_toggle.focus_neighbor_right = vsync_toggle.get_path_to(fullscreen_toggle)
	fullscreen_toggle.focus_neighbor_left = fullscreen_toggle.get_path_to(vsync_toggle)
	fullscreen_toggle.focus_neighbor_right = fullscreen_toggle.get_path_to(fullscreen_toggle)
	show_fps_toggle.focus_neighbor_left = show_fps_toggle.get_path_to(graphics_button)
	show_fps_toggle.focus_neighbor_right = show_fps_toggle.get_path_to(show_fps_toggle)
	if not shadow_buttons.is_empty():
		graphics_button.focus_neighbor_right = graphics_button.get_path_to(shadow_buttons[0])

	shadow_buttons[0].focus_neighbor_top = shadow_buttons[0].get_path_to(shadow_buttons[0])
	shadow_buttons[0].focus_neighbor_bottom = shadow_buttons[0].get_path_to(vsync_toggle)
	vsync_toggle.focus_neighbor_top = vsync_toggle.get_path_to(shadow_buttons[0])
	vsync_toggle.focus_neighbor_bottom = vsync_toggle.get_path_to(show_fps_toggle)
	fullscreen_toggle.focus_neighbor_top = fullscreen_toggle.get_path_to(vsync_toggle)
	fullscreen_toggle.focus_neighbor_bottom = fullscreen_toggle.get_path_to(show_fps_toggle)
	show_fps_toggle.focus_neighbor_top = show_fps_toggle.get_path_to(vsync_toggle)
	show_fps_toggle.focus_neighbor_bottom = show_fps_toggle.get_path_to(show_fps_toggle)

	# GUI Settings
	var gui_button = sidebar_menu.get_button_by_category("gui")
	gui_scale_slider.focus_neighbor_left = gui_scale_slider.get_path_to(gui_button)
	gui_button.focus_neighbor_right = gui_button.get_path_to(gui_scale_slider)
	gui_scale_slider.focus_neighbor_top = gui_scale_slider.get_path_to(gui_scale_slider)
	gui_scale_slider.focus_neighbor_bottom = gui_scale_slider.get_path_to(gui_scale_slider)

	# Color Settings
	var color_button = sidebar_menu.get_button_by_category("color")
	var theme_buttons = theme_buttons_container.get_children()
	for i in range(theme_buttons.size()):
		var button = theme_buttons[i]
		button.focus_neighbor_left = button.get_path_to(color_button)
		if i > 0:
			button.focus_neighbor_top = button.get_path_to(theme_buttons[i-1])
		else:
			button.focus_neighbor_top = button.get_path_to(button)
		if i < theme_buttons.size() - 1:
			button.focus_neighbor_bottom = button.get_path_to(theme_buttons[i+1])
		else:
			button.focus_neighbor_bottom = button.get_path_to(button)
	if not theme_buttons.is_empty():
		color_button.focus_neighbor_right = color_button.get_path_to(theme_buttons[0])

	# About Settings
	var about_button = sidebar_menu.get_button_by_category("about")
	var TermsButton = about_settings.get_node("Links/TermsButton")
	var HelpButton = about_settings.get_node("Links/HelpButton")
	var CreditsButton = about_settings.get_node("Links/CreditsButton")
	TermsButton.focus_neighbor_left = TermsButton.get_path_to(about_button)
	HelpButton.focus_neighbor_left = HelpButton.get_path_to(about_button)
	CreditsButton.focus_neighbor_left = CreditsButton.get_path_to(about_button)
	about_button.focus_neighbor_right = about_button.get_path_to(TermsButton)

	TermsButton.focus_neighbor_top = TermsButton.get_path_to(TermsButton)
	TermsButton.focus_neighbor_bottom = TermsButton.get_path_to(HelpButton)
	HelpButton.focus_neighbor_top = HelpButton.get_path_to(TermsButton)
	HelpButton.focus_neighbor_bottom = HelpButton.get_path_to(CreditsButton)
	CreditsButton.focus_neighbor_top = CreditsButton.get_path_to(HelpButton)
	CreditsButton.focus_neighbor_bottom = CreditsButton.get_path_to(CreditsButton)

func _on_close_pressed() -> void:
	hide_settings()

# Audio callbacks
func _on_master_changed(value: float) -> void:
	var linear := value / 100.0
	if AudioServer.bus_count > MASTER_BUS:
		AudioServer.set_bus_volume_db(MASTER_BUS, _linear_to_db(linear))
	master_value.text = "%d%%" % int(value)

func _on_music_changed(value: float) -> void:
	var linear := value / 100.0
	if AudioServer.bus_count > MUSIC_BUS:
		AudioServer.set_bus_volume_db(MUSIC_BUS, _linear_to_db(linear))
	music_value.text = "%d%%" % int(value)

func _on_sfx_changed(value: float) -> void:
	var linear := value / 100.0
	if AudioServer.bus_count > SFX_BUS:
		AudioServer.set_bus_volume_db(SFX_BUS, _linear_to_db(linear))
	sfx_value.text = "%d%%" % int(value)

# Graphics callbacks
func _on_shadow_changed(_index: int, _option_name: String) -> void:
	pass  # TODO: Implement shadow quality

func _on_vsync_changed(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _on_fullscreen_changed(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_show_fps_changed(enabled: bool) -> void:
	if fps_display:
		if enabled and fps_display.has_method("show_fps"):
			fps_display.show_fps()
		elif not enabled and fps_display.has_method("hide_fps"):
			fps_display.hide_fps()

# GUI callbacks
func _on_gui_scale_changed(value: float) -> void:
	current_gui_scale = value
	gui_scale_value.text = "%.1fx" % value
	panel.scale = Vector2(value, value)

# Settings persistence
func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)

	if err != OK:
		# Set defaults
		master_slider.value = 100.0
		music_slider.value = 70.0
		sfx_slider.value = 80.0
		gui_scale_slider.value = 1.0
		return

	# Load audio
	master_slider.value = config.get_value("audio", "master", 100.0)
	music_slider.value = config.get_value("audio", "music", 70.0)
	sfx_slider.value = config.get_value("audio", "sfx", 80.0)

	# Load graphics
	var vsync = config.get_value("graphics", "vsync", true)
	vsync_toggle.set_state(vsync)

	var is_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_toggle.set_state(is_fullscreen)

	var show_fps = config.get_value("graphics", "show_fps", true)
	show_fps_toggle.set_state(show_fps)

	var shadow = config.get_value("graphics", "shadow_quality", 1)
	shadow_quality.set_selected(shadow)

	# Load GUI
	var gui_scale = config.get_value("gui", "scale", 1.0)
	gui_scale_slider.value = gui_scale

	# Load theme
	var theme = config.get_value("appearance", "theme", "default")
	current_theme = theme
	_on_theme_selected(theme)

func _save_settings() -> void:
	var config = ConfigFile.new()

	# Save audio
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)

	# Save graphics
	config.set_value("graphics", "vsync", vsync_toggle.is_on)
	config.set_value("graphics", "fullscreen", fullscreen_toggle.is_on)
	config.set_value("graphics", "show_fps", show_fps_toggle.is_on)
	config.set_value("graphics", "shadow_quality", shadow_quality.get_selected())

	# Save GUI
	config.set_value("gui", "scale", gui_scale_slider.value)

	# Save theme
	config.set_value("appearance", "theme", current_theme)

	config.save(CONFIG_PATH)

# Helper functions
func _linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

func _db_to_linear(db: float) -> float:
	if db <= -80.0:
		return 0.0
	return pow(10.0, db / 20.0)

# Slider label animation functions
func _on_slider_focused(label: Label) -> void:
	"""Enlarge label text when slider gains focus."""
	if not label:
		return

	# Get original font size (default is 16)
	var original_size = 16
	if label.has_theme_font_size_override("font_size"):
		original_size = label.get_theme_font_size("font_size")

	var target_size = int(original_size * 1.15)  # 15% larger to prevent blur

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)  # Smoother transition
	tween.tween_method(func(size): label.add_theme_font_size_override("font_size", size), original_size, target_size, 0.15)

	# Store tween for cleanup
	label.set_meta("font_tween", tween)

func _create_theme_buttons() -> void:
	"""Create theme selection buttons."""
	if not theme_buttons_container:
		return

	# Create a button for each theme
	for theme_id in THEMES.keys():
		var theme_data = THEMES[theme_id]
		var button = Button.new()

		button.text = theme_data["name"]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.flat = true

		# Style the button
		var style = StyleBoxFlat.new()
		style.bg_color = theme_data["background"]
		style.border_width_left = 4
		style.border_color = theme_data["primary"]
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 15
		style.content_margin_top = 10
		style.content_margin_right = 15
		style.content_margin_bottom = 10

		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_color_override("font_color", theme_data["text"])
		button.add_theme_font_size_override("font_size", 20)

		# Connect signal
		button.pressed.connect(_on_theme_selected.bind(theme_id))

		# Store theme ID in metadata
		button.set_meta("theme_id", theme_id)

		theme_buttons_container.add_child(button)

	# Highlight current theme
	_update_theme_buttons()

	# Setup focus wrapping for the buttons
	if theme_buttons_container.get_child_count() > 1:
		var first_button = theme_buttons_container.get_child(0)
		var last_button = theme_buttons_container.get_child(theme_buttons_container.get_child_count() - 1)
		first_button.focus_neighbor_top = first_button.get_path_to(last_button)
		last_button.focus_neighbor_bottom = last_button.get_path_to(first_button)

func _on_theme_selected(theme_id: String) -> void:
	"""Apply selected theme to the settings menu."""
	if not THEMES.has(theme_id):
		return

	current_theme = theme_id
	var theme_data = THEMES[theme_id]

	# Apply theme colors to the settings panel
	if panel:
		# Update panel background
		var panel_style = panel.get_theme_stylebox("panel")
		if panel_style is StyleBoxFlat:
			var new_style = panel_style.duplicate()
			new_style.bg_color = theme_data["background"]
			new_style.border_color = theme_data["primary"]
			panel.add_theme_stylebox_override("panel", new_style)

	# Update background color
	if background:
		background.color = theme_data["background"]

	# Update theme buttons to show selected state
	_update_theme_buttons()

	# Propagate theme to MainMenu if it exists
	if return_to_menu and return_to_menu.has_method("set_theme_colors"):
		return_to_menu.set_theme_colors(theme_data)

	# Save immediately
	_save_settings()

func _update_theme_buttons() -> void:
	"""Update theme button appearances to show selected state."""
	if not theme_buttons_container:
		return

	for button in theme_buttons_container.get_children():
		if not button is Button:
			continue

		var theme_id = button.get_meta("theme_id", "")
		var theme_data = THEMES.get(theme_id, {})
		if theme_data.is_empty():
			continue

		var is_selected = theme_id == current_theme

		# Create style
		var style = StyleBoxFlat.new()
		style.bg_color = theme_data["background"]
		style.border_width_left = 4 if is_selected else 2
		style.border_width_top = 2 if is_selected else 0
		style.border_width_right = 2 if is_selected else 0
		style.border_width_bottom = 2 if is_selected else 0
		style.border_color = theme_data["primary"]
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 15
		style.content_margin_top = 10
		style.content_margin_right = 15
		style.content_margin_bottom = 10

		# Add glow effect for selected theme
		if is_selected:
			style.shadow_size = 8
			style.shadow_color = Color(theme_data["primary"].r, theme_data["primary"].g, theme_data["primary"].b, 0.6)

		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_color_override("font_color", theme_data["text"])

func _on_slider_unfocused(label: Label) -> void:
	"""Reset label text when slider loses focus."""
	if not label:
		return

	# Kill existing tween if any
	if label.has_meta("font_tween"):
		var old_tween = label.get_meta("font_tween")
		if old_tween:
			old_tween.kill()

	# Get current size
	var current_size = 16
	if label.has_theme_font_size_override("font_size"):
		current_size = label.get_theme_font_size("font_size")

	var original_size = 16

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(size): label.add_theme_font_size_override("font_size", size), current_size, original_size, 0.12)
