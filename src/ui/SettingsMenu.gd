extends CanvasLayer
class_name SettingsMenu

## Settings menu UI - volume controls and graphics options

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Title
@onready var master_slider: HSlider = $Panel/MarginContainer/VBoxContainer/AudioSettings/MasterVolume/Slider
@onready var master_value_label: Label = $Panel/MarginContainer/VBoxContainer/AudioSettings/MasterVolume/ValueLabel
@onready var music_slider: HSlider = $Panel/MarginContainer/VBoxContainer/AudioSettings/MusicVolume/Slider
@onready var music_value_label: Label = $Panel/MarginContainer/VBoxContainer/AudioSettings/MusicVolume/ValueLabel
@onready var sfx_slider: HSlider = $Panel/MarginContainer/VBoxContainer/AudioSettings/SFXVolume/Slider
@onready var sfx_value_label: Label = $Panel/MarginContainer/VBoxContainer/AudioSettings/SFXVolume/ValueLabel
@onready var vsync_checkbox: CheckBox = $Panel/MarginContainer/VBoxContainer/GraphicsSettings/VSync/CheckBox
@onready var fullscreen_checkbox: CheckBox = $Panel/MarginContainer/VBoxContainer/GraphicsSettings/Fullscreen/CheckBox
@onready var shadow_quality_option: OptionButton = $Panel/MarginContainer/VBoxContainer/GraphicsSettings/ShadowQuality/OptionButton
@onready var show_fps_checkbox: CheckBox = $Panel/MarginContainer/VBoxContainer/GraphicsSettings/ShowFPS/CheckBox
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/BackButton

var is_open: bool = false
var return_to_menu: Node = null  # Reference to the menu that opened settings
var fps_display: Node = null  # Reference to FPS display

# Audio bus indices
const MASTER_BUS := 0
const MUSIC_BUS := 1
const SFX_BUS := 2

func _ready() -> void:
	# Connect sliders
	if master_slider:
		master_slider.value_changed.connect(_on_master_volume_changed)
	if music_slider:
		music_slider.value_changed.connect(_on_music_volume_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# Connect checkboxes
	if vsync_checkbox:
		vsync_checkbox.toggled.connect(_on_vsync_toggled)
	if fullscreen_checkbox:
		fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	if show_fps_checkbox:
		show_fps_checkbox.toggled.connect(_on_show_fps_toggled)

	# Connect option button
	if shadow_quality_option:
		shadow_quality_option.item_selected.connect(_on_shadow_quality_selected)

	# Find FPS display
	await get_tree().process_frame
	fps_display = get_tree().get_first_node_in_group("fps_display")

	# Connect back button
	if back_button:
		print("[SETTINGS] Connecting back button...")
		back_button.pressed.connect(_on_back_pressed)
		print("[SETTINGS] Back button connected successfully!")
	else:
		push_warning("[SETTINGS] Back button node not found!")

	# Load settings
	_load_settings()

	# Start hidden
	visible = false

func _input(event: InputEvent) -> void:
	if not is_open:
		return

	# Close with Escape
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func show_settings(caller: Node = null) -> void:
	"""Show the settings menu."""
	is_open = true
	visible = true
	return_to_menu = caller

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Pause if not already paused
	if not get_tree().paused:
		get_tree().paused = true

	# Focus first control
	if master_slider:
		master_slider.grab_focus()

func hide_settings() -> void:
	"""Hide the settings menu."""
	print("[SETTINGS] hide_settings() called")
	is_open = false
	visible = false

	# Save settings
	_save_settings()

	# Restore mouse cursor state based on caller
	# If returning to pause menu or main menu, keep cursor visible
	# If returning to gameplay, hide cursor
	if return_to_menu:
		print("[SETTINGS] Returning to menu: ", return_to_menu.name)
		# Keep cursor visible for menus
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		print("[SETTINGS] No return menu, hiding cursor")
		# Hide cursor when returning to gameplay
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Notify the caller
	if return_to_menu and return_to_menu.has_method("on_settings_closed"):
		print("[SETTINGS] Calling on_settings_closed() on ", return_to_menu.name)
		return_to_menu.on_settings_closed()
	else:
		print("[SETTINGS] No return_to_menu or no on_settings_closed method")

	return_to_menu = null
	print("[SETTINGS] Settings menu hidden")

func _load_settings() -> void:
	"""Load settings from config file or set defaults."""
	# Audio settings (check if buses exist)
	var bus_count := AudioServer.bus_count
	var master_volume := 1.0 if bus_count <= MASTER_BUS else _db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS))
	var music_volume := 0.7 if bus_count <= MUSIC_BUS else _db_to_linear(AudioServer.get_bus_volume_db(MUSIC_BUS))
	var sfx_volume := 0.8 if bus_count <= SFX_BUS else _db_to_linear(AudioServer.get_bus_volume_db(SFX_BUS))

	if master_slider:
		master_slider.value = master_volume * 100.0
		_update_volume_label(master_value_label, master_volume)
	if music_slider:
		music_slider.value = music_volume * 100.0
		_update_volume_label(music_value_label, music_volume)
	if sfx_slider:
		sfx_slider.value = sfx_volume * 100.0
		_update_volume_label(sfx_value_label, sfx_volume)

	# Graphics settings
	if vsync_checkbox:
		vsync_checkbox.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	if fullscreen_checkbox:
		fullscreen_checkbox.button_pressed = (
			DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or
			DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		)

	# Shadow quality (default to medium - index 1)
	if shadow_quality_option:
		shadow_quality_option.selected = 1

	# FPS display (default to enabled)
	if show_fps_checkbox:
		show_fps_checkbox.button_pressed = fps_display and fps_display.is_visible

