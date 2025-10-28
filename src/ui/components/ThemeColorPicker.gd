extends HBoxContainer
class_name ThemeColorPicker

## Theme color picker with predefined color options

signal color_selected(color: Color, color_name: String)

# Predefined theme colors
const THEME_COLORS := {
	"Gold": Color(0.8, 0.6, 0.3, 1.0),
	"Blue": Color(0.3, 0.6, 0.9, 1.0),
	"Green": Color(0.4, 0.8, 0.5, 1.0),
	"Red": Color(0.9, 0.4, 0.4, 1.0),
	"Purple": Color(0.7, 0.4, 0.9, 1.0),
	"Cyan": Color(0.3, 0.8, 0.9, 1.0)
}

var color_buttons: Array[Button] = []
var selected_color_name: String = "Gold"

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_create_color_buttons()

func _create_color_buttons() -> void:
	"""Create a button for each predefined color."""
	for color_name in THEME_COLORS.keys():
		var button := Button.new()
		var color: Color = THEME_COLORS[color_name]

		# Button setup
		button.custom_minimum_size = Vector2(50, 50)
		button.flat = true

		# Store color info in metadata
		button.set_meta("color", color)
		button.set_meta("color_name", color_name)

		# Styling
		_style_color_button(button, color, color_name == selected_color_name)

		# Connect signals
		button.pressed.connect(_on_color_button_pressed.bind(color_name))
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.mouse_exited.connect(_on_button_unhover.bind(button))

		add_child(button)
		color_buttons.append(button)

func _on_color_button_pressed(color_name: String) -> void:
	"""Handle color button press."""
	selected_color_name = color_name
	var color: Color = THEME_COLORS[color_name]

	# Update all button states
	for button in color_buttons:
		var button_color_name = button.get_meta("color_name")
		var button_color = button.get_meta("color")
		_style_color_button(button, button_color, button_color_name == color_name)

	# Emit signal
	color_selected.emit(color, color_name)

func _style_color_button(button: Button, color: Color, is_selected: bool) -> void:
	"""Apply styling to a color button."""
	var style = StyleBoxFlat.new()
	style.bg_color = color

	# Rounded circle
	style.corner_radius_top_left = 25
	style.corner_radius_top_right = 25
	style.corner_radius_bottom_left = 25
	style.corner_radius_bottom_right = 25

	if is_selected:
		# Add thick border for selected color
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = Color(1.0, 0.95, 0.85, 1.0)  # Light cream border

		# Add glow shadow
		style.shadow_color = color
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 0)
	else:
		# Subtle border for unselected
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.2, 0.2, 0.2, 0.6)

		# No shadow
		style.shadow_size = 0

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

func _on_button_hover(button: Button) -> void:
	"""Add scale effect on hover."""
	if button.has_meta("hover_tween"):
		var old_tween = button.get_meta("hover_tween")
		if old_tween:
			old_tween.kill()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(button, "scale", Vector2(1.15, 1.15), 0.3)
	button.set_meta("hover_tween", tween)

func _on_button_unhover(button: Button) -> void:
	"""Reset scale when hover ends."""
	var button_color_name = button.get_meta("color_name")
	if button_color_name == selected_color_name:
		return  # Keep selected button scaled

	if button.has_meta("hover_tween"):
		var old_tween = button.get_meta("hover_tween")
		if old_tween:
			old_tween.kill()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.2)
	button.set_meta("hover_tween", tween)

func set_selected_color(color_name: String) -> void:
	"""Set the selected color by name."""
	if color_name in THEME_COLORS:
		_on_color_button_pressed(color_name)

func get_selected_color() -> Color:
	"""Get the currently selected color."""
	return THEME_COLORS[selected_color_name]

func get_selected_color_name() -> String:
	"""Get the currently selected color name."""
	return selected_color_name
