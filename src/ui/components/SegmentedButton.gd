extends HBoxContainer
class_name SegmentedButton

## Segmented button group for multiple choice options (like Shadow Quality)

signal option_selected(index: int, option_name: String)

@export var options: Array[String] = ["Low", "Medium", "High", "Ultra"]
@export var selected_index: int = 1  # Default to Medium

# Colors (modern flat design with dark theme + gold)
const COLOR_BG_ACTIVE = Color(0.8, 0.6, 0.3, 1.0)           # Gold background
const COLOR_BG_INACTIVE = Color(0.12, 0.10, 0.08, 0.8)      # Dark background
const COLOR_BG_HOVER = Color(0.18, 0.15, 0.12, 1.0)         # Slightly lighter dark
const COLOR_TEXT_ACTIVE = Color(0.08, 0.06, 0.04, 1.0)      # Dark text on gold
const COLOR_TEXT_INACTIVE = Color(0.7, 0.65, 0.55, 0.9)     # Gray text
const COLOR_BORDER = Color(0.8, 0.6, 0.3, 0.3)              # Subtle gold border

var buttons: Array[Button] = []
var particle_burst: PackedScene = null

func _ready() -> void:
	add_theme_constant_override("separation", 4)  # Reduced spacing for flat look
	_create_buttons()
	_update_button_states()

func _create_buttons() -> void:
	"""Create button for each option with flat modern style."""
	for i in range(options.size()):
		var button := Button.new()
		button.text = options[i]
		button.custom_minimum_size = Vector2(90, 42)
		button.flat = true

		# Theme overrides
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", COLOR_TEXT_INACTIVE)

		# Connect signals
		button.pressed.connect(_on_button_pressed.bind(i))
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.mouse_exited.connect(_on_button_unhover.bind(button))

		# Apply flat style
		_apply_flat_style(button, false)

		add_child(button)
		buttons.append(button)

func _apply_flat_style(button: Button, is_active: bool) -> void:
	"""Apply flat modern styling to button."""
	var style = StyleBoxFlat.new()

	if is_active:
		style.bg_color = COLOR_BG_ACTIVE
		button.add_theme_color_override("font_color", COLOR_TEXT_ACTIVE)
	else:
		style.bg_color = COLOR_BG_INACTIVE
		button.add_theme_color_override("font_color", COLOR_TEXT_INACTIVE)

	# Subtle border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_BORDER

	# Flat corners (no rounded for modern look)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6

	# Padding
	style.content_margin_left = 16
	style.content_margin_top = 10
	style.content_margin_right = 16
	style.content_margin_bottom = 10

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

func _on_button_pressed(index: int) -> void:
	"""Handle button press."""
	if index == selected_index:
		return  # Already selected

	selected_index = index
	_update_button_states()

	# Emit signal
	option_selected.emit(index, options[index])

	# Play particle burst effect
	_play_particle_burst(buttons[index])

	# Play selection animation
	_play_selection_animation(buttons[index])

func _update_button_states() -> void:
	"""Update visual state of all buttons."""
	for i in range(buttons.size()):
		var button := buttons[i]
		var is_active = (i == selected_index)
		_apply_flat_style(button, is_active)

		if is_active:
			# Add subtle glow
			_add_glow(button, true)
		else:
			_add_glow(button, false)

func _on_button_hover(button: Button) -> void:
	"""Add hover effect - update background color."""
	if buttons.find(button) != selected_index:
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = COLOR_BG_HOVER
		hover_style.border_width_left = 1
		hover_style.border_width_top = 1
		hover_style.border_width_right = 1
		hover_style.border_width_bottom = 1
		hover_style.border_color = COLOR_BORDER
		hover_style.corner_radius_top_left = 6
		hover_style.corner_radius_top_right = 6
		hover_style.corner_radius_bottom_left = 6
		hover_style.corner_radius_bottom_right = 6
		hover_style.content_margin_left = 16
		hover_style.content_margin_top = 10
		hover_style.content_margin_right = 16
		hover_style.content_margin_bottom = 10

		button.add_theme_stylebox_override("hover", hover_style)

		# Subtle scale
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.15)

func _on_button_unhover(button: Button) -> void:
	"""Remove hover effect."""
	if buttons.find(button) != selected_index:
		_apply_flat_style(button, false)

		# Reset scale
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.15)

func _play_selection_animation(button: Button) -> void:
	"""Play bounce animation on selection."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(button, "scale", Vector2(1.1, 1.1), 0.3)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.3)

func _play_particle_burst(button: Button) -> void:
	"""Play particle burst effect at button center."""
	# TODO: Implement particle effect
	# For now, just a simple flash effect
	var original_modulate = button.modulate
	button.modulate = Color.WHITE
	var tween = create_tween()
	tween.tween_property(button, "modulate", original_modulate, 0.3)

func _add_glow(button: Button, enabled: bool) -> void:
	"""Add or remove glow effect."""
	if enabled:
		# Add pulsing glow for selected button
		var tween = create_tween()
		tween.set_loops()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(button, "modulate:a", 0.8, 1.0)
		tween.tween_property(button, "modulate:a", 1.0, 1.0)
		button.set_meta("glow_tween", tween)
	else:
		# Remove glow
		if button.has_meta("glow_tween"):
			var tween = button.get_meta("glow_tween")
			if tween:
				tween.kill()
			button.remove_meta("glow_tween")

func set_selected(index: int) -> void:
	"""Programmatically set selected option."""
	if index >= 0 and index < options.size():
		selected_index = index
		_update_button_states()

func get_selected() -> int:
	"""Get currently selected index."""
	return selected_index

func get_selected_name() -> String:
	"""Get currently selected option name."""
	return options[selected_index] if selected_index < options.size() else ""