func _save_settings() -> void:
	"""Save settings to config file."""
	# TODO: Implement config file saving
	# For now, settings are applied in real-time and persist in the audio server
	pass

func _on_master_volume_changed(value: float) -> void:
	"""Called when master volume slider changes."""
	var linear_value := value / 100.0
	if AudioServer.bus_count > MASTER_BUS:
		AudioServer.set_bus_volume_db(MASTER_BUS, _linear_to_db(linear_value))
	_update_volume_label(master_value_label, linear_value)

func _on_music_volume_changed(value: float) -> void:
	"""Called when music volume slider changes."""
	var linear_value := value / 100.0
	if AudioServer.bus_count > MUSIC_BUS:
		AudioServer.set_bus_volume_db(MUSIC_BUS, _linear_to_db(linear_value))
	_update_volume_label(music_value_label, linear_value)

func _on_sfx_volume_changed(value: float) -> void:
	"""Called when SFX volume slider changes."""
	var linear_value := value / 100.0
	if AudioServer.bus_count > SFX_BUS:
		AudioServer.set_bus_volume_db(SFX_BUS, _linear_to_db(linear_value))
	_update_volume_label(sfx_value_label, linear_value)

	# Play a test sound
	if AudioManager.instance:
		AudioManager.instance.play_sfx("order_ding")

func _on_vsync_toggled(enabled: bool) -> void:
	"""Called when VSync checkbox is toggled."""
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _on_fullscreen_toggled(enabled: bool) -> void:
	"""Called when fullscreen checkbox is toggled."""
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_shadow_quality_selected(index: int) -> void:
	"""Called when shadow quality option is selected."""
	# TODO: Implement shadow quality changes
	# This would require modifying RenderingServer settings
	match index:
		0:  # Low
			print("Shadow quality set to Low")
		1:  # Medium
			print("Shadow quality set to Medium")
		2:  # High
			print("Shadow quality set to High")
		3:  # Ultra
			print("Shadow quality set to Ultra")

func _on_show_fps_toggled(enabled: bool) -> void:
	"""Called when Show FPS checkbox is toggled."""
	if fps_display and fps_display.has_method("show_fps") and fps_display.has_method("hide_fps"):
		if enabled:
			fps_display.show_fps()
		else:
			fps_display.hide_fps()

func _on_back_pressed() -> void:
	"""Called when back button is pressed."""
	print("[SETTINGS] Back button pressed!")
	hide_settings()

func _update_volume_label(label: Label, value: float) -> void:
	"""Update a volume label with the current percentage."""
	if label:
		label.text = "%d%%" % int(value * 100.0)

func _linear_to_db(linear: float) -> float:
	"""Convert linear volume (0-1) to decibels."""
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

func _db_to_linear(db: float) -> float:
	"""Convert decibels to linear volume (0-1)."""
	if db <= -80.0:
		return 0.0
	return pow(10.0, db / 20.0)
